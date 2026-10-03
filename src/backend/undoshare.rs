// One undo history for every Flea window; see AGENTS.md "Write operations and the undo journal".
use super::undorebase::RebaseMap;
use super::undostage::{read, Read, Staged};
use crate::backend::manifestdir::current_uid;
use crate::backend::redo::Replay;
use crate::backend::undo::{Entry, ItemIdentity, Step, DEPTH};
use crate::error::FleaError;
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

// Past twice the largest benched tree in manifest bytes the file is foreign, as copymanifest refuses its stream.
pub(crate) const MAX_FILE_BYTES: u64 = 32 * 1024 * 1024;
// The redo stack is unbounded in memory, but a file without a cap is not, so it caps here.
const MAX_REDOS: usize = 50;
pub(crate) const JOURNAL_FILE: &str = "undo-journal";
const LOCK_FILE: &str = "undo-journal.lock";
const DIR_MODE: u32 = 0o700;

#[derive(Clone, Debug)]
pub(crate) struct Shared {
    dir: PathBuf,
}

impl Shared {
    // FLEA_UNDO_DIR isolates one test run when set; otherwise the session dir under XDG_RUNTIME_DIR.
    pub(crate) fn from_env() -> Option<Shared> {
        if let Some(dir) = crate::userfile::env_dir("FLEA_UNDO_DIR") {
            return Self::at(dir);
        }
        let runtime = crate::userfile::env_dir("XDG_RUNTIME_DIR")?;
        Self::at(runtime.join("flea"))
    }

    // Tests take their directories as arguments, never a process-wide variable another test reads.
    pub(crate) fn at(dir: PathBuf) -> Option<Shared> {
        match validate_dir(&dir) {
            Ok(()) => Some(Shared { dir }),
            Err(msg) => {
                eprintln!("flea: {}", msg);
                None
            }
        }
    }

    fn journal_path(&self) -> PathBuf {
        self.dir.join(JOURNAL_FILE)
    }

    fn lock_path(&self) -> PathBuf {
        self.dir.join(LOCK_FILE)
    }
}

// Created owner-only and re-read rather than trusted, so a planted symlink loses like manifestdir.
fn validate_dir(dir: &Path) -> Result<(), String> {
    if dir.as_os_str().is_empty() {
        return Err("the shared undo directory is empty, so undo stays in this process".to_string());
    }
    match dir.symlink_metadata() {
        Ok(meta) if meta.file_type().is_symlink() => {
            return Err(format!("{} is a symbolic link, so undo stays in this process", dir.display()))
        }
        Ok(meta) if !meta.is_dir() => {
            return Err(format!("{} is not a directory, so undo stays in this process", dir.display()))
        }
        Ok(_) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            std::fs::DirBuilder::new().recursive(true).mode(DIR_MODE).create(dir).map_err(|e| {
                format!("{} could not be created, so undo stays in this process ({:?})", dir.display(), e.kind())
            })?;
        }
        Err(e) => {
            return Err(format!("{} could not be read, so undo stays in this process ({:?})", dir.display(), e.kind()))
        }
    }
    let meta = dir.symlink_metadata().map_err(|e| {
        format!("{} could not be re-read, so undo stays in this process ({:?})", dir.display(), e.kind())
    })?;
    if meta.file_type().is_symlink() {
        return Err(format!("{} is a symbolic link, so undo stays in this process", dir.display()));
    }
    if !meta.is_dir() {
        return Err(format!("{} is not a directory, so undo stays in this process", dir.display()));
    }
    if meta.uid() != current_uid() {
        return Err(format!("{} is not owned by this user, so undo stays in this process", dir.display()));
    }
    if meta.permissions().mode() & 0o077 != 0 {
        return Err(format!("{} is accessible to group or others, so undo stays in this process", dir.display()));
    }
    Ok(())
}

// Held across one read-modify-write; dropping it releases the flock, so a dead process keeps nothing.
struct Guard {
    _file: std::fs::File,
}

fn lock(shared: &Shared) -> Result<Guard, String> {
    validate_dir(&shared.dir)?;
    let file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(crate::oflags::O_NOFOLLOW)
        .open(shared.lock_path())
        .map_err(|e| format!("the shared undo lock could not be opened ({:?})", e.kind()))?;
    crate::uistore::lock_exclusive(&file)
        .map_err(|e| format!("the shared undo lock could not be taken ({:?})", e.kind()))?;
    Ok(Guard { _file: file })
}

