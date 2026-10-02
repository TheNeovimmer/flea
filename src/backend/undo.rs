// The undo journal, designed in from the first operation, which is why nothing in Flea needs a confirm dialog.
use crate::backend::renamecompat::rename_path;
use crate::backend::trash;
use crate::error::{from_io, FleaError};
use std::os::unix::fs::MetadataExt;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;

#[derive(Clone, Debug, PartialEq)]
pub struct ItemIdentity {
    dev: u64,
    ino: u64,
    kind: u32,
    len: u64,
    mtime: (i64, i64),
    changed: (i64, i64),
}

impl ItemIdentity {
    pub fn record(meta: &std::fs::Metadata) -> Self {
        Self { dev: meta.dev(), ino: meta.ino(), kind: meta.mode() & 0o170000, len: meta.len(),
            mtime: (meta.mtime(), meta.mtime_nsec()), changed: (meta.ctime(), meta.ctime_nsec()) }
    }
    // The shared journal's wire form, field for field; the kind set it accepts is checked on read.
    pub(crate) fn to_parts(&self) -> (u64, u64, u32, u64, (i64, i64), (i64, i64)) {
        (self.dev, self.ino, self.kind, self.len, self.mtime, self.changed)
    }
    pub(crate) fn from_parts(dev: u64, ino: u64, kind: u32, len: u64, mtime: (i64, i64), changed: (i64, i64)) -> Self {
        Self { dev, ino, kind, len, mtime, changed }
    }
    pub fn inspect(path: &std::path::Path) -> Result<Self, FleaError> {
        path.symlink_metadata().map(|meta| Self::record(&meta))
            .map_err(|e| from_io("journal", &path.to_string_lossy(), &e))
    }
    // The shelf keeps its one-step journal in a file of its own, so it needs these three out of here.
    pub fn parts(&self) -> (u64, u64, u32) {
        (self.dev, self.ino, self.kind)
    }
    pub fn same_item(&self, other: &Self) -> bool {
        self.dev == other.dev && self.ino == other.ino && self.kind == other.kind
    }
    // A batched move removes its source only while it still holds the bytes its copy took.
    pub fn unchanged_for_move(&self, current: &Self) -> bool {
        self.same_item(current) && self.len == current.len
            && self.mtime == current.mtime && self.changed == current.changed
    }
}

// One reversible step. An operation is a list of these, reversed newest first.
#[derive(Clone, Debug, PartialEq)]
pub enum Step {
    // A rename or a move: the entry now lives at `to` and came from `from`.
    Moved { from: PathBuf, to: PathBuf, before: ItemIdentity, after: ItemIdentity },
    // This operation created `path`, so reversing it removes that path; never a path the operation only read.
    // Undo removes what an op created; nothing in the product writes this step yet, and the tests
    // that drive undo's own ladder are what construct it.
    #[cfg_attr(not(test), allow(dead_code))]
    Created { path: PathBuf },
    // Paste as made `path` a link to `source`: undo removes it only while it
    // is still that same link, so a folder or file put at that name since
    // survives, the way a changed copy or new file is left in place.
    Linked { path: PathBuf, identity: ItemIdentity, source: PathBuf, kind: super::link::LinkKind },
    // manifest_nonce keys the recording backend's in-memory manifest; None means whole-tree fallback.
    Copied { from: PathBuf, to: PathBuf, source: ItemIdentity, created: ItemIdentity, manifest: Option<super::copymanifest::Handle>, manifest_nonce: Option<u64> },
    // This operation made the empty directory `path`; reversing it removes it only while it is still
    // empty, because anything inside it now was put there by someone else, never by this operation.
    MadeDir { path: PathBuf, identity: ItemIdentity },
    // New File is removable only while it remains the same untouched empty regular file.
    MadeFile { path: PathBuf, identity: ItemIdentity },
    // This operation trashed what was at `original`, and the trash holds it under `uri`.
    Trashed(trash::Entry),
    // Permissions for several items: one entry holds every path the Apply changed,
    // so one undo restores them all; a path edited since keeps nothing to restore to.
    Mode { path: PathBuf, before: u32, after: u32 },
    // A too-big push leaves this payload-free barrier in the shared doc; no window keeps the entry.
    Barrier,
}

