// One reviewed object stays open until its dialog closes; mode writes never walk a directory.
use crate::json::{escape, field_str, field_usize};
use crate::oflags::O_NOFOLLOW;
#[cfg(test)]
use std::fs::Permissions as Mode;
use std::fs::{File, Metadata, OpenOptions};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};

const O_PATH: i32 = 0o10000000;
const AT_EMPTY_PATH: i32 = 0x1000;
// Linux assigns fchmodat2 number 452 on both supported 64-bit architectures.
const SYS_FCHMODAT2: std::os::raw::c_long = 452;
const SPECIAL_BITS: u32 = 0o7000;
extern "C" {
    fn geteuid() -> u32;
    fn syscall(number: std::os::raw::c_long, ...) -> std::os::raw::c_long;
}

#[derive(Default)]
pub struct Permissions {
    held: Option<Reviewed>,
}
struct Reviewed {
    id: usize,
    path: PathBuf,
    file: File,
    dev: u64,
    ino: u64,
}

// Sample input: "644" or "0644"; special bits and partial/whitespace inputs are not ordinary modes.
fn mode(text: &str) -> Result<u32, String> {
    let ordinary = text.len() == 3 || (text.len() == 4 && text.starts_with('0'));
    if !ordinary || !text.bytes().all(|b| (b'0'..=b'7').contains(&b)) {
        return Err("Enter three octal digits or a leading-zero four-digit mode.".into());
    }
    u32::from_str_radix(text, 8).map_err(|e| e.to_string())
}

fn reason(meta: &Metadata, uid: u32) -> String {
    for (bit, label) in [(0o4000, "setuid"), (0o2000, "setgid"), (0o1000, "sticky")] {
        if meta.mode() & bit != 0 {
            return format!("Read-only: {} bit is present.", label);
        }
    }
    if meta.uid() != uid {
        return "Read-only: you are not the owner.".into();
    }
    String::new()
}

// Sample input, /etc/group: "gm:x:1000:gm".
fn group_name(gid: u32) -> String {
    let text = std::fs::read_to_string("/etc/group").unwrap_or_default();
    for line in text.lines() {
        let mut fields = line.split(':');
        let name = fields.next().unwrap_or("");
        if fields.nth(1).and_then(|s| s.parse::<u32>().ok()) == Some(gid) {
            return name.into();
        }
    }
    String::new()
}

// A batch failure carries what stayed applied, or nothing when the batch rolled back whole.
#[derive(Debug)]
pub struct BatchError {
    pub msg: String,
    pub applied: Vec<crate::backend::undo::Step>,
}

