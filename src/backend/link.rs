// Paste as links: one link per source inside the destination, created
// exclusively and journaled so undo removes them.
use crate::error::{from_io, FleaError};
use std::path::{Component, Path, PathBuf};

// The three Paste as leaves; the journal records which one made a link so
// redo recreates the same kind rather than guessing from the bytes.
#[derive(Clone, Debug, PartialEq)]
pub enum LinkKind {
    Relative,
    Absolute,
    Hard,
}

// Sample input: dest "/home/gm/Pictures", source "/home/gm/a.png".
pub fn dest_path(dest: &Path, source: &Path) -> Option<PathBuf> {
    source.file_name().map(|leaf| dest.join(leaf))
}

// Sample input: dest "/a/b", source "/a/c/f.png" -> "../c/f.png".
pub fn relative_target(dest_dir: &Path, source: &Path) -> PathBuf {
    let dest_parts: Vec<Component> = dest_dir.components().collect();
    let src_parts: Vec<Component> = source.components().collect();
    let mut common = 0;
    while common < dest_parts.len() && common < src_parts.len() && dest_parts[common] == src_parts[common] {
        common += 1;
    }
    // Different roots cannot be relativized; the absolute source still links.
    if common == 0 {
        return source.to_path_buf();
    }
    let mut out = PathBuf::new();
    for _ in common..dest_parts.len() {
        out.push("..");
    }
    for part in src_parts.iter().skip(common) {
        out.push(part.as_os_str());
    }
    if out.as_os_str().is_empty() {
        PathBuf::from(".")
    } else {
        out
    }
}

fn dest_dir_of(file: &Path) -> &Path {
    file.parent().unwrap_or(Path::new("/"))
}

pub fn create_relative(source: &Path, dest_file: &Path) -> Result<(), FleaError> {
    let target = relative_target(dest_dir_of(dest_file), source);
    let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    let link = target.clone();
    let at = dest_file.to_path_buf();
    let at_for_key = at.clone();
    let dest_name = dest_file.to_string_lossy().to_string();
    super::iomount::call(&at_for_key, &body, "link", move || {
        std::os::unix::fs::symlink(&link, &at).map_err(|e| from_io("link", &dest_name, &e))
    })
    .unwrap_or_else(Err)
}

pub fn create_absolute(source: &Path, dest_file: &Path) -> Result<(), FleaError> {
    let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    let from = source.to_path_buf();
    let at = dest_file.to_path_buf();
    let at_for_key = at.clone();
    let dest_name = dest_file.to_string_lossy().to_string();
    super::iomount::call(&at_for_key, &body, "link", move || {
        std::os::unix::fs::symlink(&from, &at).map_err(|e| from_io("link", &dest_name, &e))
    })
    .unwrap_or_else(Err)
}

// A hard link to a directory is refused before the syscall, which would fail
// anyway: the sentence names the refusal rather than the OS errno.
pub fn create_hard(source: &Path, dest_file: &Path) -> Result<(), FleaError> {
    let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    let from = source.to_path_buf();
    let from_for_key = from.clone();
    let is_dir = super::iomount::call(&from_for_key, &body, "link", move || {
        from.symlink_metadata().map(|m| m.is_dir()).unwrap_or(false)
    })
    .unwrap_or(false);
    if is_dir {
        return Err(FleaError {
            where_: "link".to_string(),
            path: dest_file.to_string_lossy().to_string(),
            msg: "a hard link to a directory is refused".to_string(),
        });
    }
    let at = dest_file.to_path_buf();
    let at_for_key = at.clone();
    let from_link = source.to_path_buf();
    let dest_name = dest_file.to_string_lossy().to_string();
    let from_name = source.to_path_buf();
    super::iomount::call(&at_for_key, &body, "link", move || {
        std::fs::hard_link(&from_link, &at).map_err(|e| {
            if e.raw_os_error() == Some(libc_exdev()) {
                FleaError {
                    where_: "link".to_string(),
                    path: dest_name.clone(),
                    msg: format!("cannot hard link across filesystems ({} to {})", fs_name(&from_name), fs_name(dest_dir_of(&at))),
                }
            } else {
                from_io("link", &dest_name, &e)
            }
        })
    })
    .unwrap_or_else(Err)
}

// EXDEV without a libc dependency: the one errno this module names.
fn libc_exdev() -> i32 {
    18
}

// The filesystem type of the deepest mount owning path, from mountinfo's own
// field 9; "unknown" when the table cannot be read, never an error.
fn fs_name(path: &Path) -> String {
    let text = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    let mut best: Option<(usize, String)> = None;
    for line in text.lines() {
        let fields: Vec<&str> = line.split(' ').collect();
        if fields.len() < 10 {
            continue;
        }
        let mount_point = unescape(fields[4]);
        let fs_type = fields[8].to_string();
        if path.starts_with(&mount_point)
            && best.as_ref().map(|(len, _)| mount_point.len() > *len).unwrap_or(true)
        {
            best = Some((mount_point.len(), fs_type));
        }
    }
    best.map(|(_, fs)| fs).unwrap_or_else(|| "unknown".to_string())
}

// Sample input: "/run/user/1000/gvfs/smb-share\\x3aserver=1\\x2cshare=d".
fn unescape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut bytes = text.as_bytes().iter().peekable();
    while let Some(&b) = bytes.next() {
        if b == b'\\' {
            let mut code = 0u32;
            let mut ok = true;
            for _ in 0..3 {
                match bytes.next() {
                    Some(d) if d.is_ascii_digit() => code = code * 8 + u32::from(d - b'0'),
                    _ => {
                        ok = false;
                        break;
                    }
                }
            }
            if ok {
                out.push(char::from(code as u8));
                continue;
            }
            out.push('\\');
        } else {
            out.push(b as char);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;

    #[test]
    fn relative_link_points_inside_dest() {
        let d = TestDir::new("link-relative");
        d.dir("src");
        let src = d.file("src/a.txt", "a");
        let dest = d.dir("dest");
        let at = dest_path(&dest, &src).expect("a name is always joined");
        assert_eq!(at, dest.join("a.txt"));
        create_relative(&src, &at).expect("a fresh name links");
        assert_eq!(std::fs::read_to_string(&at).unwrap(), "a");
        assert_eq!(std::fs::read_link(&at).unwrap(), relative_target(&dest, &src));
    }

    #[test]
    fn an_existing_name_is_refused_and_kept() {
        let d = TestDir::new("link-existing");
        d.dir("src");
        let src = d.file("src/a.txt", "a");
        let dest = d.dir("dest");
        let at = dest_path(&dest, &src).unwrap();
        std::fs::write(&at, "someone else").unwrap();
        assert!(create_relative(&src, &at).is_err());
        assert_eq!(std::fs::read_to_string(&at).unwrap(), "someone else");
    }

    #[test]
    fn a_hard_link_to_a_directory_is_refused() {
        let d = TestDir::new("link-hard-dir");
        let src = d.dir("src");
        let dest = d.dir("dest");
        let at = dest_path(&dest, &src).unwrap();
        assert!(create_hard(&src, &at).is_err());
        assert!(!at.exists() && std::fs::symlink_metadata(&at).is_err());
    }

    #[test]
    fn created_links_undo_by_removal() {
        let d = TestDir::new("link-undo");
        d.dir("src");
        let src = d.file("src/a.txt", "a");
        let dest = d.dir("dest");
        let at = dest_path(&dest, &src).unwrap();
        create_absolute(&src, &at).expect("a fresh name links");
        std::fs::remove_file(&at).expect("undo removes what the operation created");
        assert!(std::fs::symlink_metadata(&at).is_err());
    }
}
