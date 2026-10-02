// Paste as links: one exclusive link per source, journaled for undo.
use crate::error::{from_io, FleaError};
use std::path::{Component, Path, PathBuf};

// The Paste as leaf kind, journaled so redo recreates it.
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
    // Canonicalize the dest folder: the kernel resolves `..` from the real folder.
    let canonical_src = source.canonicalize()
        .map_err(|e| from_io("link", &source.to_string_lossy(), &e))?;
    let target = match dest_dir_of(dest_file).canonicalize() {
        Ok(canonical_dest) => relative_target(&canonical_dest, &canonical_src),
        Err(_) => canonical_src.clone(),
    };
    std::os::unix::fs::symlink(&target, dest_file)
        .map_err(|e| from_io("link", &dest_file.to_string_lossy(), &e))
}

pub fn create_absolute(source: &Path, dest_file: &Path) -> Result<(), FleaError> {
    std::os::unix::fs::symlink(source, dest_file)
        .map_err(|e| from_io("link", &dest_file.to_string_lossy(), &e))
}

// Refused before the syscall so the sentence names the refusal, not the errno.
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
            let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
            let from = super::mountinfo::mount_type_in(source, &body).unwrap_or_else(|| "unknown".to_string());
            let to = super::mountinfo::mount_type_in(dest_dir_of(dest_file), &body).unwrap_or_else(|| "unknown".to_string());
            FleaError {
                where_: "link".to_string(),
                path: dest_file.to_string_lossy().to_string(),
                msg: format!("cannot hard link across filesystems ({} to {})", from, to),
            }
        } else {
            from_io("link", &dest_file.to_string_lossy(), &e)
        }
    })
}

// EXDEV without a libc dependency: the one errno this module names.
fn libc_exdev() -> i32 {
    18
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
    fn a_relative_link_into_a_symlinked_folder_resolves() {
        let d = TestDir::new("link-symdir");
        d.dir("docs");
        let src = d.file("docs/a.txt", "a");
        d.dir("mnt");
        let real = d.dir("mnt/pics");
        let alias = d.join("pics");
        std::os::unix::fs::symlink(&real, &alias).unwrap();
        let at = dest_path(&alias, &src).unwrap();
        create_relative(&src, &at).expect("a fresh name links");
        assert_eq!(std::fs::read_to_string(&at).unwrap(), "a",
            "reported ok but the link dangles: {:?}", std::fs::read_link(&at));
    }

    #[test]
    fn a_relative_link_to_a_missing_source_is_refused() {
        let d = TestDir::new("link-rel-missing");
        let gone = d.join("gone.txt");
        let dest = d.dir("dest");
        let at = dest_path(&dest, &gone).unwrap();
        assert!(create_relative(&gone, &at).is_err());
        assert!(std::fs::symlink_metadata(&at).is_err(), "a link to nothing was never made");
    }
}
