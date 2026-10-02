// Dispatch for the five write operations: one runs at a time, because the status bar has one sticky slot for it.
use crate::backend::ops;
use crate::backend::opsreq::{
    duplicated_line, made_line, op_err, renamed_line, run_duplicate_checked, run_transfer_checked, run_trash, trashed_line,
    transferdone_line, transferitem_line, transferprogress_line, transferstarted_line, undone_line, usable_dest,
    OpMsg,
};
use crate::backend::listing::Listing;
use crate::backend::proto::error_line;
use crate::backend::undo::{Entry, ItemIdentity, Journal, Step};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;
use std::sync::mpsc::Sender;
use std::sync::Arc;
use std::thread;

// Everything the write operations own, kept apart from the listing state they never touch.
pub(crate) struct Ops {
    pub journal: Journal,
    pub permissions: super::permissions::Permissions,
    pub picker: Option<super::picker::Picker>,
    pub menuactions: Option<super::menu_actions::MenuActions>,
    pub trashbrowser: Option<super::trashbrowse::TrashBrowser>,
    pub transfer_retry: (usize, Vec<(PathBuf, ItemIdentity)>),
    pub question: Option<super::collide::Question>,
    pub asked: usize,
    pub next_id: usize,
    // The operation on the thread and its cancel flag, shared with the reader thread; one at a time.
    pub live: Arc<super::opscancel::Live>,
    // Detached jobs, so a quit cancels each one; they run alongside by design.
    pub detached: Arc<super::opscancel::DetachedJobs>,
    pub tx: Sender<OpMsg>,
}

impl Ops {
    pub fn new(tx: Sender<OpMsg>) -> Ops {
        Ops { journal: Journal::new(), permissions: super::permissions::Permissions::default(), picker: None, menuactions: None, trashbrowser: None,
              transfer_retry: (0, Vec::new()), question: None, asked: 0, next_id: 1, live: Arc::new(super::opscancel::Live::new()), detached: Arc::new(super::opscancel::DetachedJobs::new()), tx }
    }