// A stored Err replay answers its error when taken, exactly as the in-memory pop answers it.
pub(crate) enum StoredRedo {
    Ok(Replay),
    Err(FleaError),
}

pub(crate) struct Doc {
    pub undo: Vec<Entry>,
    pub redo: Vec<StoredRedo>,
    // Counts pushes; a finish replays only when no push ran since its claim.
    pub push_gen: u64,
}

pub(crate) enum PushResult { Stored, TooBig }

fn empty_doc() -> Doc {
    Doc { undo: Vec::new(), redo: Vec::new(), push_gen: 0 }
}

// A newer writer owns the file when its version reads past this reader's own.
fn is_newer_file(shared: &Shared) -> bool {
    let Ok(text) = std::fs::read_to_string(shared.journal_path()) else { return false };
    #[cfg(test)]
    super::undoprobe::read(text.len());
    super::undocodec::is_newer_version(&text)
}

// An ignored file is still a newer writer's when it parses as one, so every ignore path asks.
fn ignored(shared: &Shared) -> Result<Doc, ()> {
    if is_newer_file(shared) { Err(()) } else { Ok(empty_doc()) }
}

// One read and one parse; malformed is ignored with a log line, Err is a newer writer's file.
fn load(shared: &Shared) -> Result<Doc, ()> {
    let path = shared.journal_path();
    let meta = match path.symlink_metadata() {
        Ok(meta) => meta,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(empty_doc()),
        Err(e) => {
            eprintln!("flea: the shared undo journal could not be read ({:?}), so it was ignored", e.kind());
            return ignored(shared);
        }
    };
    if meta.file_type().is_symlink() {
        eprintln!("flea: the shared undo journal is a symbolic link, so it was ignored");
        return ignored(shared);
    }
    if meta.uid() != current_uid() {
        eprintln!("flea: the shared undo journal is not owned by this user, so it was ignored");
        return ignored(shared);
    }
    let file = match std::fs::File::open(&path) {
        Ok(file) => file,
        Err(e) => {
            eprintln!("flea: the shared undo journal could not be read ({:?}), so it was ignored", e.kind());
            return ignored(shared);
        }
    };
    let mut bytes = Vec::new();
    use std::io::Read as _;
    if file.take(MAX_FILE_BYTES + 1).read_to_end(&mut bytes).is_err() {
        eprintln!("flea: the shared undo journal could not be read, so it was ignored");
        return ignored(shared);
    }
    if bytes.len() as u64 > MAX_FILE_BYTES {
        eprintln!("flea: the shared undo journal is oversized, so it was ignored");
        return ignored(shared);
    }
    #[cfg(test)]
    super::undoprobe::read(bytes.len());
    let text = match String::from_utf8(bytes) {
        Ok(text) => text,
        Err(_) => {
            eprintln!("flea: the shared undo journal is not valid UTF-8, so it was ignored");
            return ignored(shared);
        }
    };
    #[cfg(test)]
    super::undoprobe::decode();
    match read(&text) {
        Read::Doc(doc) => Ok(doc),
        Read::Newer => Err(()),
        Read::Malformed => {
            eprintln!("flea: the shared undo journal is malformed, so it was ignored");
            Ok(empty_doc())
        }
    }
}

// Exclusive temp plus rename last, so a reader sees a complete file or none at all.
fn store(shared: &Shared, text: &str) -> Result<(), String> {
    let dest = shared.journal_path();
    let tmp = shared.dir.join(format!("{}.{}.tmp", JOURNAL_FILE, std::process::id()));
    let _ = std::fs::remove_file(&tmp);
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .custom_flags(crate::oflags::O_NOFOLLOW)
        .open(&tmp)
        .map_err(|e| format!("the shared undo journal could not be written ({:?})", e.kind()))?;
    use std::io::Write;
    #[cfg(test)]
    super::undoprobe::wrote(text.len());
    if file.write_all(text.as_bytes()).is_err() {
        let _ = std::fs::remove_file(&tmp);
        return Err("the shared undo journal could not be written".to_string());
    }
    drop(file);
    std::fs::rename(&tmp, &dest)
        .map_err(|e| format!("the shared undo journal could not be published ({:?})", e.kind()))
}