// The codec bounds an op name, so a barrier truncates an over-long one to fit it.
const MAX_OP_LEN: usize = 128;

// The codec refuses an over-long op, so the marker carries the fitting prefix.
fn placeholder_op(op: &str) -> String {
    let short: String = op.chars().take(MAX_OP_LEN).collect();
    if short.is_empty() {
        "operation".to_string()
    } else {
        short
    }
}

// A barrier is one payload-free step and nothing else, so a mixed entry never matches.
fn is_barrier(entry: &Entry) -> bool {
    matches!(&entry.steps[..], [Step::Barrier])
}

// One user-visible operation, however many steps it took, named the way the status bar already named it.
#[derive(Clone, Debug)]
pub struct Entry {
    pub op: String,
    pub steps: Vec<Step>,
}

impl Entry {
    pub(crate) fn rebase(&mut self, old: &ItemIdentity, new: &ItemIdentity) {
        for step in &mut self.steps {
            match step {
                Step::Moved { before, after, .. } => {
                    if before == old { *before = new.clone(); }
                    if after == old { *after = new.clone(); }
                }
                Step::Copied { source, created, .. } => {
                    if source == old { *source = new.clone(); }
                    if created == old { *created = new.clone(); }
                }
                Step::MadeFile { identity, .. } | Step::MadeDir { identity, .. } if identity == old => *identity = new.clone(),
                Step::Linked { identity, .. } if identity == old => *identity = new.clone(),
                _ => {}
            }
        }
    }
}

// The operations design's own number: a 50-entry ring; the cap also bounds the session file.
pub(crate) const DEPTH: usize = 50;

pub struct Journal {
    entries: Vec<Entry>,
    redo: Vec<Result<super::redo::Replay, FleaError>>,
    shared: Option<super::undoshare::Shared>,
    // Manifests by nonce for entries this backend recorded; a claim elsewhere finds no key and falls back.
    manifests: std::collections::HashMap<u64, super::copymanifest::Handle>,
    next_nonce: u32,
    // Random per journal, so two journals in one process never mint the same nonce.
    nonce_high: u32,
}

// Four bytes of randomness read once per journal, with no new crate.
const NONCE_BYTES: usize = 4;
// The starttime field index after the comm in /proc/self/stat.
const START_INDEX: usize = 19;
// A fixed mix when neither urandom nor /proc answers, so the fallback still differs by pid.
const FALLBACK_XOR: u32 = 0x9e3779b9;

// One random read per journal; the fallback mixes pid with process start time.
fn nonce_high_once() -> u32 {
    if let Ok(mut file) = std::fs::File::open("/dev/urandom") {
        let mut buf = [0u8; NONCE_BYTES];
        use std::io::Read;
        if file.read_exact(&mut buf).is_ok() {
            return u32::from_le_bytes(buf);
        }
    }
    fallback_nonce_high()
}

// Pid xor start time, so a restarted backend reusing a pid still differs.
fn fallback_nonce_high() -> u32 {
    let pid = std::process::id();
    match process_start_time() {
        Some(time) => pid ^ (time as u32) ^ ((time >> 32) as u32),
        None => pid ^ FALLBACK_XOR,
    }
}

// Field 22 of /proc/self/stat; the comm may hold spaces, so split after the last paren.
fn process_start_time() -> Option<u64> {
    let text = std::fs::read_to_string("/proc/self/stat").ok()?;
    let after = text.rsplit(')').next()?;
    after.split_whitespace().nth(START_INDEX)?.parse::<u64>().ok()
}

impl Journal {
    pub fn new() -> Journal {
        Journal { entries: Vec::new(), redo: Vec::new(), shared: None, manifests: std::collections::HashMap::new(), next_nonce: 0, nonce_high: nonce_high_once() }
    }

    // Production attaches the session journal file; a refused directory keeps the in-memory one.
    pub(crate) fn attach_shared(&mut self) {
        if self.shared.is_none() {
            self.shared = super::undoshare::Shared::from_env();
        }
        self.drain_local();
    }

    #[cfg(test)]
    pub(crate) fn attach_test_shared(&mut self, dir: std::path::PathBuf) {
        self.shared = super::undoshare::Shared::at(dir);
        self.drain_local();
    }

