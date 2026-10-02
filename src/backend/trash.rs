// gio trash is the freedesktop trash this box already shares with every GTK app; nothing about the spec is written here, only an argv and a result.
use crate::error::FleaError;
use std::path::{Path, PathBuf};
use std::process::Command;

// gio trash --list prints one entry per line as "<uri>\t<original path>".
const LIST_SEP: char = '\t';
// A hung mount must not hold the single operation slot; trashbrowse.rs bounds gio the same way.
const TRASH_TIMEOUT: &str = "10s";
const TRASH_KILL_AFTER: &str = "1s";

// What a successful trash recorded, which is the only thing that can reverse it.
#[derive(Clone, Debug, PartialEq)]
pub struct Entry {
    pub original: PathBuf,
    pub uri: String,
}

// A test stands in for gio on its own thread, because a build container has no trash:// to list or restore.
#[cfg(test)]
thread_local! {
    pub(crate) static STAND_IN: std::cell::RefCell<Option<std::rc::Rc<dyn Fn(&[&str]) -> Option<std::process::Output>>>> =
        const { std::cell::RefCell::new(None) };
}

// corner: gio on an unresponsive network mount can hang, which stalls this operation's own thread and nothing else.
fn gio(args: &[&str]) -> Option<std::process::Output> {
    #[cfg(test)]
    if let Some(stand_in) = STAND_IN.with(|slot| slot.borrow().clone()) {
        return stand_in(args);
    }
    let kill = format!("--kill-after={TRASH_KILL_AFTER}");
    Command::new("timeout").args([kill.as_str(), TRASH_TIMEOUT, "gio"]).args(args).output().ok()
}

// The batch's own reason, so a hung mount or a denial reads as what happened rather than silence.
fn failure_reason(output: &Option<std::process::Output>) -> String {
    match output {
        None => "gio could not be run to move items to Trash".to_string(),
        Some(o) if matches!(o.status.code(), Some(124 | 137)) => "Trash took too long to answer".to_string(),
        Some(o) => {
            let line = String::from_utf8_lossy(&o.stderr).lines().last().unwrap_or("").trim().to_string();
            if line.is_empty() { "gio trash failed".to_string() } else { line }
        }
    }
}

// Sample line: trash:///a.txt\t/home/gm/a.txt
fn parse_list(stdout: &str) -> Vec<Entry> {
    let mut out = Vec::new();
    for line in stdout.lines() {
        let mut parts = line.splitn(2, LIST_SEP);
        let uri = match parts.next() {
            Some(u) if !u.is_empty() => u,
            _ => continue,
        };
        if let Some(original) = parts.next() {
            if !original.is_empty() {
                out.push(Entry { original: PathBuf::from(original), uri: uri.to_string() });
            }
        }
    }
    out
}

pub fn list() -> Vec<Entry> {
    match gio(&["trash", "--list"]) {
        Some(o) => parse_list(&String::from_utf8_lossy(&o.stdout)),
        None => Vec::new(),
    }
}

// The URI is captured here rather than looked up later, because gio trash --restore refuses an original
// path outright and two files trashed from one path both list that same path, so a later lookup is ambiguous.
pub fn trash(paths: &[PathBuf]) -> (Vec<Entry>, usize, String) {
    match trash_checked(paths, None) {
        Ok(result) => result,
        Err(error) => { eprintln!("flea: {}", error); (Vec::new(), paths.len(), error) }
    }
}

