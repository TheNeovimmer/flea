use crate::backend::listing::Listing;
use crate::error::{from_io, FleaError};
use std::ffi::{c_char, c_int, CString};
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::time::Instant;

// Phase 1 never stats: d_type is free, see AGENTS.md "Two-phase listing".
// hidden:false is the shell's own dotfile convention, matched here rather than left to the client.
pub fn scan(path: &str, hidden: bool) -> Result<(Listing, f64), FleaError> {
    // The gvfs check first, so a local listing never reads the prefetch environment or the gio name.
    if !super::gvfslist::is_gvfs(std::path::Path::new(path)) {
        return scan_with(path, hidden, None, "gio");
    }
    scan_with(path, hidden, crate::gvfsprefetch::env_prefetch(), &super::gvfslist::gio_bin())
}

// Split so a test can name the prefetch and the gio binary without touching this process's environment.
pub fn scan_with(
    path: &str,
    hidden: bool,
    prefetch: Option<crate::gvfsprefetch::Prefetch>,
    gio: &str,
) -> Result<(Listing, f64), FleaError> {
    // One prefix check: local and USB paths take exactly today's code past it.
    if super::gvfslist::is_gvfs(std::path::Path::new(path)) {
        // The launcher's head start on this exact path; anything else takes today's gio path.
        if let Some(found) = prefetch.as_ref().and_then(|p| crate::gvfsprefetch::adopt_matching(path, hidden, p)) {
            return Ok(found);
        }
        // Any gio failure falls back to readdir unchanged and says nothing to the user.
        if let Ok(found) = super::gvfslist::list_via_gio(path, hidden, gio, super::gvfslist::GIO_TIMEOUT) {
            return Ok(found);
        }
    }
    let t = Instant::now();
    let mut l = Listing::new();
    // corner: a non-UTF8 name goes lossy here and then cannot be stat'd, see AGENTS.md.
    scan_raw(path, hidden, &mut l)?;
    Ok((l, t.elapsed().as_secs_f64() * 1000.0))
}

// d_type values from dirent.h: unknown 0, dir 4, link 10; only these decide the listing.
const DT_UNKNOWN: u8 = 0;
const DT_DIR: u8 = 4;
const DT_LNK: u8 = 10;

// Sample dirent: d_type 4 with name "sub", d_type 0 with name "xfs-file"; unknown stays a dir.
fn dir_from_dtype(dtype: u8) -> (bool, bool) {
    match dtype {
        DT_DIR => (true, false),
        DT_LNK => (false, true),
        DT_UNKNOWN => (true, false),
        _ => (false, false),
    }
}

// Sample input: [Ok(("a", 8)), Err(EIO), Ok(("b", 8))] answers Err, never a short Ok.
#[cfg(test)]
fn collect_strict(entries: Vec<Result<(String, u8), std::io::Error>>) -> Result<Vec<(String, u8)>, std::io::Error> {
    let mut out = Vec::with_capacity(entries.len());
    for entry in entries {
        out.push(entry?);
    }
    Ok(out)
}

// dirent as the kernel lays it: ino, off, reclen, type, then the NUL-terminated name.
#[repr(C)]
struct Dirent {
    ino: u64,
    off: i64,
    reclen: u16,
    dtype: u8,
    name: [c_char; 256],
}

extern "C" {
    fn opendir(path: *const c_char) -> *mut std::ffi::c_void;
    fn readdir(dir: *mut std::ffi::c_void) -> *mut Dirent;
    fn closedir(dir: *mut std::ffi::c_void) -> c_int;
    fn __errno_location() -> *mut c_int;
}

// Raw getdents without the lstat fallback, so xfs ftype=0 and FUSE cost no stat per entry.
fn scan_raw(path: &str, hidden: bool, l: &mut Listing) -> Result<(), FleaError> {
    let c = match CString::new(path) {
        Ok(c) => c,
        Err(_) => return Err(from_io("scan", path, &std::io::Error::new(std::io::ErrorKind::InvalidInput, "invalid input"))),
    };
    let dir = unsafe { opendir(c.as_ptr()) };
    if dir.is_null() {
        return Err(from_io("scan", path, &std::io::Error::last_os_error()));
    }
    loop {
        unsafe { *__errno_location() = 0 };
        let entry = unsafe { readdir(dir) };
        if entry.is_null() {
            let code = unsafe { *__errno_location() };
            unsafe { closedir(dir) };
            if code != 0 {
                return Err(from_io("scan", path, &std::io::Error::from_raw_os_error(code)));
            }
            return Ok(());
        }
        let dtype = unsafe { (*entry).dtype };
        let bytes: Vec<u8> = unsafe { (*entry).name.iter().take_while(|&&b| b != 0).map(|&b| b as u8).collect() };
        let name = String::from_utf8_lossy(&bytes);
        // readdir returns . and .. like any other entry, while ReadDir filters them.
        if name == "." || name == ".." {
            continue;
        }
        if !hidden && name.starts_with('.') {
            continue;
        }
        // corner: unknown never becomes a file, so a folder survives xfs ftype=0; the window corrects files.
        let (is_dir, is_link) = dir_from_dtype(dtype);
        let index = l.len();
        l.push(&name, is_dir);
        l.spans[index].is_symlink = is_link;
    }
}

