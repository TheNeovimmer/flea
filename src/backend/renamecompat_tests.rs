use super::renamecompat::{needs_fuse_fallback_in, rename_path, test_force_fallback};
use crate::backend::testdir::TestDir;
use std::io;
use std::os::unix::fs::MetadataExt;
use std::path::Path;

const EINVAL: i32 = 22;
const TAKEN: &str = "already exists";

// Sample input: "1 0 0:3 / /tmp/x rw - nfs4 192.168.0.21:/v/x rw", the line a kernel nfs4 mount leaves in mountinfo.
fn mountinfo(root: &Path, fstype: &str) -> String {
    format!("1 0 0:3 / {} rw - {} 192.168.0.21:/v/x rw\n", root.display(), fstype)
}

// One rename as a kernel without the flag answers it, and the inode it left behind, so a copy cannot pass for a rename.
fn renamed_on_einval(from: &Path, to: &Path) -> (Result<(), crate::error::FleaError>, Option<u64>) {
    let inode = from.symlink_metadata().ok().map(|m| m.ino());
    test_force_fallback(true);
    let outcome = rename_path(from, to);
    test_force_fallback(false);
    (outcome, inode)
}

#[test]
fn an_nfs_mount_never_takes_the_copy_fallback() {
    let d = TestDir::new("nfsnocopy");
    let file = d.file("file", "body");
    let folder = d.dir("folder");
    let invalid = io::Error::from_raw_os_error(EINVAL);
    for fstype in ["nfs", "nfs4"] {
        let info = mountinfo(d.path(), fstype);
        assert!(!needs_fuse_fallback_in(&folder, &invalid, &info), "{fstype} folder must not become a network copy");
        assert!(!needs_fuse_fallback_in(&file, &invalid, &info), "{fstype} file must not become a network copy");
    }
    assert!(needs_fuse_fallback_in(&folder, &invalid, &mountinfo(d.path(), "fuse.rclone")), "the copy fallback still claims rclone");
}

#[test]
fn an_einval_folder_rename_is_a_plain_rename() {
    let d = TestDir::new("nfsfolderplain");
    let from = d.dir("source");
    std::fs::write(from.join("inside.txt"), "body").unwrap();
    let to = d.join("renamed");
    let (outcome, inode) = renamed_on_einval(&from, &to);
    outcome.expect("a folder renames through the flagless fallback");
    assert!(from.symlink_metadata().is_err(), "the source name is gone");
    assert_eq!(std::fs::read_to_string(to.join("inside.txt")).unwrap(), "body");
    assert_eq!(Some(to.metadata().unwrap().ino()), inode, "one inode moved, nothing was copied");
}

#[test]
fn an_einval_file_rename_keeps_its_inode() {
    let d = TestDir::new("nfsfileplain");
    let from = d.file("source.txt", "body");
    let to = d.join("renamed.txt");
    let (outcome, inode) = renamed_on_einval(&from, &to);
    outcome.expect("a file renames through the flagless fallback");
    assert!(from.symlink_metadata().is_err(), "the source name is gone");
    assert_eq!(std::fs::read_to_string(&to).unwrap(), "body");
    assert_eq!(Some(to.metadata().unwrap().ino()), inode, "one inode moved, nothing was copied");
}

#[test]
fn an_einval_rename_onto_a_taken_name_refuses_every_kind() {
    let d = TestDir::new("nfstaken");
    let folder = d.dir("folder");
    std::fs::write(folder.join("keep.txt"), "folder body").unwrap();
    let file = d.file("file.txt", "file body");
    // An empty folder is the one a plain rename would replace, so it is the target that proves the check.
    let empty = d.dir("empty");
    let full = d.dir("full");
    std::fs::write(full.join("keep.txt"), "full body").unwrap();
    for (from, to) in [(&folder, &empty), (&folder, &full), (&file, &empty), (&file, &d.file("taken.txt", "taken body"))] {
        let (outcome, _) = renamed_on_einval(from, to);
        let error = outcome.expect_err("a taken name is refused, never replaced");
        assert_eq!(error.msg, TAKEN, "{} onto {}", from.display(), to.display());
        assert!(from.symlink_metadata().is_ok(), "the refused source stays where it was");
    }
    assert!(empty.is_dir() && std::fs::read_dir(&empty).unwrap().next().is_none(), "the empty folder was not replaced");
    assert_eq!(std::fs::read_to_string(full.join("keep.txt")).unwrap(), "full body");
    assert_eq!(std::fs::read_to_string(folder.join("keep.txt")).unwrap(), "folder body");
}
