// Owner-exit regressions use the watch fake and real children, with no compositor empty event.
use super::*;
use std::sync::mpsc::{channel, Receiver};

const TOKEN: &str = "038a038a038a038a038a038a038a038a";
const CHILD_TEST: &str = "clip::watch::tests::end::stand_in_owner";
const OWNER_WATCHDOG: Duration = Duration::from_secs(15);
const SIGKILL: i32 = 9;
const INITIAL_OFFER: u32 = 20;
const SENTINEL_OFFER: u32 = INITIAL_OFFER + 2;
const FOREIGN_OFFER: u32 = INITIAL_OFFER + 1;
const LIVE_OWNER_OFFER: u32 = SENTINEL_OFFER + 1;
const WARMUP_OFFER: u32 = INITIAL_OFFER - 1;
const NEXT_OWNER_OFFER: u32 = INITIAL_OFFER + 1;
const SELECTION_COUNT: u32 = 100;
const FLEA_RECEIVES: usize = 2;
const ONE_RECEIVE: usize = 1;
// PF_EXITING marks a task that started do_exit, before join wakes.
const PF_EXITING: u32 = 0x00000004;
// State and flags field indices after the last `)` in a task stat line.
const STAT_STATE_INDEX: usize = 0;
const STAT_FLAGS_INDEX: usize = 6;
// A stopped waiter lingers this long before it returns, so a waiter left unjoined is still running at the check.
const WAITER_STOP_HOLD_MS: u64 = 200;

struct Child(std::process::Child);

impl Drop for Child {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

// Re-exec isolates fd and thread counts from concurrently running clipboard tests.
fn isolated(name: &str) -> bool {
    if std::env::var_os("FLEA_TEST_CLIP_END_CASE").as_deref() == Some(std::ffi::OsStr::new(name)) {
        return false;
    }
    let child = Child(std::process::Command::new(std::env::current_exe().unwrap())
        .args(["--exact", &format!("clip::watch::tests::end::{}", name), "--nocapture"])
        .env("FLEA_TEST_CLIP_END_CASE", name).spawn().unwrap());
    let (done, ended) = channel();
    extern "C" {
        fn pidfd_open(pid: i32, flags: u32) -> i32;
        fn pidfd_send_signal(fd: i32, signal: i32, info: *const std::ffi::c_void, flags: u32) -> i32;
    }
    use std::os::fd::{AsRawFd, FromRawFd};
    let raw = unsafe { pidfd_open(child.0.id() as i32, 0) };
    assert!(raw >= 0, "the watchdog holds the exact test process");
    let pidfd = unsafe { OwnedFd::from_raw_fd(raw) };
    let worker = std::thread::spawn(move || {
        let mut child = child;
        let _ = done.send(child.0.wait().unwrap());
    });
    let status = ended.recv_timeout(OWNER_WATCHDOG);
    if status.is_err() {
        unsafe { pidfd_send_signal(pidfd.as_raw_fd(), SIGKILL, std::ptr::null(), 0); }
    }
    worker.join().unwrap();
    assert!(status.expect("the isolated owner-exit watchdog").success());
    true
}

#[test]
fn stand_in_owner() {
    if std::env::var_os("FLEA_TEST_CLIP_END_OWNER").is_none() {
        return;
    }
    use std::io::{Read, Write};
    println!("owner-ready");
    std::io::stdout().flush().unwrap();
    let mut byte = [0];
    let _ = std::io::stdin().read(&mut byte);
}

fn child() -> Child {
    let mut child = Child(std::process::Command::new(std::env::current_exe().unwrap())
        .args(["--exact", CHILD_TEST, "--nocapture"])
        .env("FLEA_TEST_CLIP_END_OWNER", "1")
        .stdin(std::process::Stdio::piped()).stdout(std::process::Stdio::piped()).spawn().unwrap());
    let stdout = child.0.stdout.take().unwrap();
    let (ready, received) = channel();
    let reader = std::thread::spawn(move || {
        use std::io::BufRead;
        for line in std::io::BufReader::new(stdout).lines() {
            if line.unwrap() == "owner-ready" {
                ready.send(()).unwrap();
                return;
            }
        }
    });
    received.recv_timeout(TEST_WATCHDOG).expect("the stand-in owner is ready");
    reader.join().unwrap();
    child
}

struct Watching {
    root: PathBuf,
    listener: UnixListener,
    conn: Option<Conn>,
    incoming: Receiver<OpMsg>,
    worker: Option<std::thread::JoinHandle<()>>,
    finished: Receiver<()>,
}

impl Watching {
    fn new() -> Self {
        Self::with_state(shared(), false)
    }