// The st_mode of a path whose listing failed. The stat outlives the denial: /root answers mode
// 0o40750 to anyone while opendir on it is refused, which is what lets a denied pane draw the
// directory's own permission string instead of nothing. Zero when the stat failed too, and a real
// st_mode always carries its file-type bits, so zero can only mean "I could not look".
pub fn mode_of(path: &str) -> u32 {
    match fs::metadata(path) {
        Ok(m) => m.mode(),
        Err(_) => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn reads_files_and_marks_directories() {
        let d = TestDir::new("scan-basic");
        d.file("a.txt", "");
        d.dir("sub");

        let (l, _) = scan(d.path().to_str().unwrap(), false).unwrap();
        assert_eq!(l.len(), 2);

        let mut seen_file = false;
        let mut seen_dir = false;
        for i in 0..l.len() {
            if l.name(i) == "a.txt" && !l.is_dir(i) {
                seen_file = true;
            }
            if l.name(i) == "sub" && l.is_dir(i) {
                seen_dir = true;
            }
        }
        assert!(seen_file, "expected a.txt as a file");
        assert!(seen_dir, "expected sub as a directory");
    }

    #[test]
    fn an_empty_directory_yields_an_empty_listing() {
        let d = TestDir::new("scan-empty");
        let empty = d.dir("empty");
        let (l, _) = scan(empty.to_str().unwrap(), false).unwrap();
        assert_eq!(l.len(), 0);
    }

    #[test]
    fn a_missing_directory_is_an_error_naming_the_path() {
        let d = TestDir::new("scan-missing");
        let missing = d.join("missing");
        let path = missing.to_str().unwrap();
        let e = scan(path, false).unwrap_err();
        assert_eq!(e.where_, "scan");
        assert_eq!(e.path, path);
        assert!(!e.msg.is_empty());
    }

    #[test]
    fn a_directory_that_cannot_be_listed_still_answers_its_own_mode() {
        let d = TestDir::new("scan-mode");
        let locked = d.dir("locked");
        // Write and enter, never read: opendir is refused while stat still answers.
        fs::set_permissions(&locked, fs::Permissions::from_mode(0o300)).unwrap();

        let listed = scan(locked.to_str().unwrap(), false);
        let mode = mode_of(locked.to_str().unwrap());
        fs::set_permissions(&locked, fs::Permissions::from_mode(0o700)).unwrap();

        assert!(listed.is_err(), "a directory with no read bit cannot be listed");
        assert_eq!(mode & 0o777, 0o300, "the stat answered the permission bits, got {:o}", mode);
        assert_eq!(mode & 0o170000, 0o040000, "and the file-type bits say directory, got {:o}", mode);
    }

    #[test]
    fn a_path_that_cannot_be_stat_at_all_answers_zero() {
        let d = TestDir::new("scan-missing-mode");
        assert_eq!(mode_of(d.join("missing").to_str().unwrap()), 0);
    }

    #[test]
    fn a_local_scan_makes_no_statfs_call() {
        let d = TestDir::new("scan-no-statfs");
        d.file("a.txt", "");
        crate::backend::fsinfo::test_reset_statfs();
        let (l, _) = scan(d.path().to_str().unwrap(), false).unwrap();
        assert_eq!(l.len(), 1);
        assert_eq!(crate::backend::fsinfo::statfs_calls(), 0, "the fsinfo answer never blocks a listing, so scan makes no statfs call");
    }

    #[test]
    fn a_mid_read_error_fails_rather_than_a_short_success() {
        let entries = vec![Ok(("a".to_string(), 8u8)), Err(std::io::Error::from_raw_os_error(5)), Ok(("b".to_string(), 8u8))];
        assert!(collect_strict(entries).is_err(), "EIO mid-readdir must fail, never a short listing as success");
    }

    #[test]
    fn an_unknown_type_stays_a_dir_so_a_folder_is_never_a_file() {
        assert_eq!(dir_from_dtype(DT_UNKNOWN), (true, false), "DT_UNKNOWN defaults to dir");
        assert_eq!(dir_from_dtype(DT_DIR), (true, false));
        assert_eq!(dir_from_dtype(DT_LNK), (false, true));
        assert_eq!(dir_from_dtype(8), (false, false), "a regular d_type stays a file");
    }

    #[test]
    fn a_dotfile_is_skipped_by_default_and_listed_when_hidden_is_true() {
        let d = TestDir::new("scan-hidden");
        let listing = d.dir("listing");
        d.file("listing/.dotfile", "");
        d.dir("listing/.dotdir");
        d.file("listing/plain.txt", "");

        let (visible, _) = scan(listing.to_str().unwrap(), false).unwrap();
        assert_eq!(visible.len(), 1);
        assert_eq!(visible.name(0), "plain.txt");

        let (all, _) = scan(listing.to_str().unwrap(), true).unwrap();
        assert_eq!(all.len(), 3);
        let mut names: Vec<&str> = (0..all.len()).map(|i| all.name(i)).collect();
        names.sort();
        assert_eq!(names, [".dotdir", ".dotfile", "plain.txt"]);
    }
}