#[cfg(test)]
thread_local! {
    static FAIL_AT: std::cell::Cell<Option<usize>> = const { std::cell::Cell::new(None) };
    static FAIL_RESTORE: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

// The k-th apply of the next batch fails without removing anything itself.
#[cfg(test)]
pub fn test_fail_at(index: Option<usize>) {
    FAIL_AT.with(|v| v.set(index));
}

// Every rollback of the next batch fails without racing the filesystem.
#[cfg(test)]
pub fn test_fail_restore(fail: bool) {
    FAIL_RESTORE.with(|v| v.set(fail));
}

fn fail_at(index: usize) -> bool {
    #[cfg(test)]
    {
        FAIL_AT.with(|v| v.get()) == Some(index)
    }
    #[cfg(not(test))]
    {
        let _ = index;
        false
    }
}

fn fail_restore() -> bool {
    #[cfg(test)]
    {
        FAIL_RESTORE.with(|v| v.get())
    }
    #[cfg(not(test))]
    {
        false
    }
}

// Sample input: items [("/a.txt", "600"), ("/b dir/c.txt", "644")]. One Entry holds every change for one undo.
// Every path is an absolute file or folder, never a link; a short failure rolls back what changed, newest first.
pub fn apply_many(items: &[(PathBuf, String)]) -> Result<Vec<crate::backend::undo::Step>, BatchError> {
    if items.is_empty() {
        return Err(BatchError { msg: "Permissions needs at least one selected item.".into(), applied: Vec::new() });
    }
    let uid = unsafe { geteuid() };
    let mut checked: Vec<(PathBuf, u32)> = Vec::with_capacity(items.len());
    for (path, text) in items {
        let requested = mode(text).map_err(|e| BatchError { msg: e, applied: Vec::new() })?;
        if !path.is_absolute() {
            return Err(BatchError { msg: "Permissions requires an absolute path and request identity.".into(), applied: Vec::new() });
        }
        let before = path.symlink_metadata()
            .map_err(|e| BatchError { msg: format!("Could not inspect permissions: {}.", crate::error::io_message(&e)), applied: Vec::new() })?;
        if !(before.is_file() || before.is_dir()) {
            return Err(BatchError { msg: "Permissions takes one file or folder, not a link.".into(), applied: Vec::new() });
        }
        if before.mode() & SPECIAL_BITS != 0 {
            return Err(BatchError { msg: "Special permissions cannot be edited.".into(), applied: Vec::new() });
        }
        if !reason(&before, uid).is_empty() {
            return Err(BatchError { msg: reason(&before, uid), applied: Vec::new() });
        }
        checked.push((path.clone(), requested));
    }
    let mut steps = Vec::with_capacity(checked.len());
    for (index, (path, requested)) in checked.iter().enumerate() {
        let outcome: Result<crate::backend::undo::Step, String> = (|| {
            if fail_at(index) {
                return Err(format!("Could not inspect permissions: {}.",
                    crate::error::io_message(&std::io::Error::from(std::io::ErrorKind::NotFound))));
            }
            let before = path.symlink_metadata()
                .map_err(|e| format!("Could not inspect permissions: {}.", crate::error::io_message(&e)))?;
            if !(before.is_file() || before.is_dir()) {
                return Err("Permissions takes one file or folder, not a link.".into());
            }
            if before.mode() & SPECIAL_BITS != 0 {
                return Err("Special permissions cannot be edited.".into());
            }
            let (dev, ino, before_bits) = (before.dev(), before.ino(), before.mode() & 0o777);
            chmod_pinned(path, dev, ino, before_bits, *requested)
                .map_err(|e| format!("Could not change mode: {}.", e))?;
            Ok(crate::backend::undo::Step::Mode { path: path.clone(), before: before_bits, after: *requested, dev, ino })
        })();
        match outcome {
            Ok(step) => steps.push(step),
            Err(failure) => {
                let mut stuck = Vec::new();
                for step in steps.iter().rev() {
                    if let crate::backend::undo::Step::Mode { path, before, after, dev, ino } = step {
                        if fail_restore() || crate::backend::undo::restore_mode(path, *dev, *ino, *after, *before).is_err() {
                            stuck.push(step.clone());
                        }
                    }
                }
                stuck.reverse();
                if stuck.is_empty() {
                    return Err(BatchError { msg: format!("{} No change was applied.", failure), applied: Vec::new() });
                }
                return Err(BatchError {
                    msg: format!("{} {} of {} items were changed; undo restores them.", failure, stuck.len(), items.len()),
                    applied: stuck,
                });
            }
        }
    }
    Ok(steps)
}

// The held O_PATH descriptor is identity-checked and changed by fchmodat2, never by pathname.
pub(crate) fn chmod_pinned(path: &Path, dev: u64, ino: u64, expected: u32, target: u32) -> Result<(), String> {
    let current = path.symlink_metadata().map_err(|e| crate::error::io_message(&e))?;
    if current.file_type().is_symlink() {
        return Err("Permissions takes one file or folder, not a link.".into());
    }
    if current.dev() != dev || current.ino() != ino {
        return Err("the item was replaced, so its mode was left in place.".into());
    }
    if current.mode() & 0o777 != expected {
        return Err("the mode changed since, so it was left in place.".into());
    }
    let file = OpenOptions::new().read(true).custom_flags(O_NOFOLLOW | O_PATH)
        .open(path).map_err(|e| crate::error::io_message(&e))?;
    let meta = file.metadata().map_err(|e| crate::error::io_message(&e))?;
    if meta.dev() != dev || meta.ino() != ino {
        return Err("the item was replaced, so its mode was left in place.".into());
    }
    if meta.mode() & 0o777 != expected {
        return Err("the mode changed since, so it was left in place.".into());
    }
    if unsafe { syscall(SYS_FCHMODAT2, file.as_raw_fd(), c"".as_ptr(), target, AT_EMPTY_PATH) } != 0 {
        return Err(crate::error::io_message(&std::io::Error::last_os_error()));
    }
    Ok(())
}

impl Permissions {
    // Sample input: {"c":"permissions","op":"inspect","id":1,"path":"/tmp/item"}.
    pub fn handle(&mut self, line: &str) -> String {
        let id = field_usize(line, "id").unwrap_or(0);
        let op = field_str(line, "op").unwrap_or_default();
        let result = match op.as_str() {
            "inspect" => self.inspect(id, Path::new(&field_str(line, "path").unwrap_or_default())),
            "apply" => self.apply(id, &field_str(line, "mode").unwrap_or_default()),
            "close" => {
                if self.held.as_ref().map(|h| h.id) == Some(id) {
                    self.held = None;
                }
                Ok(format!(
                    r#"{{"t":"permissions","id":{},"op":"close","ok":true}}"#,
                    id
                ))
            }
            _ => Err("Unknown permissions operation.".into()),
        };
        result.unwrap_or_else(|err| {
            format!(
                r#"{{"t":"permissions","id":{},"op":"{}","ok":false,"error":"{}"}}"#,
                id,
                escape(&op),
                escape(&err)
            )
        })
    }

    fn inspect(&mut self, id: usize, path: &Path) -> Result<String, String> {
        self.held = None;
        if id == 0 || !path.is_absolute() {
            return Err("Permissions requires an absolute path and request identity.".into());
        }
        let before = path
            .symlink_metadata()
            .map_err(|e| format!("Could not inspect permissions: {}.", crate::error::io_message(&e)))?;
        if !(before.is_file() || before.is_dir()) {
            return Err("Permissions takes one file or folder, not a link.".into());
        }
        let file = OpenOptions::new()
            .read(true)
            .custom_flags(O_NOFOLLOW | O_PATH)
            .open(path)
            .map_err(|e| format!("Could not open selected item for permissions: {}.", crate::error::io_message(&e)))?;
        let meta = file.metadata().map_err(|e| crate::error::io_message(&e))?;
        if meta.dev() != before.dev() || meta.ino() != before.ino() {
            return Err("Selected item changed; reopen Permissions.".into());
        }
        let why = reason(&meta, unsafe { geteuid() });
        let response = format!(
            r#"{{"t":"permissions","id":{},"op":"inspect","ok":true,"path":"{}","directory":{},"mode":"{:04o}","uid":{},"gid":{},"owner":"{}","group":"{}","reason":"{}"}}"#,
            id,
            escape(&path.to_string_lossy()),
            meta.is_dir(),
            meta.mode() & 0o7777,
            meta.uid(),
            meta.gid(),
            escape(&super::owner::name(meta.uid())),
            escape(&group_name(meta.gid())),
            escape(&why)
        );
        self.held = Some(Reviewed {
            id,
            path: path.into(),
            dev: meta.dev(),
            ino: meta.ino(),
            file,
        });
        Ok(response)
    }

    fn apply(&mut self, id: usize, text: &str) -> Result<String, String> {
        let requested = mode(text)?;
        let held = self
            .held
            .as_ref()
            .filter(|h| h.id == id)
            .ok_or("Permissions selection expired; reopen the dialog.")?;
        let meta = held.file.metadata().map_err(|e| crate::error::io_message(&e))?;
        let current = held
            .path
            .symlink_metadata()
            .map_err(|_| "Selected item moved or disappeared; reopen Permissions.")?;
        if current.dev() != held.dev
            || current.ino() != held.ino
            || current.file_type().is_symlink()
        {
            return Err("Selected item changed; reopen Permissions.".into());
        }
        if meta.dev() != held.dev || meta.ino() != held.ino {
            return Err("Held item identity changed.".into());
        }
        let why = reason(&meta, unsafe { geteuid() });
        if !why.is_empty() {
            return Err(why);
        }
        if meta.mode() & SPECIAL_BITS != 0 {
            return Err("Special permissions cannot be edited.".into());
        }
        // O_PATH can review mode 0000; empty-path fchmodat2 changes that held object without reopening a pathname.
        if unsafe {
            syscall(
                SYS_FCHMODAT2,
                held.file.as_raw_fd(),
                c"".as_ptr(),
                requested,
                AT_EMPTY_PATH,
            )
        } != 0
        {
            return Err(format!(
                "Could not change mode: {}. No change was applied.",
                crate::error::io_message(&std::io::Error::last_os_error())
            ));
        }
        Ok(format!(
            r#"{{"t":"permissions","id":{},"op":"apply","ok":true,"mode":"{:04o}"}}"#,
            id, requested
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    use crate::backend::testdir::TestDir;
    #[test]
    fn inspect_failures_report_plain_causes() {
        let d = TestDir::new("permissions-plain-error");
        let mut permissions = Permissions::default();
        let missing = permissions.handle(&format!(
            r#"{{"c":"permissions","op":"inspect","id":1,"path":"{}"}}"#,
            escape(&d.join("missing").to_string_lossy())
        ));
        assert_eq!(field_str(&missing, "error").unwrap(), "Could not inspect permissions: file or folder not found.");
        let parent = d.dir("locked");
        let path = d.file("locked/file", "retained contents");
        d.assert_contains(&parent);
        std::fs::set_permissions(&parent, Mode::from_mode(0o0)).unwrap();
        let refused = permissions.inspect(2, &path);
        std::fs::set_permissions(&parent, Mode::from_mode(0o700)).unwrap();
        assert_eq!(refused.unwrap_err(), "Could not inspect permissions: permission denied.");
        assert_eq!(std::fs::read(path).unwrap(), b"retained contents");
        assert!(permissions.held.is_none());
    }
    #[test]
    fn unreadable_owned_file_can_be_repaired() {
        let d = TestDir::new("permissions-unreadable");
        let path = d.file("item", "a");
        std::fs::set_permissions(&path, Mode::from_mode(0o0)).unwrap();
        let mut p = Permissions::default();
        p.inspect(1, &path).unwrap();
        p.apply(1, "600").unwrap();
        assert_eq!(path.metadata().unwrap().mode() & 0o777, 0o600);
    }
    #[test]
    fn ordinary_modes_only() {
        for text in ["644", "000", "777", "0644"] {
            assert!(mode(text).is_ok());
        }
        for text in ["", "64", "888", "4755", " 644", "0644 ", "00000", "-1"] {
            assert!(mode(text).is_err(), "{}", text);
        }
    }
    #[test]
    fn directory_change_does_not_traverse() {
        let d = TestDir::new("permissions-directory");
        let dir = d.dir("dir");
        let child = dir.join("child");
        std::fs::write(&child, "untouched").unwrap();
        let before = child.metadata().unwrap().mode();
        let mut p = Permissions::default();
        assert!(p.inspect(1, &dir).is_ok());
        assert!(p.apply(1, "0700").is_ok());
        assert_eq!(dir.metadata().unwrap().mode() & 0o777, 0o700);
        assert_eq!(child.metadata().unwrap().mode(), before);
    }
    #[test]
    fn stale_identity_symlinks_and_invalid_modes_fail_without_writes() {
        let d = TestDir::new("permissions-identity");
        let path = d.file("item", "a");
        let mut p = Permissions::default();
        p.inspect(1, &path).unwrap();
        assert!(p.apply(2, "600").is_err());
        assert!(p.apply(1, "4755").is_err());
        std::fs::rename(&path, d.join("old")).unwrap();
        d.file("item", "replacement");
        let before = path.metadata().unwrap().mode();
        assert!(p.apply(1, "600").is_err());
        assert_eq!(path.metadata().unwrap().mode(), before);
        let link = d.join("link");
        std::os::unix::fs::symlink(&path, &link).unwrap();
        assert!(p.inspect(2, &link).is_err());
        assert!(p.apply(1, "600").is_err());
        assert!(p.inspect(3, &d.join("missing")).is_err());
        assert!(p.inspect(0, &path).is_err());
        assert!(p.inspect(4, Path::new("relative")).is_err());
    }
    #[test]
    fn special_bits_and_non_owner_are_read_only() {
        let d = TestDir::new("permissions-special");
        let path = d.file("item", "a");
        let mut p = Permissions::default();
        for (bits, label) in [(0o4644, "setuid"), (0o2644, "setgid"), (0o1644, "sticky")] {
            std::fs::set_permissions(&path, Mode::from_mode(bits)).unwrap();
            assert!(p.inspect(1, &path).unwrap().contains(label));
            assert!(p.apply(1, "644").is_err());
            assert_eq!(path.metadata().unwrap().mode() & 0o7777, bits);
        }
        std::fs::set_permissions(&path, Mode::from_mode(0o644)).unwrap();
        let meta = path.metadata().unwrap();
        assert!(reason(&meta, meta.uid().wrapping_add(1)).contains("not the owner"));
    }
    #[test]
    fn a_swapped_symlink_is_refused_and_leaves_the_victim() {
        let d = TestDir::new("permissions-swap");
        let item = d.file("item", "a");
        std::fs::set_permissions(&item, Mode::from_mode(0o644)).unwrap();
        let victim = d.file("id_rsa", "secret");
        std::fs::set_permissions(&victim, Mode::from_mode(0o640)).unwrap();
        let before = item.symlink_metadata().unwrap();
        let (dev, ino) = (before.dev(), before.ino());
        std::fs::remove_file(&item).unwrap();
        std::os::unix::fs::symlink(&victim, &item).unwrap();
        let refused = chmod_pinned(&item, dev, ino, 0o644, 0o600);
        assert!(refused.is_err(), "a path swapped for a link is refused, got {:?}", refused);
        assert!(item.symlink_metadata().unwrap().file_type().is_symlink(), "the swap is still a link");
        assert_eq!(victim.metadata().unwrap().mode() & 0o777, 0o640, "the swap target keeps its mode");
    }
    #[test]
    fn apply_many_changes_every_file_and_undoes_once() {
        let d = TestDir::new("permissions-many");
        let a = d.file("a.txt", "a");
        let b = d.file("b.txt", "b");
        let c = d.file("c.txt", "c");
        for p in [&a, &b, &c] {
            std::fs::set_permissions(p, Mode::from_mode(0o644)).unwrap();
        }
        let steps = apply_many(&[(a.clone(), "600".to_string()), (b.clone(), "600".to_string()), (c.clone(), "600".to_string())]).expect("three ordinary files");
        assert_eq!(steps.len(), 3);
        for p in [&a, &b, &c] {
            assert_eq!(p.metadata().unwrap().mode() & 0o777, 0o600);
        }
        let mut journal = crate::backend::undo::Journal::new();
        journal.push(crate::backend::undo::Entry { op: "permissions".to_string(), steps });
        assert_eq!(journal.undo().expect("one undo restores all three"), "permissions");
        for p in [&a, &b, &c] {
            assert_eq!(p.metadata().unwrap().mode() & 0o777, 0o644);
        }
    }
    #[test]
    fn a_mid_batch_failure_rolls_back_and_says_nothing_changed() {
        let d = TestDir::new("permissions-rollback");
        let a = d.file("a.txt", "a");
        let b = d.file("b.txt", "b");
        for p in [&a, &b] {
            std::fs::set_permissions(p, Mode::from_mode(0o644)).unwrap();
        }
        test_fail_at(Some(1));
        let result = apply_many(&[(a.clone(), "600".to_string()), (b.clone(), "600".to_string())]);
        test_fail_at(None);
        let err = result.unwrap_err();
        assert!(err.msg.contains("No change was applied"), "unexpected message: {}", err.msg);
        assert!(err.applied.is_empty(), "a batch that rolled back whole journals nothing");
        assert_eq!(a.metadata().unwrap().mode() & 0o777, 0o644, "the first change was rolled back");
        assert_eq!(b.metadata().unwrap().mode() & 0o777, 0o644, "the failed item was never changed");
    }
    #[test]
    fn a_failed_rollback_journals_what_stayed_applied() {
        let d = TestDir::new("permissions-stuck");
        let a = d.file("a.txt", "a");
        let b = d.file("b.txt", "b");
        for p in [&a, &b] {
            std::fs::set_permissions(p, Mode::from_mode(0o644)).unwrap();
        }
        test_fail_at(Some(1));
        test_fail_restore(true);
        let result = apply_many(&[(a.clone(), "600".to_string()), (b.clone(), "600".to_string())]);
        test_fail_at(None);
        test_fail_restore(false);
        let err = result.unwrap_err();
        assert!(err.msg.contains("1 of 2 items were changed"), "unexpected message: {}", err.msg);
        assert_eq!(err.applied.len(), 1, "the step that would not go back stays journalled");
        assert_eq!(a.metadata().unwrap().mode() & 0o777, 0o600, "the stuck change is still applied");
        let mut journal = crate::backend::undo::Journal::new();
        journal.push(crate::backend::undo::Entry { op: "permissions".to_string(), steps: err.applied });
        assert_eq!(journal.undo().expect("one undo restores what stayed applied"), "permissions");
        assert_eq!(a.metadata().unwrap().mode() & 0o777, 0o644);
    }
    #[test]
    fn undo_leaves_a_file_put_at_the_name_since_in_place() {
        let d = TestDir::new("permissions-replaced");
        let a = d.file("a.txt", "old");
        std::fs::set_permissions(&a, Mode::from_mode(0o644)).unwrap();
        let steps = apply_many(&[(a.clone(), "600".to_string())]).expect("one ordinary file");
        assert_eq!(a.metadata().unwrap().mode() & 0o777, 0o600);
        std::fs::remove_file(&a).unwrap();
        std::fs::write(&a, "new secret").unwrap();
        std::fs::set_permissions(&a, Mode::from_mode(0o600)).unwrap();
        let mut journal = crate::backend::undo::Journal::new();
        journal.push(crate::backend::undo::Entry { op: "permissions".to_string(), steps });
        let err = journal.undo().expect_err("a replaced file keeps nothing to restore to");
        assert!(err.msg.contains("left in place"), "{}", err.msg);
        use std::os::unix::fs::MetadataExt;
        assert_eq!(std::fs::metadata(&a).unwrap().mode() & 0o777, 0o600,
            "undo widened a file it never changed");
    }
    #[test]
    fn undo_restores_the_rest_when_one_of_several_was_replaced() {
        let d = TestDir::new("permissions-skips-one");
        let a = d.file("a.txt", "a");
        let b = d.file("b.txt", "b");
        for p in [&a, &b] {
            std::fs::set_permissions(p, Mode::from_mode(0o644)).unwrap();
        }
        let steps = apply_many(&[(a.clone(), "600".to_string()), (b.clone(), "600".to_string())])
            .expect("two ordinary files");
        std::fs::remove_file(&a).unwrap();
        std::fs::write(&a, "replacement").unwrap();
        std::fs::set_permissions(&a, Mode::from_mode(0o600)).unwrap();
        let mut journal = crate::backend::undo::Journal::new();
        journal.push(crate::backend::undo::Entry { op: "permissions".to_string(), steps });
        let err = journal.undo().expect_err("one replaced path is skipped with a note");
        assert!(err.msg.contains("left in place"), "{}", err.msg);
        use std::os::unix::fs::MetadataExt;
        assert_eq!(std::fs::metadata(&a).unwrap().mode() & 0o777, 0o600, "the replacement keeps its mode");
        assert_eq!(b.metadata().unwrap().mode() & 0o777, 0o644, "the untouched file still restores");
    }
}