    // An id with no slot claimed: archive and convert are id-keyed and run concurrently by design,
    // so they number themselves without taking the transfer's one-at-a-time slot.
    pub fn claim_id(&mut self) -> usize {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    // A fresh flag per operation, so a cancel can never reach the operation after the one it was aimed at.
    pub(crate) fn claim_transfer(&mut self) -> (usize, Arc<AtomicBool>) {
        let id = self.next_id;
        self.next_id += 1;
        let cancel = Arc::new(AtomicBool::new(false));
        self.live.claim(id, &cancel);
        (id, cancel)
    }
}

// The status bar shows one operation, so a second one is refused as data rather than queued invisibly behind the first.
fn busy(out: &mut impl Write, where_: &str) -> bool {
    let e = op_err(where_, "", "an operation is already running");
    writeln!(out, "{}", error_line(&e)).ok();
    out.flush().ok();
    true
}

// Explicit paths win; a rows form is resolved against the listing here, at request time, so the
// operation still owns a snapshot that outlives whatever the listing does next.
pub(crate) fn resolve_rows(paths: Vec<String>, rows: &[usize], base: &Path, listing: &Listing) -> Vec<String> {
    if !paths.is_empty() {
        return paths;
    }
    rows.iter()
        .filter(|&&r| r < listing.len())
        .map(|&r| base.join(listing.name(r)).to_string_lossy().to_string())
        .collect()
}

pub(crate) fn start_transfer(out: &mut impl Write, ops: &mut Ops, op: &str, paths: Vec<String>, dest: &str, collide: super::collide::Ask) {
    start_transfer_checked(out, ops, op, paths, dest, None, None, collide)
}

pub(crate) fn request_menu_action(out: &mut impl Write, ops: &mut Ops, line: String, paths: Vec<String>, cursor: Option<String>) {
    let deleting = crate::json::field_str(&line, "op").as_deref() == Some("delete");
    if deleting && ops.live.running().is_some() {
        writeln!(out, "{}", super::menu_actions::response(&line, Err("An operation is already running.".into()))).ok();
        out.flush().ok();
        return;
    }
    let replies = ops.tx.clone();
    let accepted = ops.menuactions.get_or_insert_with(|| super::menu_actions::MenuActions::new(replies)).request(line, paths, cursor);
    if deleting && accepted { ops.claim_transfer(); }
}

pub(crate) fn start_menu_transfer(out: &mut impl Write, ops: &mut Ops, op: &str, id: usize, dest: &str, collide: super::collide::Ask) {
    match super::collide::menu_sources(ops, id, dest, &collide) {
        Ok((items, destination)) => {
            let paths = items.iter().map(|item| item.path.to_string_lossy().into()).collect();
            start_transfer_checked(out, ops, op, paths, dest, Some(items), destination, collide);
        }
        Err(message) => {
            writeln!(out, "{}", error_line(&op_err("transfer", "", &message))).ok();
            out.flush().ok();
        }
    }
}

fn start_transfer_checked(out: &mut impl Write, ops: &mut Ops, op: &str, paths: Vec<String>, dest: &str,
                          selection: Option<Vec<super::menu_actions::Selected>>, destination: Option<super::menu_actions::Selected>, collide: super::collide::Ask) {
    if ops.live.running().is_some() {
        busy(out, "transfer");
        return;
    }
    let dest = match usable_dest(dest) {
        Ok(d) => d,
        Err(e) => {
            writeln!(out, "{}", error_line(&e)).ok();
            out.flush().ok();
            return;
        }
    };
    // Anything that is not exactly "move" is a copy, so a malformed op can never remove a source.
    let moving = op == "move";
    let n = paths.len();
    ops.transfer_retry = (0, Vec::new());
    let (id, cancel) = ops.claim_transfer();
    writeln!(out, "{}", transferstarted_line(id, n, moving)).ok();
    out.flush().ok();
    let tx = ops.tx.clone();
    let policy = collide.policy(ops.question.take(), &dest);
    thread::spawn(move || run_transfer_checked(id, moving, paths, dest, cancel, tx, selection, destination, policy));
}

// No response line of its own: the running operation answers with its own terminal transferdone.
pub(crate) fn cancel_transfer(ops: &Ops, id: usize) {
    ops.live.cancel(id);
}

pub(crate) fn menu_sources(ops: &Ops, id: usize) -> Result<Option<Vec<super::menu_actions::Selected>>, String> {
    if id == 0 { return Ok(None); }
    ops.menuactions.as_ref().ok_or_else(|| "Menu selection expired; reopen the menu.".to_string())
        .and_then(|menu| menu.selection(id)).map(Some)
}

pub(crate) fn start_trash(out: &mut impl Write, ops: &mut Ops, paths: Vec<String>, menu_id: usize) {
    if ops.live.running().is_some() {
        busy(out, "trash");
        return;
    }
    let selection = match menu_sources(ops, menu_id) {
        Ok(selection) => selection,
        Err(message) => { writeln!(out, "{}", error_line(&op_err("trash", "", &message))).ok(); out.flush().ok(); return; }
    };
    ops.claim_transfer();
    let tx = ops.tx.clone();
    thread::spawn(move || run_trash(paths, tx, selection));
}

pub(crate) fn start_duplicate(out: &mut impl Write, ops: &mut Ops, path: &str, menu_id: usize) {
    if ops.live.running().is_some() {
        busy(out, "duplicate");
        return;
    }
    let selection = match menu_sources(ops, menu_id) {
        Ok(selection) => selection,
        Err(message) => { writeln!(out, "{}", error_line(&op_err("duplicate", path, &message))).ok(); out.flush().ok(); return; }
    };
    ops.claim_transfer();
    let tx = ops.tx.clone();
    let owned = path.to_string();
    thread::spawn(move || run_duplicate_checked(owned, tx, selection));
}

// Rename answers on the calling thread; rclone directory compatibility may copy before removing its source.
pub(crate) fn do_menu_rename(out: &mut impl Write, ops: &mut Ops, path: &str, to: &str, id: usize) {
    let checked = ops.menuactions.as_ref().ok_or_else(|| "Menu selection expired; reopen the menu.".to_string())
        .and_then(|menu| menu.selected_path(id, Path::new(path)))
        .and_then(|item| item.current());
    if let Err(error) = checked {
        writeln!(out, "{}", error_line(&op_err("rename", path, &error))).ok();
        out.flush().ok();
        return;
    }
    do_rename(out, ops, path, to);
}

pub(crate) fn do_rename(out: &mut impl Write, ops: &mut Ops, path: &str, to: &str) {
    if ops.live.running().is_some() { busy(out, "rename"); return; }
    match ops::rename(Path::new(path), to) {
        Ok((dst, steps)) => {
            ops.journal.push(Entry { op: "rename".to_string(), steps });
            writeln!(out, "{}", renamed_line(true, &dst.to_string_lossy())).ok();
        }
        Err(e) => {
            writeln!(out, "{}", error_line(&e)).ok();
        }
    }
    out.flush().ok();
}

// One mkdir(2), so like rename it answers on the calling thread and never takes the operation slot.
pub(crate) fn do_mkdir(out: &mut impl Write, ops: &mut Ops, parent: &str, name: &str) {
    if ops.live.running().is_some() { busy(out, "mkdir"); return; }
    match ops::mkdir(Path::new(parent), name) {
        Ok((dir, steps)) => {
            ops.journal.push(Entry { op: "mkdir".to_string(), steps });
            writeln!(out, "{}", made_line(true, &dir.to_string_lossy())).ok();
        }
        Err(e) => {
            writeln!(out, "{}", error_line(&e)).ok();
        }
    }
    out.flush().ok();
}

pub(crate) fn do_undo(out: &mut impl Write, ops: &mut Ops) {
    if ops.live.running().is_some() { busy(out, "undo"); return; }
    match ops.journal.undo() {
        Ok(op) => writeln!(out, "{}", undone_line(&op, true)).ok(),
        Err(e) => writeln!(out, "{}", error_line(&e)).ok(),
    };
    out.flush().ok();
}

// A link the journal cannot identify is removed at once, so only a named leftover stays.
fn remove_made_link(to: &Path) -> std::io::Result<()> {
    if fail_link_verify() {
        return Err(std::io::Error::from_raw_os_error(super::movebatch::ESTALE));
    }
    std::fs::remove_file(to)
}

// The identity read beside that cleanup, failing together on a flaky mount.
fn inspect_made_link(to: &Path) -> Result<ItemIdentity, crate::error::FleaError> {
    if fail_link_verify() {
        let stale = std::io::Error::from_raw_os_error(super::movebatch::ESTALE);
        return Err(crate::error::from_io("journal", &to.to_string_lossy(), &stale));
    }
    ItemIdentity::inspect(to)
}

#[cfg(test)]
thread_local! {
    static FAIL_LINK_VERIFY: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

// Both the identity read and its cleanup fail, the way EACCES or ESTALE on a flaky mount breaks both.
#[cfg(test)]
pub fn test_fail_link_verify(fail: bool) {
    FAIL_LINK_VERIFY.with(|v| v.set(fail));
}

fn fail_link_verify() -> bool {
    #[cfg(test)]
    {
        FAIL_LINK_VERIFY.with(|v| v.get())
    }
    #[cfg(not(test))]
    {
        false
    }
}

// Paste as links: one syscall per source on this thread, journaled as one entry.
pub(crate) fn do_link(out: &mut impl Write, ops: &mut Ops, op: &str, paths: Vec<String>, dest: &str, collide: super::collide::Ask) {
    if ops.live.running().is_some() { busy(out, "link"); return; }
    let dest_path = match usable_dest(dest) {
        Ok(d) => d,
        Err(mut e) => {
            e.where_ = "link".to_string();
            writeln!(out, "{}", error_line(&e)).ok();
            out.flush().ok();
            return;
        }
    };
    let policy = collide.policy(ops.question.take(), &dest_path).for_batch(&paths);
    let mut steps: Vec<Step> = Vec::new();
    let mut ok = 0usize;
    let mut failed = 0usize;
    let mut skipped = 0usize;
    let mut first_err = String::new();
    // Each stranded replace sentence, reported on the linked line beside first_err.
    let mut note = String::new();
    for source in &paths {
        let src = Path::new(source);
        if src.symlink_metadata().is_err() {
            failed += 1;
            if first_err.is_empty() { first_err = format!("the link source {source} no longer exists"); }
            continue;
        }
        let Some(dst) = super::link::dest_path(&dest_path, src) else {
            failed += 1;
            if first_err.is_empty() { first_err = format!("{source} has no file name"); }
            continue;
        };
        let here = src.parent() == Some(dest_path.as_path());
        match policy.place(src, dst.clone(), here, false) {
            super::collide::Place::Skip => { skipped += 1; }
            super::collide::Place::Refuse(msg) => {
                failed += 1;
                if first_err.is_empty() { first_err = msg; }
            }
            super::collide::Place::Land { to, replace } => {
                let mut replaced: Vec<super::trash::Entry> = Vec::new();
                if replace {
                    match super::trash::trash(std::slice::from_ref(&to)) {
                        (trashed, 0) => replaced = trashed,
                        _ => {
                            failed += 1;
                            if first_err.is_empty() { first_err = super::collide::TRASH_REFUSED.to_string(); }
                            continue;
                        }
                    }
                }
                let kind = match op {
                    "absolute" => super::link::LinkKind::Absolute,
                    "hard" => super::link::LinkKind::Hard,
                    _ => super::link::LinkKind::Relative,
                };
                let made = match kind {
                    super::link::LinkKind::Absolute => super::link::create_absolute(src, &to),
                    super::link::LinkKind::Hard => super::link::create_hard(src, &to),
                    super::link::LinkKind::Relative => super::link::create_relative(src, &to),
                };
                match made {
                    Ok(()) => {
                        match inspect_made_link(&to) {
                            Ok(identity) => {
                                for entry in replaced {
                                    steps.push(Step::Trashed(entry));
                                }
                                steps.push(Step::Linked { path: to, identity,
                                    source: src.to_path_buf(), kind });
                                ok += 1;
                            }
                            Err(e) => {
                                // A failed cleanup leaves the link behind, so its result is reported, never ignored.
                                if let Err(remove) = remove_made_link(&to) {
                                    // The link holds their name, so restoring them can only fail and they stay in the trash.
                                    let stayed = if replaced.is_empty() { String::new() } else { "; the replaced item stays in the trash".to_string() };
                                    // The sentence lives in note, so a landed batch still reports it.
                                    let sentence = format!("{}; the link left at {} could not be removed ({}){}",
                                        e.msg, to.to_string_lossy(), crate::error::io_message(&remove), stayed);
                                    if note.is_empty() {
                                        note = sentence;
                                    } else {
                                        note.push_str("; ");
                                        note.push_str(&sentence);
                                    }
                                    failed += 1;
                                    continue;
                                }
                                for entry in replaced {
                                    if to.symlink_metadata().is_err()
                                        && super::trash::restore(&entry).is_ok() {
                                        continue;
                                    }
                                    steps.push(Step::Trashed(entry));
                                }
                                failed += 1;
                                if first_err.is_empty() { first_err = e.msg.clone(); }
                            }
                        }
                    }
                    Err(e) => {
                        // Put the trashed item back when the link left its name free.
                        for entry in replaced {
                            if to.symlink_metadata().is_err()
                                && super::trash::restore(&entry).is_ok() {
                                continue;
                            }
                            steps.push(Step::Trashed(entry));
                        }
                        failed += 1;
                        if first_err.is_empty() { first_err = e.msg.clone(); }
                    }
                }
            }
        }
    }
    ops.journal.push(Entry { op: "link".to_string(), steps });
    if (failed == 0 && first_err.is_empty()) || ok > 0 || skipped > 0 {
        writeln!(out, "{}", super::proto::linked_line(ok, failed, skipped, &note)).ok();
    } else {
        // An earlier failure never hides a stranded replace, so the note rides along.
        let msg = if first_err.is_empty() { note } else if note.is_empty() { first_err } else { format!("{first_err}; {note}") };
        writeln!(out, "{}", error_line(&op_err("link", dest, &msg))).ok();
    }
    out.flush().ok();
}

// Show original: reveal the symlink target in its own folder, never resolve a non-link.
pub(crate) fn do_link_target(out: &mut impl Write, path: &str) {
    let target = Path::new(path);
    let text = match std::fs::read_link(target) {
        Ok(t) => t,
        Err(e) => {
            writeln!(out, "{}", error_line(&op_err("linktarget", path, &crate::error::io_message(&e)))).ok();
            out.flush().ok();
            return;
        }
    };
    let absolute = if text.is_absolute() {
        text.clone()
    } else {
        target.parent().unwrap_or(Path::new("/")).join(&text)
    };
    let directory = absolute.parent().unwrap_or(Path::new("/")).to_string_lossy().to_string();
    let name = absolute.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    writeln!(out, "{}", super::proto::linktarget_line(path, &directory, &name)).ok();
    out.flush().ok();
}

// Permissions batch: one entry holds every path Apply changed, so one undo restores all.
pub(crate) fn do_permissions_batch(out: &mut impl Write, ops: &mut Ops, paths: Vec<String>, modes: Vec<String>, id: usize) {
    if ops.live.running().is_some() {
        writeln!(out, "{}", super::proto::permissions_batch_line(id, false, "", "an operation is already running")).ok();
        out.flush().ok();
        return;
    }
    if paths.len() != modes.len() {
        writeln!(out, "{}", super::proto::permissions_batch_line(id, false, "", "every selected item needs its own target mode")).ok();
        out.flush().ok();
        return;
    }
    let items: Vec<(PathBuf, String)> = paths.into_iter().zip(modes).map(|(p, m)| (PathBuf::from(p), m)).collect();
    // The reply names the first target mode.
    let shown = items.first().map(|(_, m)| m.clone()).unwrap_or_default();
    match super::permissions::apply_many(&items) {
        Ok(steps) => {
            ops.journal.push(Entry { op: "permissions".to_string(), steps });
            writeln!(out, "{}", super::proto::permissions_batch_line(id, true, &shown, "")).ok();
        }
        Err(failed) => {
            // A failed rollback journals what stayed applied, else nothing.
            if !failed.applied.is_empty() {
                ops.journal.push(Entry { op: "permissions".to_string(), steps: failed.applied });
            }
            writeln!(out, "{}", super::proto::permissions_batch_line(id, false, &shown, &failed.msg)).ok();
        }
    }
    out.flush().ok();
}

pub(crate) fn do_newfile(out: &mut impl Write, ops: &mut Ops, parent: &str, name: &str, id: usize) {
    if ops.live.running().is_some() {
        let request = format!(r#"{{"op":"newFile","id":{}}}"#, id);
        writeln!(out, "{}", super::menu_actions::response(&request, Err("An operation is already running.".into()))).ok();
        out.flush().ok();
        return;
    }
    let result = super::menu_actions::create_file(Path::new(parent), name).map(|(path, identity)| {
        ops.journal.push(Entry { op: "newfile".into(), steps: vec![super::undo::Step::MadeFile { path: path.clone(), identity }] });
        format!(r#""path":"{}""#, crate::json::escape(&path.to_string_lossy()))
    });
    let request = format!(r#"{{"op":"newFile","id":{}}}"#, id);
    writeln!(out, "{}", super::menu_actions::response(&request, result)).ok();
    out.flush().ok();
}

pub(crate) fn start_redo(out: &mut impl Write, ops: &mut Ops) {
    if ops.live.running().is_some() { busy(out, "redo"); return; }
    let (op, n) = match ops.journal.redo_info() {
        Ok(info) => info,
        Err(error) => {
            writeln!(out, "{}", error_line(&error)).ok();
            out.flush().ok();
            return;
        }
    };
    let (id, cancel) = ops.claim_transfer();
    let mut journal = std::mem::replace(&mut ops.journal, Journal::new());
    writeln!(out, r#"{{"t":"redostarted","id":{},"n":{},"op":"{}"}}"#, id, n, crate::json::escape(&op)).ok();
    out.flush().ok();
    let tx = ops.tx.clone();
    thread::spawn(move || {
        let result = journal.redo(id, &cancel, &tx);
        let _ = tx.send(OpMsg::RedoDone { journal, result });
    });
}

// Every message an operation thread sends, written out and, when terminal, recorded in the journal.
pub(crate) fn report_op(out: &mut impl Write, ops: &mut Ops, msg: OpMsg) {
    match msg {
        OpMsg::MenuDeleteDone { line } | OpMsg::SlotDone { line } => {
            ops.live.finished();
            writeln!(out, "{}", line).ok();
        }
        OpMsg::Progress { id, index, name, bytes, total, scanned } => {
            writeln!(out, "{}", transferprogress_line(id, index, &name, bytes, total, scanned)).ok();
        }
        OpMsg::Item { id, index, name, ok, err } => {
            writeln!(out, "{}", transferitem_line(id, index, &name, ok, &err)).ok();
        }
        OpMsg::TransferDone { id, ok, failed, skipped, cancelled, entry, retry, durable, note } => {
            ops.journal.push(entry);
            ops.live.finished();
            ops.transfer_retry = (id, retry);
            writeln!(out, "{}", transferdone_line(id, ok, failed, skipped, cancelled, &ops.transfer_retry.1, durable, &note)).ok();
        }
        OpMsg::Trashed { ok, failed, entry } => {
            ops.journal.push(entry);
            ops.live.finished();
            writeln!(out, "{}", trashed_line(ok, failed)).ok();
        }
        OpMsg::Asked { turn, question, line } => if super::collide::landed(ops, turn, question) { writeln!(out, "{}", line).ok(); },
        // Meta never claims the operation slot, so it does not clear it either.
        OpMsg::Meta { line } => {
            writeln!(out, "{}", line).ok();
        }
        // The job leaves the quit registry here, so a drain that sees it empty has already written every line.
        OpMsg::DetachedDone { id, line } => { writeln!(out, "{}", line).ok(); ops.detached.remove(id); }
        OpMsg::Duplicated { ok, path, err, entry } => {
            ops.journal.push(entry);
            ops.live.finished();
            if ok {
                writeln!(out, "{}", duplicated_line(true, &path)).ok();
            } else {
                writeln!(out, "{}", error_line(&op_err("duplicate", "", &err))).ok();
            }
        }
        OpMsg::RedoDone { journal, result } => {
            ops.journal = journal;
            ops.live.finished();
            match result {
                Ok(op) => writeln!(out, r#"{{"t":"redone","op":"{}","ok":true}}"#, crate::json::escape(&op)).ok(),
                Err(error) => writeln!(out, "{}", error_line(&error)).ok(),
            };
        }
    }
    out.flush().ok();
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, Ordering};
    use crate::backend::testdir::TestDir;
    use crate::backend::undo::Step;
    use std::sync::mpsc::channel;

    fn ops() -> Ops {
        let (tx, _rx) = channel();
        Ops::new(tx)
    }

    fn out() -> Vec<u8> {
        Vec::new()
    }

    fn text(buf: &[u8]) -> String {
        String::from_utf8_lossy(buf).to_string()
    }

    #[test]
    fn each_operation_claims_a_new_id_and_its_own_cancel_flag() {
        let mut o = ops();
        let (first, first_flag) = o.claim_transfer();
        o.live.finished();
        let (second, second_flag) = o.claim_transfer();
        assert_eq!((first, second), (1, 2));
        first_flag.store(true, Ordering::Relaxed);
        assert!(
            !second_flag.load(Ordering::Relaxed),
            "a cancel aimed at the first operation must never reach the one after it"
        );
    }

    #[test]
    fn a_cancel_for_an_operation_that_is_not_running_does_nothing() {
        let mut o = ops();
        let (id, flag) = o.claim_transfer();
        cancel_transfer(&o, id + 99);
        assert!(!flag.load(Ordering::Relaxed), "a stale id must not cancel the live operation");
        cancel_transfer(&o, id);
        assert!(flag.load(Ordering::Relaxed));
    }

    #[test]
    fn permanent_delete_owns_the_mutation_slot_and_releases_it_on_refusal() {
        let (tx, rx) = channel();
        let mut o = Ops::new(tx);
        let mut buf = out();
        o.claim_transfer();
        request_menu_action(&mut buf, &mut o, r#"{"op":"delete","id":5,"token":1}"#.into(), vec![], None);
        assert!(text(&buf).contains(r#""op":"delete","ok":false"#));
        assert!(text(&buf).contains("already running"));
        assert!(o.menuactions.is_none(), "busy refusal must not start a competing service");
        o.live.finished();
        buf.clear();
        request_menu_action(&mut buf, &mut o, r#"{"op":"delete","id":5,"token":1}"#.into(), vec![], None);
        assert!(o.live.running().is_some());
        let message = rx.recv_timeout(std::time::Duration::from_secs(5)).unwrap();
        assert!(matches!(&message, OpMsg::MenuDeleteDone { .. }));
        report_op(&mut buf, &mut o, message);
        assert!(o.live.running().is_none());
        assert!(text(&buf).contains("expired"));
    }

    #[test]
    fn menu_rename_checks_only_the_requested_captured_identity() {
        let d = TestDir::new("menu-rename");
        let first = d.file("first", "first");
        let second = d.file("second", "second");
        let foreign = d.file("foreign", "foreign");
        let (tx, rx) = channel();
        let mut o = Ops::new(tx.clone());
        let menu = super::super::menu_actions::MenuActions::new(tx);
        menu.request(r#"{"op":"snapshot","id":5}"#.into(), vec![first.to_string_lossy().into(), second.to_string_lossy().into()], None);
        let OpMsg::Meta { line } = rx.recv_timeout(std::time::Duration::from_secs(5)).unwrap() else { panic!("snapshot reply"); };
        assert!(line.contains(r#""ok":true"#));
        o.menuactions = Some(menu);
        for path in [&first, &second, &foreign] { assert!(path.is_absolute() && path.starts_with(d.path())); }
        let mut buf = out();
        do_menu_rename(&mut buf, &mut o, &first.to_string_lossy(), "first-renamed", 5);
        assert!(text(&buf).contains(r#""t":"renamed","ok":true"#));
        buf.clear();
        do_menu_rename(&mut buf, &mut o, &second.to_string_lossy(), "second-renamed", 5);
        assert!(text(&buf).contains(r#""t":"renamed","ok":true"#), "a prior successful rename must not invalidate the next captured item");
        assert_eq!(o.journal.len(), 2);
        buf.clear();
        do_menu_rename(&mut buf, &mut o, &foreign.to_string_lossy(), "wrong", 5);
        assert!(text(&buf).contains("not in the menu selection"));
        d.file("first", "replacement");
        buf.clear();
        do_menu_rename(&mut buf, &mut o, &first.to_string_lossy(), "wrong", 5);
        assert!(text(&buf).contains("Selected item changed"));
        assert_eq!(std::fs::read_to_string(&first).unwrap(), "replacement");
        assert_eq!(std::fs::read_to_string(&foreign).unwrap(), "foreign");
        buf.clear();
        do_menu_rename(&mut buf, &mut o, &first.to_string_lossy(), "wrong", 4);
        assert!(text(&buf).contains("expired"));
        assert!(!d.join("wrong").exists());
    }

    #[test]
    fn a_rename_records_its_reversal_and_undo_puts_the_name_back() {
        let d = TestDir::new("dispatchrename");
        let mut o = ops();
        let from = d.file("before.txt", "body");
        let mut buf = out();
        do_rename(&mut buf, &mut o, &from.to_string_lossy(), "after.txt");
        assert!(d.join("after.txt").exists());
        assert!(text(&buf).contains(r#""t":"renamed","ok":true"#));
        assert_eq!(o.journal.len(), 1);
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        assert!(text(&buf).contains(r#"{"t":"undone","op":"rename","ok":true}"#));
        assert!(from.exists(), "undo put the old name back");
        assert!(o.journal.is_empty());
    }

    // Journal::undo propagates with `?` and do_undo hands that error straight to error_line.
    #[test]
    fn a_failed_rename_reversal_answers_the_rename_kind_and_not_undo() {
        let d = TestDir::new("dispatchundorename");
        let mut o = ops();
        let from = d.file("before.txt", "body");
        let mut buf = out();
        do_rename(&mut buf, &mut o, &from.to_string_lossy(), "after.txt");
        // Something takes the old name back before the undo, so the reversal's own rename refuses it.
        d.file("before.txt", "squatter");
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        let line = text(&buf);
        assert!(line.contains(r#""t":"error","where":"rename""#), "{}", line);
        assert!(!line.contains(r#""where":"undo""#), "an undo must not re-stamp the kind its step answered");
    }

    #[test]
    fn a_refused_rename_records_nothing_to_undo() {
        let d = TestDir::new("dispatchrefuse");
        let mut o = ops();
        let from = d.file("a.txt", "a");
        d.file("b.txt", "b");
        let mut buf = out();
        do_rename(&mut buf, &mut o, &from.to_string_lossy(), "b.txt");
        assert!(text(&buf).contains(r#""t":"error","where":"rename""#), "the refusal is an error line, not a silent no-op");
        assert!(o.journal.is_empty(), "a rename that did not happen must not be undoable");
        assert_eq!(std::fs::read_to_string(d.join("b.txt")).unwrap(), "b");
    }

    #[test]
    fn explicit_paths_win_and_a_rows_form_resolves_against_the_listing() {
        let mut l = Listing::new();
        l.push("sub", true);
        l.push("a.txt", false);
        l.push("b.txt", false);
        let base = Path::new("/home/gm");
        // A wide selection reaches the backend as indices, because the client only holds its own window.
        assert_eq!(
            resolve_rows(Vec::new(), &[1, 2], base, &l),
            vec!["/home/gm/a.txt".to_string(), "/home/gm/b.txt".to_string()]
        );
        // A row past the end is dropped rather than panicking or naming the base directory itself.
        assert_eq!(resolve_rows(Vec::new(), &[99], base, &l), Vec::<String>::new());
        // Explicit paths are never second-guessed against the listing.
        assert_eq!(
            resolve_rows(vec!["/elsewhere/c.txt".to_string()], &[0, 1, 2], base, &l),
            vec!["/elsewhere/c.txt".to_string()]
        );
        assert_eq!(resolve_rows(Vec::new(), &[], base, &l), Vec::<String>::new());
    }

    #[test]
    fn a_second_operation_while_one_runs_is_refused_as_data_rather_than_queued_invisibly() {
        let d = TestDir::new("dispatchbusy");
        let mut o = ops();
        o.claim_transfer();
        let mut buf = out();
        start_trash(&mut buf, &mut o, vec![d.file("a.txt", "a").to_string_lossy().to_string()], 0);
        assert!(text(&buf).contains("an operation is already running"));
        assert!(d.join("a.txt").exists(), "the refused operation touched nothing");
    }

    #[test]
    fn a_terminal_message_clears_the_running_slot_so_the_next_operation_is_accepted() {
        let mut o = ops();
        o.claim_transfer();
        assert!(o.live.running().is_some());
        let mut buf = out();
        report_op(
            &mut buf,
            &mut o,
            OpMsg::Trashed { ok: 1, failed: 0, entry: Entry { op: "trash".to_string(), steps: vec![Step::Created { path: "/x".into() }] } },
        );
        assert!(o.live.running().is_none(), "the cap would otherwise refuse every operation for the rest of the session");
        assert_eq!(o.journal.len(), 1);
        assert_eq!(text(&buf).trim(), r#"{"t":"trashed","ok":1,"failed":0}"#);
    }

    #[test]
    fn a_new_folder_records_its_reversal_and_undo_removes_it() {
        let d = TestDir::new("dispatchmkdir");
        let mut o = ops();
        let mut buf = out();
        do_mkdir(&mut buf, &mut o, &d.path().to_string_lossy(), "photos");
        assert!(d.join("photos").is_dir());
        assert_eq!(text(&buf).trim(), format!(r#"{{"t":"made","ok":true,"path":"{}"}}"#, d.join("photos").display()));
        assert_eq!(o.journal.len(), 1);
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        assert!(text(&buf).contains(r#"{"t":"undone","op":"mkdir","ok":true}"#));
        assert!(!d.join("photos").exists(), "undo removed the folder it made");
        assert!(o.journal.is_empty());
    }

    #[test]
    fn a_refused_new_folder_records_nothing_to_undo() {
        let d = TestDir::new("dispatchmkdirrefuse");
        let mut o = ops();
        d.file("taken", "t");
        let mut buf = out();
        do_mkdir(&mut buf, &mut o, &d.path().to_string_lossy(), "taken");
        assert!(text(&buf).contains(r#""t":"error","where":"mkdir""#), "the refusal is an error line, not a silent no-op");
        assert!(o.journal.is_empty(), "a folder that was not made must not be undoable");
        assert_eq!(std::fs::read_to_string(d.join("taken")).unwrap(), "t");
    }

    #[test]
    fn paste_as_links_answers_one_line_and_undo_removes_them() {
        let d = TestDir::new("dispatchlink");
        let mut o = ops();
        let src = d.dir("src");
        let a = d.file("src/a.txt", "a");
        let b = d.file("src/b.txt", "b");
        let dest = d.dir("dest");
        let _ = src;
        let mut buf = out();
        let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
        do_link(&mut buf, &mut o, "relative",
            vec![a.to_string_lossy().to_string(), b.to_string_lossy().to_string()],
            &dest.to_string_lossy(), ask);
        assert_eq!(text(&buf).trim(), r#"{"t":"linked","ok":2,"failed":0,"skipped":0}"#);
        assert_eq!(o.journal.len(), 1);
        assert_eq!(std::fs::read_to_string(dest.join("a.txt")).unwrap(), "a");
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        assert!(text(&buf).contains(r#"{"t":"undone","op":"link","ok":true}"#));
        assert!(std::fs::symlink_metadata(dest.join("a.txt")).is_err());
        assert!(std::fs::symlink_metadata(dest.join("b.txt")).is_err());
        assert!(a.exists() && b.exists(), "undo removes the links, never the sources");
    }

    #[test]
    fn an_existing_name_is_refused_and_journals_nothing() {
        let d = TestDir::new("dispatchlinkrefuse");
        let mut o = ops();
        let a = d.file("a.txt", "a");
        let dest = d.dir("dest");
        d.file("dest/a.txt", "someone else");
        let mut buf = out();
        let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
        do_link(&mut buf, &mut o, "relative",
            vec![a.to_string_lossy().to_string()], &dest.to_string_lossy(), ask);
        assert!(text(&buf).contains(r#""t":"error","where":"link""#));
        assert!(o.journal.is_empty(), "a link that was not made must not be undoable");
        assert_eq!(std::fs::read_to_string(dest.join("a.txt")).unwrap(), "someone else");
    }

    #[test]
    fn a_hard_link_to_a_directory_is_refused() {
        let d = TestDir::new("dispatchharddir");
        let mut o = ops();
        let src = d.dir("src");
        let dest = d.dir("dest");
        let mut buf = out();
        let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
        do_link(&mut buf, &mut o, "hard", vec![src.to_string_lossy().to_string()], &dest.to_string_lossy(), ask);
        let line = text(&buf);
        assert!(line.contains("a hard link to a directory is refused"), "{}", line);
        assert!(line.contains(r#""where":"link""#), "{}", line);
        assert!(std::fs::symlink_metadata(dest.join("src")).is_err());
        assert!(o.journal.is_empty());
    }

    #[test]
    fn an_unverifiable_link_whose_cleanup_fails_names_the_leftover() {
        let d = TestDir::new("dispatchlinkleftover");
        let mut o = ops();
        let a = d.file("a.txt", "a");
        let dest = d.dir("dest");
        test_fail_link_verify(true);
        let mut buf = out();
        let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
        do_link(&mut buf, &mut o, "relative",
            vec![a.to_string_lossy().to_string()], &dest.to_string_lossy(), ask);
        test_fail_link_verify(false);
        let line = text(&buf);
        let at = dest.join("a.txt");
        assert!(line.contains(&at.to_string_lossy().into_owned()), "leftover unnamed: {}", line);
        assert!(line.contains("could not be removed"), "cleanup failure silent: {}", line);
        assert!(at.symlink_metadata().is_ok(), "the leftover stays and is reported, never dropped");
        assert!(o.journal.is_empty(), "a link never identified journals nothing");
    }

    #[test]
    fn a_link_into_an_unwritable_folder_answers_link() {
        use std::os::unix::fs::PermissionsExt;
        let d = TestDir::new("dispatchlinknowrite");
        let mut o = ops();
        let a = d.file("a.txt", "a");
        let dest = d.dir("dest");
        std::fs::set_permissions(&dest, std::fs::Permissions::from_mode(0o555)).unwrap();
        let mut buf = out();
        let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
        do_link(&mut buf, &mut o, "relative", vec![a.to_string_lossy().to_string()], &dest.to_string_lossy(), ask);
        std::fs::set_permissions(&dest, std::fs::Permissions::from_mode(0o755)).unwrap();
        let line = text(&buf);
        assert!(line.contains(r#""where":"link""#), "{}", line);
        assert!(line.contains("that folder cannot be written"), "usable_dest refused, not the link: {}", line);
        assert!(o.journal.is_empty());
    }

    #[test]
    fn a_folder_put_at_a_link_name_survives_undo() {
        let d = TestDir::new("dispatchlinkkept");
        let mut o = ops();
        let a = d.file("a.txt", "a");
        let dest = d.dir("dest");
        let mut buf = out();
        let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
        do_link(&mut buf, &mut o, "relative",
            vec![a.to_string_lossy().to_string()], &dest.to_string_lossy(), ask);
        assert!(text(&buf).contains(r#""t":"linked""#));
        let at = dest.join("a.txt");
        std::fs::remove_file(&at).unwrap();
        let folder = d.dir("dest/a.txt");
        std::fs::write(folder.join("kept.txt"), "kept").unwrap();
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        assert!(text(&buf).contains(r#""t":"error","where":"undo""#), "undo refuses a name that stopped being its link");
        assert_eq!(std::fs::read_to_string(folder.join("kept.txt")).unwrap(), "kept");
    }

    #[test]
    fn undone_links_redo_in_each_kind() {
        for op in ["relative", "absolute", "hard"] {
            let d = TestDir::new("dispatchlinkredo");
            let mut o = ops();
            let a = d.file("a.txt", "a");
            let dest = d.dir("dest");
            let mut buf = out();
            let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
            do_link(&mut buf, &mut o, op,
                vec![a.to_string_lossy().to_string()], &dest.to_string_lossy(), ask);
            assert!(text(&buf).contains(r#""t":"linked""#), "link lands for {op}");
            let at = dest.join("a.txt");
            let mut buf = out();
            do_undo(&mut buf, &mut o);
            assert!(text(&buf).contains(r#""t":"undone""#), "undo removes the {op} link");
            assert!(std::fs::symlink_metadata(&at).is_err());
            let (tx, _rx) = channel();
            let redone = o.journal.redo(1, &AtomicBool::new(false), &tx);
            assert_eq!(redone.unwrap(), "link", "redo recreates the {op} link");
            if op == "hard" {
                use std::os::unix::fs::MetadataExt;
                assert!(!at.symlink_metadata().unwrap().file_type().is_symlink());
                assert_eq!(a.metadata().unwrap().ino(), at.metadata().unwrap().ino());
            } else {
                assert!(at.symlink_metadata().unwrap().file_type().is_symlink());
                assert_eq!(std::fs::read_to_string(&at).unwrap(), "a");
            }
            assert!(o.journal.redo_info().is_err(), "a redone entry is undoable, not redoable again");
            let mut buf = out();
            do_undo(&mut buf, &mut o);
            assert!(text(&buf).contains(r#""t":"undone""#));
            assert!(std::fs::symlink_metadata(&at).is_err());
        }
    }

    #[test]
    fn redo_refuses_a_link_name_taken_since() {
        let d = TestDir::new("dispatchlinkredotaken");
        let mut o = ops();
        let a = d.file("a.txt", "a");
        let dest = d.dir("dest");
        let mut buf = out();
        let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
        do_link(&mut buf, &mut o, "relative",
            vec![a.to_string_lossy().to_string()], &dest.to_string_lossy(), ask);
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        std::fs::write(dest.join("a.txt"), "someone else").unwrap();
        let (tx, _rx) = channel();
        let redone = o.journal.redo(1, &AtomicBool::new(false), &tx);
        assert!(redone.unwrap_err().msg.contains("already exists"));
        assert_eq!(std::fs::read_to_string(dest.join("a.txt")).unwrap(), "someone else");
    }

    #[test]
    fn undoing_a_hard_link_keeps_the_last_name_when_its_source_is_gone() {
        let d = TestDir::new("link-hard-last");
        let mut o = ops();
        d.dir("src");
        let a = d.file("src/a.txt", "precious");
        let dest = d.dir("dest");
        let mut buf = out();
        let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
        do_link(&mut buf, &mut o, "hard",
            vec![a.to_string_lossy().to_string()], &dest.to_string_lossy(), ask);
        assert!(text(&buf).contains(r#""ok":1"#), "{}", text(&buf));
        std::fs::remove_file(&a).unwrap();
        assert_eq!(std::fs::read_to_string(dest.join("a.txt")).unwrap(), "precious");
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        assert!(std::fs::read_to_string(dest.join("a.txt")).is_ok(),
            "undo removed the only remaining name; undo said {}", text(&buf));
        assert!(text(&buf).contains("last name"), "{}", text(&buf));
    }

    #[test]
    fn a_link_landing_during_a_redo_is_refused_busy_and_keeps_its_undo() {
        let d = TestDir::new("link-redo-busy");
        let (tx, rx) = channel();
        let mut o = Ops::new(tx);
        let parent = d.dir("p");
        let mut buf = out();
        do_mkdir(&mut buf, &mut o, &parent.to_string_lossy(), "made");
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        assert!(text(&buf).contains("undone"), "{}", text(&buf));
        let mut buf = out();
        start_redo(&mut buf, &mut o);
        assert!(text(&buf).contains("redostarted"), "{}", text(&buf));
        let a = d.file("a.txt", "a");
        let dest = d.dir("dest");
        let mut buf = out();
        let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
        do_link(&mut buf, &mut o, "relative",
            vec![a.to_string_lossy().to_string()], &dest.to_string_lossy(), ask);
        assert!(text(&buf).contains("already running"), "{}", text(&buf));
        assert!(!text(&buf).contains(r#""t":"linked""#), "{}", text(&buf));
        assert!(o.journal.is_empty(), "a refused link journals nothing");
        loop {
            let msg = rx.recv().unwrap();
            let done = matches!(msg, OpMsg::RedoDone { .. });
            let mut sink = out();
            report_op(&mut sink, &mut o, msg);
            if done { break; }
        }
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        assert!(text(&buf).contains(r#""op":"mkdir""#), "{}", text(&buf));
    }

    #[test]
    fn a_hard_link_of_a_symlink_undoes() {
        let d = TestDir::new("link-hard-sym");
        let mut o = ops();
        d.dir("src");
        let t = d.file("src/t.txt", "t");
        let l = d.join("src/l");
        std::os::unix::fs::symlink(&t, &l).unwrap();
        let dest = d.dir("dest");
        let mut buf = out();
        let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
        do_link(&mut buf, &mut o, "hard",
            vec![l.to_string_lossy().to_string()], &dest.to_string_lossy(), ask);
        assert!(text(&buf).contains(r#""t":"linked""#), "{}", text(&buf));
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        assert!(text(&buf).contains("undone"), "untouched link refused by undo: {}", text(&buf));
        assert!(std::fs::symlink_metadata(dest.join("l")).is_err());
        assert!(l.symlink_metadata().is_ok(), "undo removes the link, never the source");
    }

    #[test]
    fn a_hard_link_of_a_fifo_undoes_and_redoes() {
        let d = TestDir::new("link-hard-fifo");
        let mut o = ops();
        let src = d.join("src.pipe");
        assert!(std::process::Command::new("mkfifo").arg(&src).status().unwrap().success());
        let dest = d.dir("dest");
        let mut buf = out();
        let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
        do_link(&mut buf, &mut o, "hard", vec![src.to_string_lossy().to_string()], &dest.to_string_lossy(), ask);
        assert!(text(&buf).contains(r#""t":"linked""#), "{}", text(&buf));
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        assert!(text(&buf).contains("undone"), "fifo link refused by undo: {}", text(&buf));
        assert!(std::fs::symlink_metadata(dest.join("src.pipe")).is_err());
        let (tx, _rx) = channel();
        assert_eq!(o.journal.redo(1, &AtomicBool::new(false), &tx).unwrap(), "link");
        assert!(dest.join("src.pipe").symlink_metadata().is_ok());
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        assert!(text(&buf).contains("undone"), "{}", text(&buf));
    }

    #[test]
    fn a_link_to_a_missing_source_is_refused_per_path() {
        let d = TestDir::new("link-missing");
        let mut o = ops();
        let gone = d.join("gone.txt");
        let dest = d.dir("dest");
        let mut buf = out();
        let ask = crate::backend::collide::Ask::parse(r#"{"c":"link"}"#);
        do_link(&mut buf, &mut o, "relative",
            vec![gone.to_string_lossy().to_string()], &dest.to_string_lossy(), ask);
        assert!(!text(&buf).contains(r#""ok":1"#), "a link to nothing reported success: {}", text(&buf));
        assert!(o.journal.is_empty(), "a refused link journals nothing");
        assert!(std::fs::symlink_metadata(dest.join("gone.txt")).is_err());
    }

    #[test]
    fn a_permissions_batch_during_a_redo_is_refused_busy() {
        let d = TestDir::new("perm-busy");
        let (tx, rx) = channel();
        let mut o = Ops::new(tx);
        let parent = d.dir("p");
        let mut buf = out();
        do_mkdir(&mut buf, &mut o, &parent.to_string_lossy(), "made");
        let mut buf = out();
        do_undo(&mut buf, &mut o);
        let mut buf = out();
        start_redo(&mut buf, &mut o);
        assert!(text(&buf).contains("redostarted"), "{}", text(&buf));
        let a = d.file("a.txt", "a");
        let mut buf = out();
        do_permissions_batch(&mut buf, &mut o,
            vec![a.to_string_lossy().to_string()], vec!["600".to_string()], 7);
        let line = text(&buf);
        assert!(line.contains("already running"), "{}", line);
        assert!(line.contains(r#""ok":false"#), "{}", line);
        assert!(o.journal.is_empty(), "a refused chmod journals nothing");
        loop {
            let msg = rx.recv_timeout(std::time::Duration::from_secs(5)).unwrap();
            let done = matches!(msg, OpMsg::RedoDone { .. });
            let mut sink = out();
            report_op(&mut sink, &mut o, msg);
            if done { break; }
        }
    }
}