pub(crate) fn trash_checked(paths: &[PathBuf], selection: Option<&[super::menu_actions::Selected]>) -> Result<(Vec<Entry>, usize, String), String> {
    // A leading empty path is a drag that left this window. The receiver may already have moved
    // the file and still accepted a move; a path that is gone is then nothing left to delete.
    let (quiet_gone, paths) = match paths.first() {
        Some(path) if path.as_os_str().is_empty() => (true, &paths[1..]),
        _ => (false, paths),
    };
    super::menu_actions::validate_sources(selection, paths)?;
    if paths.is_empty() {
        return Ok((Vec::new(), 0, String::new()));
    }
    // Issue 88, nixfred: a path already gone before the call read as trashed afterwards and was
    // journaled as a step with no trash entry, which is where undo stopped, so it is a failure here.
    let (present, missing): (Vec<&PathBuf>, Vec<&PathBuf>) =
        paths.iter().partition(|p| p.symlink_metadata().is_ok());
    if present.is_empty() {
        let reason = if quiet_gone || missing.is_empty() { String::new() } else { "those items are already gone".to_string() };
        return Ok((Vec::new(), if quiet_gone { 0 } else { missing.len() }, reason));
    }
    let before = list();
    let mut argv: Vec<String> = vec!["trash".to_string(), "--".to_string()];
    for p in &present {
        argv.push(p.to_string_lossy().to_string());
    }
    let refs: Vec<&str> = argv.iter().map(|s| s.as_str()).collect();
    super::menu_actions::validate_sources(selection, paths)?;
    // The exit status covers the whole batch, so which paths actually went is read off the filesystem instead.
    let output = gio(&refs);
    let after = list();
    let mut ok = Vec::new();
    let mut failed = if quiet_gone { 0 } else { missing.len() };
    for p in present {
        if p.symlink_metadata().is_ok() {
            failed += 1;
            continue;
        }
        match newest_entry_for(&before, &after, p) {
            Some(e) => ok.push(e),
            // corner: the file went but gio listed no entry for it, so it is gone and simply not reversible.
            None => ok.push(Entry { original: (*p).clone(), uri: String::new() }),
        }
    }
    let gio_failed = !matches!(&output, Some(o) if o.status.success());
    let reason = if failed == 0 {
        String::new()
    } else if gio_failed {
        failure_reason(&output)
    } else {
        "those items are already gone".to_string()
    };
    Ok((ok, failed, reason))
}

// Only an entry that was not already in the trash before this call can be one this call put there.
fn newest_entry_for(before: &[Entry], after: &[Entry], path: &Path) -> Option<Entry> {
    after
        .iter()
        .find(|e| e.original == path && !before.iter().any(|b| b.uri == e.uri))
        .cloned()
}

pub fn restore(entry: &Entry) -> Result<(), FleaError> {
    if entry.uri.is_empty() {
        return Err(err("this item was trashed without a trash entry, so it cannot be restored"));
    }
    match gio(&["trash", "--restore", &entry.uri]) {
        Some(o) if o.status.success() => Ok(()),
        Some(o) => {
            let msg = String::from_utf8_lossy(&o.stderr);
            Err(err(msg.lines().last().unwrap_or("gio trash --restore failed")))
        }
        None => Err(err("gio is not available to restore from the trash")),
    }
}

