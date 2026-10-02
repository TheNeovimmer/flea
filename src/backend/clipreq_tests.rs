use super::*;
use crate::backend::testdir::TestDir;
use crate::clip::protocol::{DISPLAY, DISPLAY_GET_REGISTRY, DISPLAY_SYNC};
use crate::clip::wire::Conn;
use crate::clip::DisplayEnv;
use crate::json::field_str;
use std::os::fd::OwnedFd;
use std::os::unix::net::UnixListener;
use std::sync::mpsc::{channel, RecvTimeoutError};
use std::time::Duration;

// Hang bounds for handshakes that must arrive, never durations the code under test is held to.
const TEST_WATCHDOG: Duration = Duration::from_secs(5);
const TEST_HOLD_WATCHDOG: Duration = Duration::from_secs(10);
const TEST_WAIT_MS: u32 = 5000;

fn clip_line(message: OpMsg) -> String {
    let OpMsg::Meta { line } = message else { panic!("a clip line") };
    line
}

#[test]
fn a_request_runs_beside_the_loop_that_made_it() {
    let (replies, result) = channel();
    let (entered, running) = channel();
    let (release, proceed) = channel();
    beside(replies, move || {
        entered.send(()).unwrap();
        proceed.recv_timeout(TEST_HOLD_WATCHDOG).unwrap();
        reply::reply_clear(true, false, "")
    });
    // The work is parked until released here, so a call that ran it inline would never reach this line.
    running.recv_timeout(TEST_WATCHDOG).unwrap();
    release.send(()).unwrap();
    assert_eq!(field_str(&clip_line(result.recv_timeout(TEST_WATCHDOG).unwrap()), "op").as_deref(), Some("clear"));
}

#[test]
fn a_silent_set_owner_never_holds_the_request_loop_and_still_refuses() {
    let dir = TestDir::new("clip-set-silent");
    let script = dir.script("owner", "#!/bin/sh\ncat >/dev/null\nprintf 'payload-read\\n'\nexec tail -f /dev/null\n");
    let (replies, result) = channel();
    let (entered, running) = channel();
    let (release, proceed) = channel();
    let (returned, free) = channel();
    let caller = std::thread::spawn(move || {
        set_with(replies, move || own::spawn_owner_with(&script, "copy", &["/tmp/a".into()], |rx| {
            let read = rx.recv_timeout(TEST_WATCHDOG).unwrap();
            assert_eq!(read.1.trim_end(), "payload-read");
            entered.send(()).unwrap();
            proceed.recv_timeout(TEST_HOLD_WATCHDOG).unwrap();
            Err(RecvTimeoutError::Timeout)
        }));
        returned.send(()).unwrap();
    });
    running.recv_timeout(TEST_WATCHDOG).unwrap();
    let request_returned = free.recv_timeout(TEST_WATCHDOG);
    release.send(()).ok();
    caller.join().unwrap();
    assert!(request_returned.is_ok(), "request_set must return while the silent owner is still awaiting ready");
    let line = clip_line(result.recv_timeout(TEST_WATCHDOG).unwrap());
    assert!(line.contains(r#""ok":false"#));
    assert!(line.contains("the clipboard owner did not answer"));
}

#[test]
fn a_hung_compositor_gets_a_refusal_once_it_lets_go() {
    let dir = TestDir::new("clip-clear-hang");
    let sock = dir.join("hang");
    let listener = UnixListener::bind(&sock).unwrap();
    let env = DisplayEnv::set(Some(&sock));
    let (accepted, held) = channel();
    let (release, proceed) = channel();
    let compositor = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut conn = Conn::over(OwnedFd::from(stream));
        // Both handshake requests are read, so closing later ends the stream cleanly, never with a reset.
        for opcode in [DISPLAY_GET_REGISTRY, DISPLAY_SYNC] {
            let event = conn.next_raw(TEST_WAIT_MS).unwrap().expect("a handshake request");
            assert_eq!((event.sender, event.opcode), (DISPLAY, opcode));
        }
        accepted.send(()).unwrap();
        // The accepted stream stays open and silent until the test lets go of it.
        proceed.recv_timeout(TEST_HOLD_WATCHDOG).unwrap();
        drop(conn);
    });
    let (replies, result) = channel();
    request_clear(replies, String::new(), vec!["/tmp/a.txt".to_string()]);
    held.recv_timeout(TEST_WATCHDOG).unwrap();
    release.send(()).unwrap();
    // The reply is the clear worker's last act, so the display is restored only after it read it.
    let line = clip_line(result.recv_timeout(TEST_WATCHDOG).unwrap());
    drop(env);
    compositor.join().unwrap();
    assert!(line.contains(r#""ok":false"#), "{}", line);
    assert!(line.contains("the compositor closed the connection"), "{}", line);
}

#[test]
fn a_watch_starts_once_and_the_second_is_silent() {
    // No display, so the thread ends after one honest error line and the channel closes with it.
    let _env = DisplayEnv::set(None);
    let (tx, rx) = channel();
    let mut watching = false;
    request_watch(tx.clone(), &mut watching);
    assert!(watching);
    request_watch(tx, &mut watching);
    let mut lines = 0;
    for m in rx.iter() {
        let line = clip_line(m);
        assert!(line.contains(r#""op":"changed""#));
        lines += 1;
    }
    assert_eq!(lines, 1, "one watcher means one error line, never two");
}