// One walk of the document for the whole batch of moves, however many there are.
fn rebase_doc<'a>(doc: &mut Doc, pairs: impl IntoIterator<Item = (&'a ItemIdentity, &'a ItemIdentity)>) {
    let map = RebaseMap::new(pairs);
    if map.is_empty() {
        return;
    }
    for entry in &mut doc.undo {
        entry.rebase_with(&mut |identity| map.moved(identity));
    }
    for stored in &mut doc.redo {
        if let StoredRedo::Ok(replay) = stored {
            replay.rebase_with(&mut |identity| map.moved(identity), &mut |identity| map.item(identity));
        }
    }
}

// Renders the document once and trims by the sizes of its pieces; None when the newest record alone is over the cap.
fn staged_to_fit(doc: &Doc) -> Option<Staged> {
    let mut staged = Staged::new(doc);
    staged.trim_to(MAX_FILE_BYTES);
    staged.fits(MAX_FILE_BYTES).then_some(staged)
}

pub(crate) fn push_entry(shared: &Shared, entry: &Entry) -> Result<PushResult, ()> {
    if entry.steps.is_empty() {
        return Ok(PushResult::Stored);
    }
    let _guard = lock(shared).map_err(|msg| eprintln!("flea: {}", msg))?;
    // A newer file is unavailable, never rewritten: the caller falls back to memory.
    let mut doc = load(shared)?;
    rebase_doc(&mut doc, entry.steps.iter().filter_map(|step| match step {
        Step::Moved { before, after, .. } => Some((before, after)),
        _ => None,
    }));
    doc.undo.push(entry.clone());
    while doc.undo.len() > DEPTH {
        doc.undo.remove(0);
    }
    doc.redo.clear();
    doc.push_gen = doc.push_gen.wrapping_add(1);
    let Some(staged) = staged_to_fit(&doc) else { return Ok(PushResult::TooBig) };
    store(shared, &staged.text()).map_err(|msg| eprintln!("flea: {}", msg))?;
    Ok(PushResult::Stored)
}

// Every nonce the doc still names, so a journal drops handles for entries it no longer holds.
pub(crate) fn live_nonces(shared: &Shared) -> Option<std::collections::HashSet<u64>> {
    let _guard = lock(shared).map_err(|msg| eprintln!("flea: {}", msg)).ok()?;
    let doc = load(shared).ok()?;
    let mut live = std::collections::HashSet::new();
    for entry in &doc.undo {
        for step in &entry.steps {
            if let Step::Copied { manifest_nonce: Some(nonce), .. } = step {
                live.insert(*nonce);
            }
        }
    }
    for stored in &doc.redo {
        if let StoredRedo::Ok(replay) = stored {
            for (step, _, _) in replay.steps_data().1 {
                if let Step::Copied { manifest_nonce: Some(nonce), .. } = &step {
                    live.insert(*nonce);
                }
            }
        }
    }
    Some(live)
}

// One locked read-modify-write pops the newest entry; the generation lets finish drop a stale replay.
pub(crate) fn claim_undo(shared: &Shared) -> Result<Option<(Entry, u64)>, ()> {
    let _guard = lock(shared).map_err(|msg| eprintln!("flea: {}", msg))?;
    let mut doc = load(shared)?;
    let claimed = doc.undo.pop();
    if claimed.is_some() {
        store(shared, &Staged::new(&doc).text()).map_err(|msg| eprintln!("flea: {}", msg))?;
    }
    Ok(claimed.map(|entry| (entry, doc.push_gen)))
}