    // Entries pushed before the attach join the shared doc oldest first, so none strands locally.
    fn drain_local(&mut self) {
        if self.shared.is_none() || self.entries.is_empty() {
            return;
        }
        let pending = std::mem::take(&mut self.entries);
        for entry in pending {
            self.push(entry);
        }
    }

    // A nonce this backend alone can reattach; the random high half keeps it unique across backends.
    fn next_nonce(&mut self) -> u64 {
        self.next_nonce = self.next_nonce.wrapping_add(1);
        ((self.nonce_high as u64) << 32) | (self.next_nonce as u64)
    }

    // Drops every manifest whose nonce left the shared doc with its entry.
    fn prune(&mut self) {
        let Some(shared) = self.shared.clone() else { return };
        let Some(live) = super::undoshare::live_nonces(&shared) else { return };
        self.manifests.retain(|nonce, _| live.contains(nonce));
    }

    // Test-only: the next nonce without recording anything, so uniqueness is pinned directly.
    #[cfg(test)]
    pub(crate) fn test_nonce(&mut self) -> u64 {
        self.next_nonce()
    }

    // An operation that changed nothing records nothing, so undo never reports a no-op as work.
    pub fn push(&mut self, entry: Entry) {
        let shared = match &self.shared {
            Some(shared) => shared.clone(),
            None => {
                if entry.steps.is_empty() {
                    return;
                }
                self.redo.clear();
                for step in &entry.steps {
                    if let Step::Moved { before, after, .. } = step { self.rebase(before, after); }
                }
                self.entries.push(entry);
                if self.entries.len() > DEPTH {
                    self.entries.remove(0);
                }
                return;
            }
        };
        let mut filed = entry.clone();
        let mut nonces = Vec::new();
        for index in 0..filed.steps.len() {
            let handle = match &filed.steps[index] {
                Step::Copied { manifest: Some(handle), .. } => handle.clone(),
                _ => continue,
            };
            let nonce = self.next_nonce();
            self.manifests.insert(nonce, handle);
            nonces.push(nonce);
            if let Step::Copied { manifest, manifest_nonce, .. } = &mut filed.steps[index] {
                *manifest = None;
                *manifest_nonce = Some(nonce);
            }
        }
        match super::undoshare::push_entry(&shared, &filed) {
            Ok(super::undoshare::PushResult::Stored) => {
                self.prune();
                return;
            }
            Ok(super::undoshare::PushResult::TooBig) => {
                for nonce in &nonces {
                    self.manifests.remove(nonce);
                }
                // The payload is kept nowhere: a small barrier keeps the entry's place in line.
                let barrier = Entry { op: placeholder_op(&entry.op), steps: vec![Step::Barrier] };
                match super::undoshare::push_entry(&shared, &barrier) {
                    Ok(super::undoshare::PushResult::Stored) => self.prune(),
                    Ok(super::undoshare::PushResult::TooBig) => {}
                    Err(()) => self.shared = None,
                }
                return;
            }
            Err(()) => {
                for nonce in &nonces {
                    self.manifests.remove(nonce);
                }
                self.shared = None;
            }
        }
        if entry.steps.is_empty() {
            return;
        }
        self.redo.clear();
        for step in &entry.steps {
            if let Step::Moved { before, after, .. } = step { self.rebase(before, after); }
        }
        self.entries.push(entry);
        if self.entries.len() > DEPTH {
            self.entries.remove(0);
        }
    }