    fn with_state(state: Shared, reconnect: bool) -> Self {
        static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let root = std::env::temp_dir().join(format!("flea-test-clip-end-{}-{}", std::process::id(),
            NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)));
        std::fs::create_dir(&root).unwrap();
        let path = root.join("socket");
        let listener = UnixListener::bind(&path).unwrap();
        let (replies, incoming) = channel();
        let (done, finished) = channel();
        let worker = std::thread::spawn(move || {
            if reconnect {
                watch_loop(replies, state, Some(path), NO_RETRY_WAIT);
            } else {
                let _ = connect_and_watch(&replies, &state, &Some(path));
            }
            let _ = done.send(());
        });
        let mut conn = over(crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap());
        hello(&mut conn);
        Self { root, listener, conn: Some(conn), incoming, worker: Some(worker), finished }
    }

    fn report(&mut self, id: u32, token: &str, pid: Option<u32>) {
        let mut bytes = format!("cut {}", token).into_bytes();
        if let Some(pid) = pid {
            bytes.extend_from_slice(format!(" {}", pid).as_bytes());
        }
        let answers = HashMap::from([
            (format::FLEA.into(), bytes),
            (format::GNOME.into(), format::build_gnome("cut", &["/tmp/a".into()])),
        ]);
        let conn = self.conn.as_mut().unwrap();
        offer(conn, id, &[format::FLEA, format::GNOME]);
        serve_n(conn, &answers, FLEA_RECEIVES);
        assert_eq!(field_str(&changed(&self.incoming), "token").as_deref(), Some(token));
    }

    fn fresh(&self) -> Conn {
        over(crate::clip::testutil::accept(&self.listener, TEST_WATCHDOG)
            .expect("an owner exit must read on a fresh connection"))
    }

    fn sentinel(&mut self, id: u32) {
        let conn = self.conn.as_mut().unwrap();
        offer(conn, id, &[format::GNOME]);
        let answers = HashMap::from([(format::GNOME.into(), format::build_gnome("copy", &["/tmp/new".into()]))]);
        serve_n(conn, &answers, ONE_RECEIVE);
        let line = changed(&self.incoming);
        assert_eq!(field_str(&line, "clip").as_deref(), Some("copy"), "{}", line);
        assert_eq!(field_str_array(&line, "paths"), vec!["/tmp/new"]);
    }

    fn finish(&mut self) {
        self.conn.take();
        self.finished.recv_timeout(TEST_WATCHDOG).expect("the watcher and owner waiter stop");
        self.worker.take().unwrap().join().unwrap();
    }
}

impl Drop for Watching {
    fn drop(&mut self) {
        if self.worker.is_some() {
            self.finish();
        }
        std::fs::remove_dir_all(&self.root).unwrap();
    }
}

fn read_start(conn: &mut Conn) -> u32 {
    hello(conn);
    expect(conn, DISPLAY, DISPLAY_SYNC)
}

fn empty(conn: &mut Conn, callback: u32) {
    conn.send(READER_DEVICE, DEVICE_SELECTION, &0u32.to_ne_bytes(), &[]).unwrap();
    conn.send(callback, CALLBACK_DONE, &[], &[]).unwrap();
}

