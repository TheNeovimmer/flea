// One reviewed object stays open until its dialog closes; mode writes never walk a directory.
use crate::json::{escape, field_str, field_usize};
use crate::oflags::O_NOFOLLOW;
#[cfg(test)]
use std::fs::Permissions as Mode;
use std::fs::{File, Metadata, OpenOptions};
use std::os::unix::fs::PermissionsExt;
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

// Sample input: items [("/a.txt", "600"), ("/b dir/c.txt", "644")]. Every
// path is an absolute file or folder, never a link; one Entry holds every
// change so one undo restores them all. Octal, Owner, Group and the change
// preview drop out for several items: the grid and Apply are the whole card.
// A mixed box the operator never touched keeps each file's own bit, because
// the client sends that file's own target mode rather than one mode for all.
pub fn apply_many(items: &[(PathBuf, String)]) -> Result<Vec<crate::backend::undo::Step>, String> {
    if items.is_empty() {
        return Err("Permissions needs at least one selected item.".into());
    }
    let uid = unsafe { geteuid() };
    let mut checked: Vec<(PathBuf, u32)> = Vec::with_capacity(items.len());
    for (path, text) in items {
        let requested = mode(text).map_err(|e| e)?;
        if !path.is_absolute() {
            return Err("Permissions requires an absolute path and request identity.".into());
        }
        let before = path.symlink_metadata()
            .map_err(|e| format!("Could not inspect permissions: {}.", crate::error::io_message(&e)))?;
        if !(before.is_file() || before.is_dir()) {
            return Err("Permissions takes one file or folder, not a link.".into());
        }
        if before.mode() & SPECIAL_BITS != 0 {
            return Err("Special permissions cannot be edited.".into());
        }
        if !reason(&before, uid).is_empty() {
            return Err(reason(&before, uid));
        }
        checked.push((path.clone(), requested));
    }
    let mut steps = Vec::with_capacity(checked.len());
    for (path, requested) in checked {
        let before = path.symlink_metadata()
            .map_err(|e| format!("Could not inspect permissions: {}.", crate::error::io_message(&e)))?;
        let before_bits = before.mode() & 0o777;
        apply_mode_path(&path, requested)
            .map_err(|e| format!("Could not change mode: {}. No change was applied.", e))?;
        steps.push(crate::backend::undo::Step::Mode { path, before: before_bits, after: requested });
    }
    Ok(steps)
}

// One fchmod by name, after the caller proved the path is a file or folder;
// symlinks are refused rather than followed.
fn apply_mode_path(path: &Path, requested: u32) -> Result<(), String> {
    let before = path.symlink_metadata().map_err(|e| crate::error::io_message(&e))?;
    if before.file_type().is_symlink() {
        return Err("Permissions takes one file or folder, not a link.".into());
    }
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(requested))
        .map_err(|e| crate::error::io_message(&e))?;
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
}
