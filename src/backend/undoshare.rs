// One undo history for every Flea window; see AGENTS.md "Write operations and the undo journal".
use super::undocodec::{decode, encode};
use crate::backend::manifestdir::current_uid;
use crate::backend::redo::Replay;
use crate::backend::undo::{reverse, Entry, ItemIdentity, Step, DEPTH};
use crate::error::FleaError;
use crate::jsondoc::render;
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

// Past twice the largest benched tree in manifest bytes the file is foreign, as copymanifest refuses its stream.
const MAX_FILE_BYTES: u64 = 32 * 1024 * 1024;
// The redo stack is unbounded in memory, but a file without a cap is not, so it caps here.
const MAX_REDOS: usize = 50;
const JOURNAL_FILE: &str = "undo-journal";
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

// A malformed file is ignored with one log line; a missing file is the normal first run.
fn load(shared: &Shared) -> Doc {
    let path = shared.journal_path();
    let meta = match path.symlink_metadata() {
        Ok(meta) => meta,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return empty_doc(),
        Err(e) => {
            eprintln!("flea: the shared undo journal could not be read ({:?}), so it was ignored", e.kind());
            return empty_doc();
        }
    };
    if meta.file_type().is_symlink() {
        eprintln!("flea: the shared undo journal is a symbolic link, so it was ignored");
        return empty_doc();
    }
    if meta.uid() != current_uid() {
        eprintln!("flea: the shared undo journal is not owned by this user, so it was ignored");
        return empty_doc();
    }
    let file = match std::fs::File::open(&path) {
        Ok(file) => file,
        Err(e) => {
            eprintln!("flea: the shared undo journal could not be read ({:?}), so it was ignored", e.kind());
            return empty_doc();
        }
    };
    let mut bytes = Vec::new();
    use std::io::Read;
    if file.take(MAX_FILE_BYTES + 1).read_to_end(&mut bytes).is_err() {
        eprintln!("flea: the shared undo journal could not be read, so it was ignored");
        return empty_doc();
    }
    if bytes.len() as u64 > MAX_FILE_BYTES {
        eprintln!("flea: the shared undo journal is oversized, so it was ignored");
        return empty_doc();
    }
    let text = match String::from_utf8(bytes) {
        Ok(text) => text,
        Err(_) => {
            eprintln!("flea: the shared undo journal is not valid UTF-8, so it was ignored");
            return empty_doc();
        }
    };
    match decode(&text) {
        Some(doc) => doc,
        None => {
            eprintln!("flea: the shared undo journal is malformed, so it was ignored");
            empty_doc()
        }
    }
}

// Exclusive temp plus rename last, so a reader sees a complete file or none at all.
fn store(shared: &Shared, doc: &Doc) -> Result<(), String> {
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
    let text = render(&encode(doc));
    if file.write_all(text.as_bytes()).is_err() {
        let _ = std::fs::remove_file(&tmp);
        return Err("the shared undo journal could not be written".to_string());
    }
    drop(file);
    std::fs::rename(&tmp, &dest)
        .map_err(|e| format!("the shared undo journal could not be published ({:?})", e.kind()))
}

fn rebase_doc(doc: &mut Doc, old: &ItemIdentity, new: &ItemIdentity) {
    for entry in &mut doc.undo {
        entry.rebase(old, new);
    }
    for stored in &mut doc.redo {
        if let StoredRedo::Ok(replay) = stored {
            replay.rebase(old, new);
        }
    }
}

// Drops oldest undo then oldest redo until the render fits; newest records never go.
fn trim_to_fit(doc: &mut Doc) {
    while render(&encode(doc)).len() as u64 > MAX_FILE_BYTES {
        if doc.undo.len() > 1 {
            doc.undo.remove(0);
        } else if !doc.redo.is_empty() {
            doc.redo.remove(0);
        } else {
            break;
        }
    }
}

// True when the doc fits; a single newest record over the cap alone answers false.
fn fits(doc: &Doc) -> bool {
    render(&encode(doc)).len() as u64 <= MAX_FILE_BYTES
}

pub(crate) fn push_entry(shared: &Shared, entry: &Entry) -> Result<PushResult, ()> {
    if entry.steps.is_empty() {
        return Ok(PushResult::Stored);
    }
    let _guard = lock(shared).map_err(|msg| eprintln!("flea: {}", msg))?;
    let mut doc = load(shared);
    for step in &entry.steps {
        if let Step::Moved { before, after, .. } = step {
            rebase_doc(&mut doc, before, after);
        }
    }
    doc.undo.push(entry.clone());
    while doc.undo.len() > DEPTH {
        doc.undo.remove(0);
    }
    doc.redo.clear();
    doc.push_gen = doc.push_gen.wrapping_add(1);
    trim_to_fit(&mut doc);
    if !fits(&doc) {
        return Ok(PushResult::TooBig);
    }
    store(shared, &doc).map_err(|msg| eprintln!("flea: {}", msg))?;
    Ok(PushResult::Stored)
}