    // Test-only: production reads the journal by undoing it, never by asking how deep it is.
    #[cfg(test)]
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    #[cfg(test)]
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    // Shared entries undo from the file with this backend's manifests reattached.
    pub fn undo(&mut self) -> Result<String, FleaError> {
        if let Some(shared) = self.shared.clone() {
            let (mut entry, gen) = match super::undoshare::claim_undo(&shared) {
                Ok(Some(pair)) => pair,
                Ok(None) => return Err(err("there is nothing to undo")),
                Err(()) => {
                    self.shared = None;
                    return Err(FleaError { where_: "undo".into(), path: String::new(), msg: "the shared undo journal is unavailable".into() });
                }
            };
            // The claim already spent the barrier, so this answers and never replays it.
            if is_barrier(&entry) {
                self.prune();
                return Err(FleaError { where_: "undo".into(), path: String::new(), msg: "That operation was too large to undo.".into() });
            }
            for step in &mut entry.steps {
                if let Step::Copied { manifest, manifest_nonce: Some(nonce), .. } = step {
                    if let Some(handle) = self.manifests.remove(nonce) {
                        *manifest = Some(handle);
                    }
                }
            }
            let op = entry.op.clone();
            let mut changes = Vec::new();
            for step in entry.steps.iter().rev() {
                match reverse(step) {
                    Ok(Some((old, new))) => {
                        changes.push((old.clone(), new.clone()));
                        self.rebase(&old, &new);
                    }
                    Ok(None) => {}
                    Err(error) => {
                        let _ = super::undoshare::finish_undone(&shared, None, &changes, gen);
                        self.prune();
                        return Err(error);
                    }
                }
            }
            let _ = super::undoshare::finish_undone(&shared, Some(entry), &changes, gen);
            self.prune();
            return Ok(op);
        }
        let entry = match self.entries.pop() {
            Some(e) => e,
            None => return Err(err("there is nothing to undo")),
        };
        for step in entry.steps.iter().rev() {
            if let Some((old, new)) = reverse(step)? { self.rebase(&old, &new); }
        }
        let op = entry.op.clone();
        self.redo.push(super::redo::Replay::capture(entry));
        Ok(op)
    }

    pub fn redo_info(&mut self) -> Result<(String, usize), FleaError> {
        if let Some(shared) = self.shared.clone() {
            let info = super::undoshare::redo_info(&shared);
            self.prune();
            return info;
        }
        match self.redo.last() {
            Some(Ok(replay)) => Ok((replay.op().to_string(), replay.len())),
            Some(Err(error)) => Err(FleaError { where_: "redo".into(), path: error.path.clone(), msg: error.msg.clone() }),
            None => Err(FleaError { where_: "redo".into(), path: String::new(), msg: "there is nothing to redo".into() }),
        }
    }

    pub fn redo(&mut self, id: usize, cancel: &std::sync::atomic::AtomicBool,
                tx: &std::sync::mpsc::Sender<super::opsreq::OpMsg>) -> Result<String, FleaError> {
        if self.shared.is_some() {
            let result = super::undoshare::redo_newest(&mut self.shared, id, cancel, tx);
            self.prune();
            return result;
        }
        let replay = self.redo.pop().ok_or_else(|| FleaError { where_: "redo".into(), path: String::new(), msg: "there is nothing to redo".into() })??;
        let (entry, changes, result) = replay.run(id, cancel, tx);
        for (old, new) in changes { self.rebase(&old, &new); }
        if !entry.steps.is_empty() { self.entries.push(entry); }
        if result.is_err() { self.redo.clear(); }
        result
    }

    fn rebase(&mut self, old: &ItemIdentity, new: &ItemIdentity) {
        for entry in &mut self.entries { entry.rebase(old, new); }
        for replay in self.redo.iter_mut().flatten() { replay.rebase(old, new); }
    }
}

// The shelf keeps its one step back in a file rather than in a Journal, because the process that
// made the move has exited by the time the card presses z; the walk home is still this one, so the
// no-clobber rename and its cross-filesystem fallback are shared rather than written twice.
pub fn move_back(to: &std::path::Path, from: &std::path::Path) -> Result<(), FleaError> {
    rename_path(to, from)
}

pub fn copied(from: &std::path::Path, to: &std::path::Path, source: ItemIdentity) -> Result<Step, FleaError> {
    Ok(Step::Copied { from: from.to_path_buf(), to: to.to_path_buf(), source, created: ItemIdentity::inspect(to)?, manifest: None, manifest_nonce: None })
}

// A failed or cancelled tree copy carries what it managed to create; a success keeps the plain step.
pub fn copied_partial(from: &std::path::Path, to: &std::path::Path, source: ItemIdentity, manifest: Option<super::copymanifest::Handle>) -> Result<Step, FleaError> {
    Ok(Step::Copied { from: from.to_path_buf(), to: to.to_path_buf(), source, created: ItemIdentity::inspect(to)?, manifest, manifest_nonce: None })
}

pub fn moved(from: &std::path::Path, to: &std::path::Path, before: ItemIdentity) -> Result<Step, FleaError> {
    Ok(Step::Moved { from: from.to_path_buf(), to: to.to_path_buf(), before, after: ItemIdentity::inspect(to)? })
}