fn err(msg: &str) -> FleaError {
    FleaError { where_: "undo".to_string(), path: String::new(), msg: msg.to_string() }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Issue 88, nixfred: a path the user's listing still names and the filesystem no longer has is a
    // failure, so it never becomes a journal step that undo cannot reverse. tests/ops.sh drives the pair.
    #[test]
    fn paths_that_are_already_gone_are_failures_rather_than_trashed() {
        let gone = vec![PathBuf::from("/nonexistent/flea-88-a.txt"), PathBuf::from("/nonexistent/flea-88-b.txt")];
        let (entries, failed, reason) = trash_checked(&gone, None).expect("a batch of missing paths is not an error");
        assert!(entries.is_empty(), "nothing was trashed, so nothing is journaled");
        assert_eq!(failed, 2, "both are counted as failures rather than as trashed");
        assert!(reason.contains("already gone"), "the reason names the gone paths: {reason}");
    }

    #[test]
    fn a_drag_release_does_not_fail_when_the_receiver_already_moved_the_file() {
        let gone = vec![PathBuf::new(), PathBuf::from("/nonexistent/flea-drag-release.txt")];
        let (entries, failed, reason) = trash_checked(&gone, None).expect("quiet");
        assert!(entries.is_empty());
        assert_eq!(failed, 0);
        assert!(reason.is_empty(), "nothing failed, so no reason rides along");
    }

    #[test]
    fn a_timed_out_trash_names_the_wait_rather_than_going_silent() {
        assert_eq!(TRASH_TIMEOUT, "10s", "the named bound gio runs under");
        assert_eq!(failure_reason(&None), "gio could not be run to move items to Trash");
    }

    #[test]
    fn a_failed_trash_carries_gios_own_last_line() {
        use std::os::unix::process::ExitStatusExt;
        let output = Some(std::process::Output { status: std::process::ExitStatus::from_raw(256),
            stdout: Vec::new(), stderr: b"gio: Error 1: Permission denied\n".to_vec() });
        assert!(failure_reason(&output).contains("Permission denied"));
        let timed_out = Some(std::process::Output { status: std::process::ExitStatus::from_raw(124 << 8),
            stdout: Vec::new(), stderr: Vec::new() });
        assert_eq!(failure_reason(&timed_out), "Trash took too long to answer");
    }

    #[test]
    fn a_list_line_splits_on_the_tab_and_keeps_a_path_containing_spaces() {
        let out = "trash:///a.txt\t/home/gm/a.txt\ntrash:///my%20file\t/home/gm/my file\n";
        let got = parse_list(out);
        assert_eq!(got.len(), 2);
        assert_eq!(got[0].uri, "trash:///a.txt");
        assert_eq!(got[0].original, PathBuf::from("/home/gm/a.txt"));
        assert_eq!(got[1].original, PathBuf::from("/home/gm/my file"));
    }

    #[test]
    fn a_malformed_list_line_is_skipped_rather_than_panicking() {
        let got = parse_list("no tab here\n\n\tmissing uri\ntrash:///ok\t/x\ntrash:///nopath\t\n");
        assert_eq!(got.len(), 1, "only the one well-formed line survives");
        assert_eq!(got[0].uri, "trash:///ok");
    }

    #[test]
    fn only_an_entry_absent_before_the_call_is_taken_as_ours() {
        let p = PathBuf::from("/home/gm/dup.txt");
        let before = vec![Entry { original: p.clone(), uri: "trash:///dup.txt".to_string() }];
        let after = vec![
            Entry { original: p.clone(), uri: "trash:///dup.txt".to_string() },
            Entry { original: p.clone(), uri: "trash:///dup.2.txt".to_string() },
        ];
        // Both entries name the same original, which is exactly why the URI is captured at trash time.
        let got = newest_entry_for(&before, &after, &p).expect("the new one");
        assert_eq!(got.uri, "trash:///dup.2.txt");
    }

    #[test]
    fn an_entry_with_no_uri_refuses_to_restore_instead_of_running_gio_with_an_empty_argument() {
        let e = Entry { original: PathBuf::from("/x"), uri: String::new() };
        let err = restore(&e).expect_err("must refuse");
        assert_eq!(err.where_, "undo");
        assert!(err.msg.contains("cannot be restored"));
    }

    #[test]
    fn trashing_nothing_runs_no_subprocess_and_reports_nothing() {
        let (ok, failed, reason) = trash(&[]);
        assert!(ok.is_empty());
        assert_eq!(failed, 0);
        assert!(reason.is_empty());
    }

    #[test]
    fn a_refused_trash_reports_gios_reason_for_the_wire() {
        use std::os::unix::process::ExitStatusExt;
        use std::rc::Rc;
        let d = crate::backend::testdir::TestDir::new("trash-refused-reason");
        let kept = d.file("kept.txt", "stays");
        STAND_IN.with(|slot| *slot.borrow_mut() = Some(Rc::new(move |args: &[&str]| {
            if args.first() == Some(&"trash") && !args.contains(&"--list") {
                return Some(std::process::Output { status: std::process::ExitStatus::from_raw(256),
                    stdout: Vec::new(), stderr: b"gio: Operation not supported\n".to_vec() });
            }
            Some(std::process::Output { status: std::process::ExitStatus::from_raw(0),
                stdout: Vec::new(), stderr: Vec::new() })
        })));
        let (ok, failed, reason) = trash_checked(std::slice::from_ref(&kept), None).expect("a refused batch is not an error");
        STAND_IN.with(|slot| *slot.borrow_mut() = None);
        assert!(ok.is_empty());
        assert_eq!(failed, 1);
        assert!(reason.contains("not supported"), "gio's own refusal rides the wire: {reason}");
    }
}