#[test]
fn t1_a_reserved_selection_never_reports_none() {
    if isolated("t1_a_reserved_selection_never_reports_none") { return; }
    let mut owner = child();
    let mut watching = Watching::new();
    watching.report(INITIAL_OFFER, TOKEN, Some(owner.0.id()));
    owner.0.kill().unwrap();
    let mut fresh = watching.fresh();
    let callback = read_start(&mut fresh);
    offer(&mut fresh, INITIAL_OFFER, &[format::FLEA, format::GNOME]);
    fresh.send(callback, CALLBACK_DONE, &[], &[]).unwrap();
    let answers = HashMap::from([
        (format::FLEA.into(), format!("cut {} {}", TOKEN, owner.0.id()).into_bytes()),
        (format::GNOME.into(), format::build_gnome("cut", &["/tmp/a".into()])),
    ]);
    serve_n(&mut fresh, &answers, FLEA_RECEIVES);
    assert!(fresh.next_raw(MS).unwrap().is_none(), "the reread completes without another request");
    assert!(watching.incoming.try_recv().is_err(), "the completed reread must not guess none");
    watching.sentinel(SENTINEL_OFFER);
    assert!(watching.incoming.try_recv().is_err(), "same token emits nothing");
}

#[test]
fn t2_an_unrelated_window_reports_one_empty_read() {
    if isolated("t2_an_unrelated_window_reports_one_empty_read") { return; }
    let mut owner = child();
    let mut windows = [Watching::new(), Watching::new()];
    for window in &mut windows { window.report(INITIAL_OFFER, TOKEN, Some(owner.0.id())); }
    owner.0.kill().unwrap();
    for window in &mut windows {
        let mut fresh = window.fresh();
        let callback = read_start(&mut fresh);
        empty(&mut fresh, callback);
        assert_eq!(field_str(&changed(&window.incoming), "clip").as_deref(), Some("none"));
        window.conn.as_mut().unwrap().send(READER_DEVICE, DEVICE_SELECTION, &0u32.to_ne_bytes(), &[]).unwrap();
        window.sentinel(SENTINEL_OFFER);
        assert!(window.incoming.try_recv().is_err(), "exactly one none");
    }
}

#[test]
fn t3_a_new_report_wins_in_both_reply_orders() {
    if isolated("t3_a_new_report_wins_in_both_reply_orders") { return; }
    for watcher_first in [true, false] {
        let mut owner = child();
        let mut watching = Watching::new();
        watching.report(INITIAL_OFFER, TOKEN, Some(owner.0.id()));
        owner.0.kill().unwrap();
        let mut fresh = watching.fresh();
        let callback = read_start(&mut fresh);
        if watcher_first { watching.sentinel(SENTINEL_OFFER); }
        empty(&mut fresh, callback);
        assert!(fresh.next_raw(MS).unwrap().is_none());
        if !watcher_first {
            assert_eq!(field_str(&changed(&watching.incoming), "clip").as_deref(), Some("none"));
            watching.sentinel(SENTINEL_OFFER);
        }
        watching.finish();
        assert!(watching.incoming.try_recv().is_err(), "a late read cannot erase the newer report");
    }
}

fn waiter_detail() -> String {
    // One entry per task named flea-clip-end, with the state and wchan as evidence.
    let mut out = Vec::new();
    let Ok(tasks) = std::fs::read_dir("/proc/self/task") else { return String::from("no task dir"); };
    for task in tasks.flatten() {
        let Ok(comm) = std::fs::read_to_string(task.path().join("comm")) else { continue; };
        if comm.trim() != "flea-clip-end" { continue; }
        let tid = task.file_name().to_string_lossy().into_owned();
        // Sample: "1234 (flea-clip-end) S 1 1234 1234 0 -1 4194624 ...".
        let (state, flags) = std::fs::read_to_string(task.path().join("stat")).ok().and_then(|text| {
            text.rfind(')').and_then(|end| {
                let fields: Vec<_> = text[end + 1..].split_whitespace().collect();
                Some((fields.get(STAT_STATE_INDEX)?.to_string(), fields.get(STAT_FLAGS_INDEX)?.to_string()))
            })
        }).unwrap_or((String::from("gone"), String::from("gone")));
        let wchan = std::fs::read_to_string(task.path().join("wchan")).map(|s| s.trim().to_string()).unwrap_or_else(|_| String::from("nowchan"));
        out.push(format!("tid={} state={} flags={} wchan={}", tid, state, flags, wchan));
    }
    if out.is_empty() { String::from("no flea-clip-end task") } else { out.join(" ") }
}