pub(crate) fn reverse(step: &Step) -> Result<Option<(ItemIdentity, ItemIdentity)>, FleaError> {
    match step {
        // Back the way it came, and still refusing to clobber: something may occupy the old name now.
        Step::Moved { from, to, after, .. } => {
            let current = ItemIdentity::inspect(to)?;
            if !after.same_item(&current) {
                return Err(FleaError { where_: "undo".into(), path: to.to_string_lossy().into(), msg: "the moved item was replaced, so undo left it in place".into() });
            }
            rename_path(to, from)?;
            return Ok(if current == *after { Some((current, ItemIdentity::inspect(from)?)) } else { None });
        }
        Step::Created { path } => remove(path)?,
        Step::Linked { path, identity, kind, .. } => remove_link(path, identity, kind)?,
        Step::Copied { to, created, manifest, .. } => {
            if let Some(handle) = manifest {
                // The manifest names only what the copy made, so the coarse whole-tree checks below are skipped.

                match super::copymanifest::remove_owned(handle) {
                    super::copymanifest::Outcome::Done(report) if report.kept.is_empty() => {}
                    super::copymanifest::Outcome::Done(report) => {
                        return Err(super::copymanifest::undo_err(to, super::copymanifest::summarize(&report)));
                    }
                    // Unreadable before anything went: today's check, never a wider delete.
                    super::copymanifest::Outcome::Fallback => return remove_copied(to, created),
                }
            } else {
                return remove_copied(to, created);
            }
        }
        Step::MadeDir { path, identity } => {
            if !identity.same_item(&ItemIdentity::inspect(path)?) {
                return Err(FleaError { where_: "undo".into(), path: path.to_string_lossy().into(), msg: "the new folder was replaced, so undo left it in place".into() });
            }
            remove_empty(path)?;
        }
        Step::MadeFile { path, identity } => remove_new_file(path, identity)?,
        Step::Trashed(entry) => trash::restore(entry)?,
        Step::Mode { path, before, .. } => restore_mode(path, *before)?,
        // A claimed barrier never reaches a reversal; refusing here keeps it from running as a file.
        Step::Barrier => return Err(FleaError { where_: "undo".into(), path: String::new(), msg: "That operation was too large to undo.".into() }),
    }
    Ok(None)
}

// Today's whole-tree check, kept for successes and for a manifest that never verified a record.
fn remove_copied(to: &PathBuf, created: &ItemIdentity) -> Result<Option<(ItemIdentity, ItemIdentity)>, FleaError> {
    if ItemIdentity::inspect(to)? != *created {
        return Err(FleaError { where_: "undo".into(), path: to.to_string_lossy().into(),
            msg: "the copied item changed since this operation, so undo left it in place".into() });
    }
    if let Some(newer) = newer_inside(to, created.changed)? {
        return Err(FleaError { where_: "undo".into(), path: newer.to_string_lossy().into(),
            msg: "something inside the copied folder changed since this operation, so undo left it in place".into() });
    }
    remove(to)?;
    Ok(None)
}

fn remove_new_file(path: &PathBuf, identity: &ItemIdentity) -> Result<(), FleaError> {
    let meta = path.symlink_metadata().map_err(|e| from_io("undo", &path.to_string_lossy(), &e))?;
    if !meta.is_file() || meta.len() != 0 || ItemIdentity::record(&meta) != *identity {
        return Err(FleaError { where_: "undo".into(), path: path.to_string_lossy().into(),
            msg: "the new file changed since creation, so undo left it in place".into() });
    }
    std::fs::remove_file(path).map_err(|e| from_io("undo", &path.to_string_lossy(), &e))
}

