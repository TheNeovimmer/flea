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
    std::os::unix::fs::symlink(&target, dest_file)
        .map_err(|e| link_err(dest_file, &e))
}

pub fn create_absolute(source: &Path, dest_file: &Path) -> Result<(), FleaError> {
    std::os::unix::fs::symlink(source, dest_file)
        .map_err(|e| link_err(dest_file, &e))
}

// A hard link to a directory is refused before the syscall, which would fail
// anyway: the sentence names the refusal rather than the OS errno.
pub fn create_hard(source: &Path, dest_file: &Path) -> Result<(), FleaError> {
    if source.symlink_metadata().map(|m| m.is_dir()).unwrap_or(false) {
        return Err(FleaError {
            where_: "link".to_string(),
            path: dest_file.to_string_lossy().to_string(),
            msg: "a hard link to a directory is refused".to_string(),
        });
    }
    std::fs::hard_link(source, dest_file).map_err(|e| {
        if e.raw_os_error() == Some(libc_exdev()) {
            FleaError {
                where_: "link".to_string(),
                path: dest_file.to_string_lossy().to_string(),
                msg: format!(
                    "cannot hard link across filesystems ({} to {})",
                    fs_name(source),
                    fs_name(dest_dir_of(dest_file))
                ),
            }
        } else {
            link_err(dest_file, &e)
        }
    })
}

// EXDEV without a libc dependency: the one errno this module names.
fn libc_exdev() -> i32 {
    18
}

// EPERM from a link names the missing capability on linkless filesystems and stays a permission error everywhere else.
fn link_err(dest_file: &Path, e: &std::io::Error) -> FleaError {
    const EPERM: i32 = 1;
    if e.raw_os_error() == Some(EPERM) {
        let parent = dest_file.parent().unwrap_or(dest_file);
        let magic = crate::backend::fsinfo::magic_of(parent);
        if let Some(sentence) = no_links_sentence(magic) {
            return FleaError { where_: "link".to_string(), path: dest_file.to_string_lossy().to_string(), msg: sentence.to_string() };
        }
    }
    from_io("link", &dest_file.to_string_lossy(), e)
}

// Sample input: Some(vfat) answers the sentence, Some(ext4) and None answer None.
fn no_links_sentence(magic: Option<i64>) -> Option<&'static str> {
    const VFAT_MAGIC: i64 = 0x4D44;
    const EXFAT_MAGIC: i64 = 0x2011BAB0;
    match magic {
        Some(VFAT_MAGIC) | Some(EXFAT_MAGIC) => Some("this drive cannot hold links"),
        _ => None,
    }
}

// The filesystem type of the deepest mount owning path, or "unknown" when the table cannot be read.
fn fs_name(path: &Path) -> String {
    let text = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    crate::backend::mountinfo::mount_type_in(path, &text).unwrap_or_else(|| "unknown".to_string())
}

// Sample input: "/run/user/1000/gvfs/smb-share:server=1,share=d" is matched by prefix on the decoded mount.
#[cfg(test)]
fn fs_name_in(path: &Path, mountinfo: &str) -> String {
    crate::backend::mountinfo::mount_type_in(path, mountinfo).unwrap_or_else(|| "unknown".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;

    #[test]
    fn fat_link_failures_name_the_missing_capability() {
        // Sample magics: vfat and exfat hold no links, ext4 and unknown do.
        assert_eq!(no_links_sentence(Some(0x4D44)), Some("this drive cannot hold links"));
        assert_eq!(no_links_sentence(Some(0x2011BAB0)), Some("this drive cannot hold links"));
        assert_eq!(no_links_sentence(Some(0xEF53)), None);
        assert_eq!(no_links_sentence(None), None);
    }

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
    fn shared_parser_keeps_optional_fields_and_non_ascii_mountpoints() {
        // Sample mountinfo: one optional field plus a UTF-8 mountpoint escaped as octal bytes.
        let body = "1 0 8:1 / / rw - ext4 /dev/a rw\n\
                    2 1 8:17 / /caf\\303\\251 rw shared:2 - vfat /dev/b rw\n";
        assert_eq!(fs_name_in(Path::new("/café/photo.jpg"), body), "vfat");
        assert_eq!(fs_name_in(Path::new("/elsewhere"), body), "ext4");
        assert_eq!(fs_name_in(Path::new("/nowhere"), "junk\n"), "unknown");
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
