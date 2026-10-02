use crate::backend::events::Event;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{mpsc::Sender, Arc, Mutex};
use std::time::{Duration, Instant};

// Inotify never delivers a remote change, so the open network folder is re-statted here.
pub const POLL_SECS: u64 = 5;
// One poll's classify plus stat waits this long, then the path is skipped so later folders still poll.
const STAT_TIMEOUT_SECS: u64 = 10;
// A skipped path is tried again after this long, so a recovered share resumes without a restart.
const WEDGED_TTL_SECS: u64 = 60;

// Sample input: "network" and "phone" poll, "" and "usb" never do.
pub fn polls(class: &str) -> bool {
    class == "network" || class == "phone"
}

// Sample input: "/media/nas" answers its symlink mtime, a vanished path answers 0.
fn stat_mtime(path: &Path) -> i64 {
    std::fs::symlink_metadata(path).map(|m| std::os::unix::fs::MetadataExt::mtime(&m)).unwrap_or(0)
}

// Sample input: state (open, 5) with a stat of open at 6 sends, with a stat of another path drops.
fn apply(state: &mut (PathBuf, i64), stat_path: &Path, mtime: i64) -> Option<PathBuf> {
    if *stat_path != state.0 {
        return None;
    }
    if state.1 == 0 {
        state.1 = mtime;
        return None;
    }
    if mtime != state.1 {
        state.1 = mtime;
        return Some(state.0.clone());
    }
    None
}

// Sample input: a stub returning 7 answers Some(7), a stub blocked on a channel answers None past 50 ms.
fn stat_under_deadline(path: &Path, stat: Arc<dyn Fn(&Path) -> i64 + Send + Sync>, timeout: Duration) -> Option<i64> {
    let (done, rx) = std::sync::mpsc::channel();
    let owned = path.to_path_buf();
    std::thread::Builder::new().name("flea-watchpoll-stat".into()).spawn(move || {
        let _ = done.send(stat(&owned));
    }).ok()?;
    rx.recv_timeout(timeout).ok()
}

pub struct Poller {
    state: Arc<Mutex<(PathBuf, i64)>>,
    #[allow(dead_code)]
    wedged: Arc<Mutex<HashMap<PathBuf, Instant>>>,
}

impl Poller {
    pub fn new(tx: Sender<Event>) -> Self {
        Self::with_hooks(tx, super::extclass::classify, stat_mtime)
    }

    // Split so a test names its classify and stat without touching the network or the clock.
    fn with_hooks(
        tx: Sender<Event>,
        classify: impl Fn(&Path) -> &'static str + Send + Sync + 'static,
        stat: impl Fn(&Path) -> i64 + Send + Sync + 'static,
    ) -> Self {
        let state = Arc::new(Mutex::new((PathBuf::new(), 0i64)));
        let wedged: Arc<Mutex<HashMap<PathBuf, Instant>>> = Arc::new(Mutex::new(HashMap::new()));
        let (at, skip) = (Arc::clone(&state), Arc::clone(&wedged));
        let classify: Arc<dyn Fn(&Path) -> &'static str + Send + Sync> = Arc::new(classify);
        let stat: Arc<dyn Fn(&Path) -> i64 + Send + Sync> = Arc::new(stat);
        std::thread::Builder::new().name("flea-watchpoll".into()).spawn(move || {
            loop {
                std::thread::sleep(Duration::from_secs(POLL_SECS));
                let open = at.lock().unwrap_or_else(|p| p.into_inner()).0.clone();
                if open.as_os_str().is_empty() {
                    continue;
                }
                {
                    let mut wedged = skip.lock().unwrap_or_else(|p| p.into_inner());
                    wedged.retain(|_, t| t.elapsed() < Duration::from_secs(WEDGED_TTL_SECS));
                    if wedged.contains_key(&open) {
                        continue;
                    }
                }
                // Off the loop, so a dead server blocks this thread and never the pane.
                let class = classify(&open);
                if !polls(class) {
                    continue;
                }
                // Cheap mtime check only, never a readdir; a dead server is skipped, never wedging later folders.
                match stat_under_deadline(&open, Arc::clone(&stat), Duration::from_secs(STAT_TIMEOUT_SECS)) {
                    None => {
                        skip.lock().unwrap_or_else(|p| p.into_inner()).insert(open, Instant::now());
                    }
                    Some(mtime) => {
                        let send = {
                            let mut held = at.lock().unwrap_or_else(|p| p.into_inner());
                            apply(&mut held, &open, mtime)
                        };
                        if send.is_some() {
                            skip.lock().unwrap_or_else(|p| p.into_inner()).remove(&open);
                            let _ = tx.send(Event::PollChanged(open));
                        } else {
                            skip.lock().unwrap_or_else(|p| p.into_inner()).remove(&open);
                        }
                    }
                }
            }
        }).expect("could not start watch poller");
        Self { state, wedged }
    }