fn waiters_joined() -> bool {
    let Ok(tasks) = std::fs::read_dir("/proc/self/task") else { return true; };
    for task in tasks.flatten() {
        let Ok(comm) = std::fs::read_to_string(task.path().join("comm")) else { continue; };
        if comm.trim() != "flea-clip-end" { continue; }
        let Ok(text) = std::fs::read_to_string(task.path().join("stat")) else { continue; };
        // Sample: "1234 (flea-clip-end) S 1 1234 1234 0 -1 4194624 ...".
        let joined = text.rfind(')').and_then(|end| text[end + 1..].split_whitespace().nth(STAT_FLAGS_INDEX)?.parse::<u32>().ok())
            .is_some_and(|flags| flags & PF_EXITING != 0);
        if !joined { return false; }
    }
    true
}

fn counts() -> (usize, usize, usize) {
    let fds: Vec<_> = std::fs::read_dir("/proc/self/fd").unwrap().flatten().collect();
    let pidfds = fds.iter().filter(|fd| std::fs::read_link(fd.path()).ok()
        .is_some_and(|path| path == std::path::Path::new("anon_inode:[pidfd]"))).count();
    // A task that exits while it is read is gone, so only a readable comm counts.
    let waiters = std::fs::read_dir("/proc/self/task").unwrap().flatten().filter(|task|
        std::fs::read_to_string(task.path().join("comm")).ok()
            .is_some_and(|comm| comm.trim() == "flea-clip-end")).count();
    (waiters, pidfds, fds.len())
}

#[test]
fn t4_old_and_foreign_pids_never_trigger_a_read() {
    if isolated("t4_old_and_foreign_pids_never_trigger_a_read") { return; }
    let mut owner = child();
    let mut watching = Watching::new();
    for (id, pid) in [(INITIAL_OFFER, None), (FOREIGN_OFFER, Some(std::process::id()))] {
        let token = format!("{:032x}", id);
        watching.report(id, &token, pid);
        assert_eq!(counts().1, 0, "an invalid pid holds no exit trigger");
    }
    watching.sentinel(SENTINEL_OFFER);
    watching.report(LIVE_OWNER_OFFER, TOKEN, Some(owner.0.id()));
    assert!(counts().1 > 0, "a live Flea owner arms the positive control");
    owner.0.kill().unwrap();
    let mut fresh = watching.fresh();
    let callback = read_start(&mut fresh);
    empty(&mut fresh, callback);
    assert_eq!(field_str(&changed(&watching.incoming), "clip").as_deref(), Some("none"));
    watching.finish();
    assert!(watching.incoming.try_recv().is_err(), "invalid owners emitted no extra report");
}