// The entry is spent whether the reversal worked or not; a replay lands only with no push since claim.
pub(crate) fn finish_undone(shared: &Shared, entry: Option<Entry>, changes: &[(ItemIdentity, ItemIdentity)], claimed_gen: u64) -> Result<(), ()> {
    let _guard = lock(shared).map_err(|msg| eprintln!("flea: {}", msg))?;
    let mut doc = load(shared)?;
    rebase_doc(&mut doc, changes.iter().map(|(old, new)| (old, new)));
    if let Some(entry) = entry {
        if doc.push_gen == claimed_gen {
            match Replay::capture(entry) {
                Ok(replay) => doc.redo.push(StoredRedo::Ok(replay)),
                Err(error) => doc.redo.push(StoredRedo::Err(error)),
            }
            while doc.redo.len() > MAX_REDOS {
                doc.redo.remove(0);
            }
        }
    }
    let mut staged = Staged::new(&doc);
    staged.trim_to(MAX_FILE_BYTES);
    if !staged.fits(MAX_FILE_BYTES) && staged.drop_newest_redo() {
        // The replay alone overflowed; keep history without it rather than publishing oversize.
        staged.trim_to(MAX_FILE_BYTES);
    }
    if !staged.fits(MAX_FILE_BYTES) {
        return Ok(());
    }
    store(shared, &staged.text()).map_err(|msg| eprintln!("flea: {}", msg))?;
    Ok(())
}

pub(crate) fn redo_info(shared: &Shared) -> Result<(String, usize), FleaError> {
    let _guard = lock(shared).map_err(|msg| {
        eprintln!("flea: {}", msg);
    }).map_err(|_| FleaError { where_: "redo".into(), path: String::new(), msg: "the shared undo journal is unavailable".into() })?;
    let doc = load(shared).map_err(|()| FleaError { where_: "redo".into(), path: String::new(), msg: "the shared undo journal is unavailable".into() })?;
    match doc.redo.last() {
        Some(StoredRedo::Ok(replay)) => Ok((replay.op().to_string(), replay.len())),
        Some(StoredRedo::Err(error)) => {
            Err(FleaError { where_: "redo".into(), path: error.path.clone(), msg: error.msg.clone() })
        }
        None => Err(FleaError { where_: "redo".into(), path: String::new(), msg: "there is nothing to redo".into() }),
    }
}

pub(crate) fn claim_redo(shared: &Shared) -> Result<Option<StoredRedo>, ()> {
    let _guard = lock(shared).map_err(|msg| eprintln!("flea: {}", msg))?;
    let mut doc = load(shared)?;
    let claimed = doc.redo.pop();
    if claimed.is_some() {
        store(shared, &Staged::new(&doc).text()).map_err(|msg| eprintln!("flea: {}", msg))?;
    }
    Ok(claimed)
}

// Mirrors Journal::redo's tail: the redone entry rejoins the undo stack, and a failed redo clears it.
pub(crate) fn finish_redone(shared: &Shared, entry: Entry, changes: &[(ItemIdentity, ItemIdentity)], failed: bool) -> Result<(), ()> {
    let _guard = lock(shared).map_err(|msg| eprintln!("flea: {}", msg))?;
    let mut doc = load(shared)?;
    rebase_doc(&mut doc, changes.iter().map(|(old, new)| (old, new)));
    if !entry.steps.is_empty() {
        doc.undo.push(entry);
        while doc.undo.len() > DEPTH {
            doc.undo.remove(0);
        }
    }
    if failed {
        doc.redo.clear();
    }
    let Some(staged) = staged_to_fit(&doc) else { return Ok(()) };
    store(shared, &staged.text()).map_err(|msg| eprintln!("flea: {}", msg))?;
    Ok(())
}

pub(crate) fn redo_newest(slot: &mut Option<Shared>, id: usize, cancel: &std::sync::atomic::AtomicBool,
    tx: &std::sync::mpsc::Sender<super::opsreq::OpMsg>) -> Result<String, FleaError> {
    let Some(shared) = slot.clone() else {
        return Err(FleaError { where_: "redo".into(), path: String::new(), msg: "there is nothing to redo".into() });
    };
    let claimed = match claim_redo(&shared) {
        Ok(claimed) => claimed,
        Err(()) => {
            *slot = None;
            return Err(FleaError { where_: "redo".into(), path: String::new(),
                msg: "the shared undo journal is unavailable".into() });
        }
    };
    let replay = match claimed {
        Some(StoredRedo::Ok(replay)) => replay,
        Some(StoredRedo::Err(error)) => return Err(error),
        None => return Err(FleaError { where_: "redo".into(), path: String::new(), msg: "there is nothing to redo".into() }),
    };
    let (entry, changes, result) = replay.run(id, cancel, tx);
    let failed = result.is_err();
    let _ = finish_redone(&shared, entry, &changes, failed);
    result
}

#[cfg(test)]
#[path = "undoshare_tests.rs"]
mod tests;