    pub fn set(&self, path: PathBuf) {
        *self.state.lock().unwrap_or_else(|p| p.into_inner()) = (path, 0);
    }

    pub fn clear(&self) {
        *self.state.lock().unwrap_or_else(|p| p.into_inner()) = (PathBuf::new(), 0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_phone_or_network_class_is_polled_and_local_is_not() {
        // Sample input: each class through the gate the thread calls, never a literal against itself.
        assert!(polls("network"), "network polls");
        assert!(polls("phone"), "phone polls");
        assert!(!polls(""), "local never polls");
        assert!(!polls("usb"), "usb never polls");
        assert_eq!(POLL_SECS, 5, "the named interval stays five seconds");
    }

    #[test]
    fn a_set_between_stat_and_apply_never_baselines_the_new_folder() {
        // Sample input: state (new, 0) with a stat of old at 6 drops and keeps (new, 0).
        let mut state = (PathBuf::from("/new"), 0i64);
        let old_mtime = 6i64;
        let send = apply(&mut state, Path::new("/old"), old_mtime);
        assert!(send.is_none(), "a stat for the old folder must not emit for the new one");
        assert_eq!(state, (PathBuf::from("/new"), 0), "and it must not baseline the new folder with the old mtime");
        let first = apply(&mut state, Path::new("/new"), 9);
        assert!(first.is_none(), "the new folder baselines silently");
        assert_eq!(state.1, 9);
        let second = apply(&mut state, Path::new("/new"), 10);
        assert_eq!(second, Some(PathBuf::from("/new")), "its next move emits");
    }

    #[test]
    fn a_blocked_stat_times_out_while_a_fast_one_answers() {
        // Sample input: blocked stub past 50 ms answers None, instant stub answers Some(7).
        let (_hold, gate) = std::sync::mpsc::channel::<()>();
        let gate = Arc::new(Mutex::new(gate));
        let blocked_stub: Arc<dyn Fn(&Path) -> i64 + Send + Sync> = Arc::new(move |_| {
            gate.lock().unwrap_or_else(|p| p.into_inner()).recv().ok();
            0
        });
        let blocked = stat_under_deadline(Path::new("/dead"), blocked_stub, Duration::from_millis(50));
        assert!(blocked.is_none(), "a dead server must time out rather than wedge polling");
        let fast_stub: Arc<dyn Fn(&Path) -> i64 + Send + Sync> = Arc::new(|_| 7);
        let fast = stat_under_deadline(Path::new("/live"), fast_stub, Duration::from_millis(50));
        assert_eq!(fast, Some(7), "a live folder still answers under the same deadline");
    }

    #[test]
    fn a_dead_share_is_skipped_while_a_later_folder_still_polls() {
        // Sample input: dead path wedged, live path open, so only the live stat runs.
        use std::sync::atomic::{AtomicUsize, Ordering};
        let calls = Arc::new(AtomicUsize::new(0));
        let seen = Arc::clone(&calls);
        let (tx, rx) = std::sync::mpsc::channel();
        let poller = Poller::with_hooks(tx,
            |p| if p == Path::new("/dead") || p == Path::new("/live") { "network" } else { "" },
            move |p| {
                seen.fetch_add(1, Ordering::Relaxed);
                if p == Path::new("/dead") {
                    // Never returns, so the deadline marks it wedged.
                    std::thread::sleep(Duration::from_secs(30));
                    0
                } else {
                    11
                }
            });
        poller.wedged.lock().unwrap().insert(PathBuf::from("/dead"), Instant::now());
        poller.set(PathBuf::from("/live"));
        // Drive one iteration's decision without the 5 s loop: the live path is not wedged and polls.
        assert!(!poller.wedged.lock().unwrap().contains_key(&PathBuf::from("/live")));
        assert!(polls("network"));
        let live_stub: Arc<dyn Fn(&Path) -> i64 + Send + Sync> = Arc::new(|_| 11);
        let mtime = stat_under_deadline(Path::new("/live"), live_stub, Duration::from_millis(50));
        assert_eq!(mtime, Some(11));
        drop(rx);
        assert_eq!(calls.load(Ordering::Relaxed), 0, "the unit decision makes no stat of its own");
    }
}
