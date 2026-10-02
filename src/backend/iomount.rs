// Path syscalls leave the loop for mount-keyed workers; see AGENTS.md "The open directory is watched".
use crate::error::FleaError;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};
// One deadline for a single path call, well past a cold listing and under every rail bound.
const CALL_DEADLINE: Duration = Duration::from_secs(5);
// One deadline for a bulk pass, matching gio and mount rather than a single stat.
const BULK_DEADLINE: Duration = Duration::from_secs(15);
// A stuck mount answers at once until this passes, then the next request probes it again.
const STUCK_TTL: Duration = Duration::from_secs(30);
// Sample body: "1 0 8:1 / / rw - ext4 /dev/a rw" then "30 1 0:45 / /hung rw - nfs n:/s rw".
fn stuck_table() -> &'static Mutex<HashMap<PathBuf, Instant>> {
    static STUCK: OnceLock<Mutex<HashMap<PathBuf, Instant>>> = OnceLock::new();
    STUCK.get_or_init(|| Mutex::new(HashMap::new()))
}
// A mount marked stuck inside its transmission time answers at once without a worker.
fn is_stuck(mount: &Path, ttl: Duration) -> bool {
    stuck_table().lock().unwrap_or_else(|poisoned| poisoned.into_inner()).get(mount).is_some_and(|marked| marked.elapsed() < ttl)
}
// A call past its deadline marks its mount, so later requests on it answer at once.
fn mark_stuck(mount: &Path) {
    stuck_table().lock().unwrap_or_else(|poisoned| poisoned.into_inner()).insert(mount.to_path_buf(), Instant::now());
}
// A call that answered clears its mount, so the next request probes it again.
fn clear_stuck(mount: &Path) {
    stuck_table().lock().unwrap_or_else(|poisoned| poisoned.into_inner()).remove(mount);
}
// The mount a path sits under, lexical and never a stat, so a dead server costs no syscall here.
pub fn mount_key(path: &Path, body: &str) -> PathBuf {
    if let Some(root) = super::extclass::gvfs_root(path) {
        return root;
    }
    super::mountinfo::mount_entry_in(path, body).map(|e| e.mount).unwrap_or_else(|| PathBuf::from("/"))
}
// A mount whose syscalls can wedge: gvfs, network fstypes and any FUSE daemon.
pub fn is_remote(path: &Path, body: &str) -> bool {
    if super::extclass::gvfs_class(path).is_some() {
        return true;
    }
    super::mountinfo::mount_entry_in(path, body).is_some_and(|e| {
        super::extclass::fstype_is_network(&e.fstype) || e.fstype == "fuse" || e.fstype.starts_with("fuse.")
    })
}
// One plain sentence naming the mount, sharing defect 23's "not responding" words.
pub fn not_responding(where_: &str, path: &Path, mount: &Path) -> FleaError {
    FleaError {
        where_: where_.to_string(),
        path: path.to_string_lossy().to_string(),
        msg: format!("{} is not responding.", mount.display()),
    }
}
// Stub: runs inline with no bound, so the hung test below blocks and goes red.
pub fn call<T: Send + 'static>(
    path: &Path,
    body: &str,
    where_: &str,
    f: impl FnOnce() -> T + Send + 'static,
) -> Result<T, FleaError> {
    call_with(path, body, where_, CALL_DEADLINE, STUCK_TTL, f)
}
// A remote call runs on a worker with a deadline; a local call runs inline with no hop.
pub fn call_with<T: Send + 'static>(
    path: &Path,
    body: &str,
    where_: &str,
    deadline: Duration,
    ttl: Duration,
    f: impl FnOnce() -> T + Send + 'static,
) -> Result<T, FleaError> {
    let mount = mount_key(path, body);
    if is_stuck(&mount, ttl) {
        return Err(not_responding(where_, path, &mount));
    }
    if !is_remote(path, body) {
        return Ok(f());
    }
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let _ = tx.send(f());
    });
    match rx.recv_timeout(deadline) {
        Ok(value) => {
            clear_stuck(&mount);
            Ok(value)
        }
        Err(_) => {
            mark_stuck(&mount);
            Err(not_responding(where_, path, &mount))
        }
    }
}
// Bulk passes share the single-call sentence and bound, with their own longer deadline.
pub fn call_bulk<T: Send + 'static>(
    path: &Path,
    body: &str,
    where_: &str,
    f: impl FnOnce() -> T + Send + 'static,
) -> Result<T, FleaError> {
    call_with(path, body, where_, BULK_DEADLINE, STUCK_TTL, f)
}
// Tests clear the stuck table, so one hung mount never leaks into the next test.
#[cfg(test)]
pub fn test_reset() {
    stuck_table().lock().unwrap_or_else(|poisoned| poisoned.into_inner()).clear();
}
// One listing's syscalls, computed on a worker with the listing, never on the loop.
pub struct ListOut {
    pub listing: super::listing::Listing,
    pub read_ms: f64,
    pub sort_ms: f64,
    pub sized: Vec<Option<super::dirsize::DirSize>>,
    pub dev: u64,
    pub writable: bool,
    pub first_metas: Vec<super::meta::Meta>,
    pub first_ms: f64,
    pub watch_wd: i32,
}
// A failed listing carries its mode for the denial tile, or zero when no stat ran.
#[derive(Debug)]
pub struct ListErr {
    pub error: FleaError,
    pub mode: u32,
}
// Sample request: {"c":"list","path":"/hung/dir","first":350,"hidden":false} on an nfs mount.
pub fn list_dir(
    path: String,
    hidden: bool,
    first: usize,
    line: String,
    mime: std::sync::Arc<super::mime::Db>,
    fd: std::ffi::c_int,
) -> Result<ListOut, ListErr> {
    let path_buf = std::path::PathBuf::from(&path);
    let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    call(&path_buf, &body, "scan", move || {
        let base = std::path::PathBuf::from(&path);
        let wd = super::watch::Watch::add_raw(fd, &base);
        match super::scan::scan(&path, hidden) {
            Ok((mut l, read_ms)) => {
                super::picker::filter_listing(&mut l, &mime, &line);
                let (pass_ms, sort_ms, sized) = match super::ordering::request(&mut l, &base, &mime, &line) {
                    Ok(timing) => timing,
                    Err(msg) => {
                        let error = FleaError { where_: "sort".to_string(), path: path.clone(), msg: msg.to_string() };
                        return Err(ListErr { error, mode: 0 });
                    }
                };
                let dev = super::fsinfo::dev_of(&base);
                let writable = super::ops::dir_writable(&base);
                let (first_metas, first_ms) = super::meta::stat_range(&base, &l, 0, first);
                Ok(ListOut { listing: l, read_ms: read_ms + pass_ms, sort_ms, sized, dev, writable, first_metas, first_ms, watch_wd: wd })
            }
            Err(e) => {
                let mode = super::scan::mode_of(&path);
                Err(ListErr { error: e, mode })
            }
        }
    })
    .map_err(|timeout| ListErr { error: timeout, mode: 0 })
    .and_then(|inner| inner)
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc::channel;
    // Fast enough to keep the suite moving, slow enough that scheduling noise never flakes it.
    const TEST_DEADLINE: Duration = Duration::from_millis(300);
    // Long enough that a stuck mark outlives the whole test, so the fast path is pinned.
    const TEST_TTL: Duration = Duration::from_secs(60);
    // Outer bound for the thread running call, past one deadline with room for spawn.
    const TEST_ASSERT_BOUND: Duration = Duration::from_secs(2);
    // Sample body: root ext4, a hung nfs mount and a healthy ext4 mount side by side.
    const BODY: &str = "1 0 8:1 / / rw - ext4 /dev/a rw\n30 1 0:45 / /hung rw - nfs n:/s rw\n31 1 8:17 / /healthy rw - ext4 /dev/b rw\n";
    #[test]
    fn a_hung_mount_answers_not_responding_while_a_healthy_mount_still_answers() {
        test_reset();
        let (tx_hung, rx_hung) = channel::<()>();
        let hung_done = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let hung_flag = std::sync::Arc::clone(&hung_done);
        let hung_path = PathBuf::from("/hung/dir");
        let hung_body = BODY.to_string();
        let (tx_res, rx_res) = channel();
        std::thread::spawn(move || {
            let out = call_with(
                &hung_path,
                &hung_body,
                "scan",
                TEST_DEADLINE,
                TEST_TTL,
                move || {
                    let _ = rx_hung.recv();
                    hung_flag.store(true, std::sync::atomic::Ordering::SeqCst);
                    42
                },
            );
            let _ = tx_res.send(out);
        });
        let hung = rx_res.recv_timeout(TEST_ASSERT_BOUND).expect("a hung mount must answer within its bound");
        let err = hung.expect_err("a hung mount answers with an error, never a value");
        assert!(err.msg.contains("not responding"), "the sentence names the cause: {}", err.msg);
        assert_eq!(err.where_, "scan");
        let healthy = call_with(Path::new("/healthy/dir"), BODY, "scan", TEST_DEADLINE, TEST_TTL, || 7);
        assert_eq!(healthy.unwrap(), 7, "a stuck mount never blocks its neighbour");
        drop(tx_hung);
        test_reset();
    }
}