// Issue 111: a directory keeps its own ctime while a file inside it is edited, so the root's identity
// said the tree was untouched and undo removed the work the user had done since; the copy sets the
// root's mode last, so nothing it wrote is newer than the ctime recorded for the root.
// corner: neither a change landing between this walk and the removal, the window every check-then-act
// has, nor one inside the filesystem's own timestamp granularity: tmpfs is coarser than a copy is fast.
fn newer_inside(root: &std::path::Path, copied: (i64, i64)) -> Result<Option<PathBuf>, FleaError> {
    let meta = root.symlink_metadata().map_err(|e| from_io("undo", &root.to_string_lossy(), &e))?;
    if !meta.is_dir() || meta.file_type().is_symlink() {
        return Ok(None);
    }
    let entries = std::fs::read_dir(root).map_err(|e| from_io("undo", &root.to_string_lossy(), &e))?;
    for entry in entries {
        let entry = entry.map_err(|e| from_io("undo", &root.to_string_lossy(), &e))?;
        let path = entry.path();
        let meta = path.symlink_metadata().map_err(|e| from_io("undo", &path.to_string_lossy(), &e))?;
        if (meta.ctime(), meta.ctime_nsec()) > copied {
            return Ok(Some(path));
        }
        if meta.is_dir() && !meta.file_type().is_symlink() {
            if let Some(found) = newer_inside(&path, copied)? {
                return Ok(Some(found));
            }
        }
    }
    Ok(None)
}

// Only ever a path this operation itself created, so a directory it made is removed with its contents.
fn remove(path: &PathBuf) -> Result<(), FleaError> {
    let meta = path
        .symlink_metadata()
        .map_err(|e| from_io("undo", &path.to_string_lossy(), &e))?;
    let r = if meta.is_dir() && !meta.file_type().is_symlink() {
        std::fs::remove_dir_all(path)
    } else {
        std::fs::remove_file(path)
    };
    r.map_err(|e| from_io("undo", &path.to_string_lossy(), &e))
}

// A link undo removes only the link this operation made, with remove_file and
// never remove_dir_all: a folder or file put at that name since is someone
// else's, so undo refuses and leaves it, the way a changed copy is left.
fn remove_link(path: &PathBuf, identity: &ItemIdentity, kind: &super::link::LinkKind) -> Result<(), FleaError> {
    let meta = path.symlink_metadata().map_err(|e| from_io("undo", &path.to_string_lossy(), &e))?;
    let current = ItemIdentity::record(&meta);
    let still_link = match kind {
        super::link::LinkKind::Hard => !meta.file_type().is_symlink() && meta.is_file(),
        _ => meta.file_type().is_symlink(),
    };
    if !identity.same_item(&current) || !still_link {
        return Err(FleaError { where_: "undo".into(), path: path.to_string_lossy().into(),
            msg: "the link changed since this operation, so undo left it in place".into() });
    }
    std::fs::remove_file(path).map_err(|e| from_io("undo", &path.to_string_lossy(), &e))
}

// Only ever an empty directory this operation made. A folder the user has filled since is theirs now, so
// undo refuses and leaves it, the way a rename undo refuses a name something else has taken meanwhile.
fn remove_empty(path: &PathBuf) -> Result<(), FleaError> {
    // ENOTEMPTY from Linux errno.h: ErrorKind::DirectoryNotEmpty needs Rust 1.83 over the 1.77 floor.
    const ENOTEMPTY: i32 = 39;
    match std::fs::remove_dir(path) {
        Ok(()) => Ok(()),
        Err(e) if e.raw_os_error() == Some(ENOTEMPTY) => Err(FleaError {
            where_: "undo".to_string(),
            path: path.to_string_lossy().to_string(),
            msg: "the new folder has been filled since, so undo left it in place".to_string(),
        }),
        Err(e) => Err(from_io("undo", &path.to_string_lossy(), &e)),
    }
}

fn err(msg: &str) -> FleaError {
    FleaError { where_: "undo".to_string(), path: String::new(), msg: msg.to_string() }
}

// A mode undo restores bits rather than removing a path: a symlink is refused,
// because chmod would follow it, and any other failure names the path. The
// batch apply rolls back through here too, so a failure there can say what it
// restored and what stayed applied.
pub(crate) fn restore_mode(path: &PathBuf, mode: u32) -> Result<(), FleaError> {
    let meta = path.symlink_metadata().map_err(|e| from_io("undo", &path.to_string_lossy(), &e))?;
    if meta.file_type().is_symlink() {
        return Err(FleaError { where_: "undo".to_string(), path: path.to_string_lossy().to_string(),
            msg: "the item is a link, so undo left its mode in place".to_string() });
    }
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
        .map_err(|e| from_io("undo", &path.to_string_lossy(), &e))
}

#[cfg(test)]
#[path = "undo_tests.rs"]
mod tests;