#[test]
fn t5_a_hundred_selections_leave_no_waiter_or_fd_leak() {
    if isolated("t5_a_hundred_selections_leave_no_waiter_or_fd_leak") { return; }
    let mut first = child();
    let owner = child();
    let before = counts();
    let mut watching = Watching::new();
    // A completed exit read proves the reusable waiter has started before its thread is counted.
    watching.report(WARMUP_OFFER, TOKEN, Some(first.0.id()));
    first.0.kill().unwrap();
    let mut fresh = watching.fresh();
    let callback = read_start(&mut fresh);
    empty(&mut fresh, callback);
    assert_eq!(field_str(&changed(&watching.incoming), "clip").as_deref(), Some("none"));
    assert!(fresh.next_raw(MS).unwrap().is_none());
    drop(fresh);
    for id in INITIAL_OFFER..INITIAL_OFFER + SELECTION_COUNT {
        watching.report(id, &format!("{:032x}", id), Some(owner.0.id()));
        let (waiters, pidfds, _) = counts();
        assert_eq!(waiters, 1, "only one owner-exit waiter across copies");
        assert!((1..=2).contains(&pidfds), "only current and replacing pidfd can overlap");
    }
    crate::clip::end::STOP_HOLD_MS.store(WAITER_STOP_HOLD_MS, std::sync::atomic::Ordering::Relaxed);
    watching.finish();
    assert!(waiters_joined(), "the last waiter ends with the watcher: {}", waiter_detail());
    assert_eq!(counts().1, 0, "all selection pidfds close");
    drop(watching);
    assert_eq!(counts().2, before.2, "no extra fd survives a hundred copies");
}

#[test]
fn a_failed_exit_read_reports_nothing_and_never_retries() {
    if isolated("a_failed_exit_read_reports_nothing_and_never_retries") { return; }
    let mut owner = child();
    let mut watching = Watching::new();
    watching.report(INITIAL_OFFER, TOKEN, Some(owner.0.id()));
    owner.0.kill().unwrap();
    let mut fresh = watching.fresh();
    hello(&mut fresh);
    let _ = expect(&mut fresh, DISPLAY, DISPLAY_SYNC);
    drop(fresh);
    watching.sentinel(SENTINEL_OFFER);
    watching.finish();
    assert!(watching.incoming.try_recv().is_err(), "a failed read says nothing");
    watching.listener.set_nonblocking(true).unwrap();
    assert_eq!(watching.listener.accept().unwrap_err().kind(), std::io::ErrorKind::WouldBlock);
}

#[test]
fn an_exit_read_of_a_new_flea_selection_arms_that_owners_exit() {
    if isolated("an_exit_read_of_a_new_flea_selection_arms_that_owners_exit") { return; }
    const NEXT: &str = "038b038b038b038b038b038b038b038b";
    let mut old = child();
    let mut next = child();
    let mut watching = Watching::new();
    watching.report(INITIAL_OFFER, TOKEN, Some(old.0.id()));
    old.0.kill().unwrap();
    let mut fresh = watching.fresh();
    let callback = read_start(&mut fresh);
    offer(&mut fresh, INITIAL_OFFER, &[format::FLEA, format::GNOME]);
    fresh.send(callback, CALLBACK_DONE, &[], &[]).unwrap();
    let answers = HashMap::from([
        (format::FLEA.into(), format!("cut {} {}", NEXT, next.0.id()).into_bytes()),
        (format::GNOME.into(), format::build_gnome("cut", &["/tmp/a".into()])),
    ]);
    serve_n(&mut fresh, &answers, FLEA_RECEIVES);
    assert_eq!(field_str(&changed(&watching.incoming), "token").as_deref(), Some(NEXT));
    let conn = watching.conn.as_mut().unwrap();
    offer(conn, NEXT_OWNER_OFFER, &[format::FLEA, format::GNOME]);
    serve_n(conn, &answers, FLEA_RECEIVES);
    next.0.kill().unwrap();
    let mut fresh = watching.fresh();
    let callback = read_start(&mut fresh);
    empty(&mut fresh, callback);
    assert_eq!(field_str(&changed(&watching.incoming), "clip").as_deref(), Some("none"));
    watching.finish();
    assert!(watching.incoming.try_recv().is_err(), "the watcher dedupes the selection read earlier");
}

#[path = "watch_end_race_tests.rs"]
mod races;

#[path = "watch_end_sequence_tests.rs"]
mod sequence;