// One locked read-modify-write pops the newest entry; the generation lets finish drop a stale replay.
pub(crate) fn claim_undo(shared: &Shared) -> Result<Option<(Entry, u64)>, ()> {
    let _guard = lock(shared).map_err(|msg| eprintln!("flea: {}", msg))?;
    let mut doc = load(shared);
    let claimed = doc.undo.pop();
    if claimed.is_some() {
        store(shared, &doc).map_err(|msg| eprintln!("flea: {}", msg))?;
    }
    Ok(claimed.map(|entry| (entry, doc.push_gen)))
}

// The entry is spent whether the reversal worked or not; a replay lands only with no push since claim.
pub(crate) fn finish_undone(shared: &Shared, entry: Option<Entry>, changes: &[(ItemIdentity, ItemIdentity)], claimed_gen: u64) -> Result<(), ()> {
    let _guard = lock(shared).map_err(|msg| eprintln!("flea: {}", msg))?;
    let mut doc = load(shared);
    for (old, new) in changes {
        rebase_doc(&mut doc, old, new);
    }
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
    trim_to_fit(&mut doc);
    if !fits(&doc) {
        // The replay alone overflowed; keep history without it rather than publishing oversize.
        if let Some(StoredRedo::Ok(_)) | Some(StoredRedo::Err(_)) = doc.redo.pop() {
            trim_to_fit(&mut doc);
        }
    }
    if !fits(&doc) {
        return Ok(());
    }
    store(shared, &doc).map_err(|msg| eprintln!("flea: {}", msg))?;
    Ok(())
}

pub(crate) fn redo_info(shared: &Shared) -> Result<(String, usize), FleaError> {
    let _guard = lock(shared).map_err(|msg| {
        eprintln!("flea: {}", msg);
    }).map_err(|_| FleaError { where_: "redo".into(), path: String::new(), msg: "the shared undo journal is unavailable".into() })?;
    let doc = load(shared);
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
    let mut doc = load(shared);
    let claimed = doc.redo.pop();
    if claimed.is_some() {
        store(shared, &doc).map_err(|msg| eprintln!("flea: {}", msg))?;
    }
    Ok(claimed)
}

// Mirrors Journal::redo's tail: the redone entry rejoins the undo stack, and a failed redo clears it.
pub(crate) fn finish_redone(shared: &Shared, entry: Entry, changes: &[(ItemIdentity, ItemIdentity)], failed: bool) -> Result<(), ()> {
    let _guard = lock(shared).map_err(|msg| eprintln!("flea: {}", msg))?;
    let mut doc = load(shared);
    for (old, new) in changes {
        rebase_doc(&mut doc, old, new);
    }
    if !entry.steps.is_empty() {
        doc.undo.push(entry);
        while doc.undo.len() > DEPTH {
            doc.undo.remove(0);
        }
    }
    if failed {
        doc.redo.clear();
    }
    trim_to_fit(&mut doc);
    if !fits(&doc) {
        return Ok(());
    }
    store(shared, &doc).map_err(|msg| eprintln!("flea: {}", msg))?;
    Ok(())
}

fn nothing_to_undo() -> FleaError {
    FleaError { where_: "undo".into(), path: String::new(), msg: "there is nothing to undo".into() }
}

// The whole entry is reversed or the failure is reported; a finish only loses its replay and rebase.
pub(crate) fn undo_newest(slot: &mut Option<Shared>) -> Result<String, FleaError> {
    let Some(shared) = slot.clone() else { return Err(nothing_to_undo()) };
    let (entry, gen) = match claim_undo(&shared) {
        Ok(Some(pair)) => pair,
        Ok(None) => return Err(nothing_to_undo()),
        Err(()) => {
            *slot = None;
            return Err(FleaError { where_: "undo".into(), path: String::new(),
                msg: "the shared undo journal is unavailable".into() });
        }
    };
    let op = entry.op.clone();
    let mut changes = Vec::new();
    for step in entry.steps.iter().rev() {
        match reverse(step) {
            Ok(Some((old, new))) => changes.push((old, new)),
            Ok(None) => {}
            Err(error) => {
                let _ = finish_undone(&shared, None, &changes, gen);
                return Err(error);
            }
        }
    }
    let _ = finish_undone(&shared, Some(entry), &changes, gen);
    Ok(op)
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
