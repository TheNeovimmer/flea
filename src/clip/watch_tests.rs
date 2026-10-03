// The watcher against a fake compositor, plus the spent-cut clear form; the fake mirrors control_tests.rs's.
use super::*;
use crate::backend::testdir::TestDir;
use crate::clip::control::clear_cut_on;
use crate::clip::format;
use crate::json::{field_str, field_str_array};
use std::collections::HashMap;
use std::os::fd::OwnedFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::time::Duration;

const MS: u32 = 5000;
const TEST_WATCHDOG: Duration = Duration::from_millis(MS as u64);
// A reconnect in a test happens at once; the production one-second pause is not under test.
const NO_RETRY_WAIT: Duration = Duration::ZERO;

fn serve(tag: &str) -> (TestDir, UnixListener, PathBuf) {
    let dir = TestDir::new(tag);
    let path = dir.join("fake-watch");
    let listener = UnixListener::bind(&path).unwrap();
    (dir, listener, path)
}

fn over(stream: UnixStream) -> Conn {
    Conn::over(OwnedFd::from(stream))
}

fn expect(conn: &mut Conn, sender: u32, opcode: u16) -> u32 {
    let event = conn.next_raw(MS).unwrap().expect("a request");
    assert_eq!((event.sender, event.opcode), (sender, opcode));
    let mut at = 0;
    wire::get_u32(&event.body, &mut at).unwrap()
}

// Registry round trip, both binds and the watcher's device: everything up to the offers.
fn hello(conn: &mut Conn) {
    let registry = expect(conn, 1, 1);
    let callback = expect(conn, 1, 0);
    for (index, (interface, version)) in [("wl_seat", 1u32), ("ext_data_control_manager_v1", 1u32)].iter().enumerate() {
        let mut payload = Vec::new();
        wire::put_u32(&mut payload, 10 + index as u32);
        wire::put_string(&mut payload, interface);
        wire::put_u32(&mut payload, *version);
        conn.send(registry, 0, &payload, &[]).unwrap();
    }
    conn.send(callback, 0, &[], &[]).unwrap();
    let _ = expect(conn, 2, 0);
    let _ = expect(conn, 2, 0);
    let _ = expect(conn, 5, 1);
}

fn offer(conn: &mut Conn, id: u32, types: &[&str]) {
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, id);
    conn.send(6, 0, &payload, &[]).unwrap();
    for mime in types {
        payload.clear();
        wire::put_string(&mut payload, mime);
        conn.send(id, 0, &payload, &[]).unwrap();
    }
    payload.clear();
    wire::put_u32(&mut payload, id);
    conn.send(6, 1, &payload, &[]).unwrap();
}

// Exactly n receives, in order; destroys from offer retirement pass uncounted, bounded so a silent fake fails.
fn serve_n(conn: &mut Conn, answers: &HashMap<String, Vec<u8>>, n: usize) -> Vec<(u32, String)> {
    let mut asked = Vec::new();
    let mut seen = 0;
    while asked.len() < n {
        seen += 1;
        assert!(seen <= n + 16, "too many non-receive events for {} receives", n);
        let event = conn.next_raw(MS).unwrap().expect("a receive");
        if event.opcode == 1 {
            continue;
        }
        assert_eq!(event.opcode, 0);
        let mut at = 0;
        let mime = wire::get_string(&event.body, &mut at).unwrap();
        let fd = conn.take_fd(MS).unwrap().expect("a pipe");
        use std::io::Write;
        let mut file = std::fs::File::from(fd);
        let answer = answers.get(&mime).unwrap_or_else(|| panic!("unanswered mime {}", mime));
        file.write_all(answer).unwrap();
        asked.push((event.sender, mime));
    }
    asked
}

fn changed(rx: &std::sync::mpsc::Receiver<OpMsg>) -> String {
    let Ok(OpMsg::Meta { line }) = rx.recv_timeout(TEST_WATCHDOG) else {
        panic!("a changed line");
    };
    line
}

// Events off a thread, so a missing destroy fails the test instead of hanging a blocking read.
fn events(conn: Conn) -> std::sync::mpsc::Receiver<wire::RawEvent> {
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let mut conn = conn;
        while let Ok(Some(event)) = conn.next_raw(MS) {
            if tx.send(event).is_err() {
                break;
            }
        }
    });
    rx
}

fn next_within(rx: &std::sync::mpsc::Receiver<wire::RawEvent>, what: &str) -> wire::RawEvent {
    rx.recv_timeout(TEST_WATCHDOG).unwrap_or_else(|_| panic!("{} within the deadline", what))
}

#[test]
fn a_watcher_reports_copy_then_none_then_cut_and_dedups_a_repeat() {
    let (_dir, listener, path) = serve("clip-watch-flow");
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || watch_loop(tx, Some(path), NO_RETRY_WAIT));
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = over(stream);
    hello(&mut conn);
    let token_a = "ab12cd34ab12cd34ab12cd34ab12cd34";
    let mut answers = HashMap::new();
    answers.insert(format::FLEA.to_string(), format::build_flea("copy", token_a));
    answers.insert(format::GNOME.to_string(), format::build_gnome("copy", &["/tmp/a.txt".to_string()]));
    // A Flea copy: token and files both land.
    offer(&mut conn, 10, &[format::FLEA, format::GNOME]);
    assert_eq!(serve_n(&mut conn, &answers, 2).iter().map(|(_, m)| m.clone()).collect::<Vec<_>>(),
        vec![format::FLEA.to_string(), format::GNOME.to_string()]);
    let line = changed(&rx);
    assert_eq!(field_str(&line, "clip").as_deref(), Some("copy"));
    assert_eq!(field_str(&line, "token").as_deref(), Some(token_a));
    assert_eq!(field_str_array(&line, "paths"), vec!["/tmp/a.txt".to_string()]);
    // Text only: none, and no receive is ever issued for its offer.
    offer(&mut conn, 11, &["text/plain;charset=utf-8"]);
    let line = changed(&rx);
    assert_eq!(field_str(&line, "clip").as_deref(), Some("none"));
    assert!(field_str_array(&line, "paths").is_empty());
    // A foreign cut: gnome's own word decides, no token rides along.
    answers.insert(format::GNOME.to_string(), format::build_gnome("cut", &["/tmp/q.txt".to_string()]));
    offer(&mut conn, 12, &[format::GNOME]);
    assert_eq!(serve_n(&mut conn, &answers, 1), vec![(12, format::GNOME.to_string())]);
    let line = changed(&rx);
    assert_eq!(field_str(&line, "clip").as_deref(), Some("cut"));
    assert_eq!(field_str_array(&line, "paths"), vec!["/tmp/q.txt".to_string()]);
    // The same token twice: received twice, emitted once.
    let token_b = "ff12cd34ff12cd34ff12cd34ff12cd34";
    answers.insert(format::FLEA.to_string(), format::build_flea("copy", token_b));
    answers.insert(format::GNOME.to_string(), format::build_gnome("copy", &["/tmp/r.txt".to_string()]));
    offer(&mut conn, 13, &[format::FLEA, format::GNOME]);
    serve_n(&mut conn, &answers, 2);
    let line = changed(&rx);
    assert_eq!(field_str(&line, "token").as_deref(), Some(token_b));
    offer(&mut conn, 14, &[format::FLEA, format::GNOME]);
    serve_n(&mut conn, &answers, 2);
    // A later distinct selection must be the very next line, so the repeat emitted nothing between.
    answers.insert(format::GNOME.to_string(), format::build_gnome("cut", &["/tmp/sentinel.txt".to_string()]));
    offer(&mut conn, 15, &[format::GNOME]);
    serve_n(&mut conn, &answers, 1);
    let line = changed(&rx);
    assert_eq!(field_str(&line, "clip").as_deref(), Some("cut"), "a repeated token emits once: {}", line);
    assert_eq!(field_str_array(&line, "paths"), vec!["/tmp/sentinel.txt".to_string()]);
}

#[test]
fn a_dropped_connection_reconnects_once() {
    let (_dir, listener, path) = serve("clip-watch-drop");
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || watch_loop(tx, Some(path), NO_RETRY_WAIT));
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = over(stream);
    hello(&mut conn);
    let mut answers = HashMap::new();
    answers.insert(format::GNOME.to_string(), format::build_gnome("copy", &["/tmp/a.txt".to_string()]));
    offer(&mut conn, 10, &[format::GNOME]);
    serve_n(&mut conn, &answers, 1);
    let line = changed(&rx);
    assert_eq!(field_str_array(&line, "paths"), vec!["/tmp/a.txt".to_string()]);
    // The drop: the watcher comes back on a new connection.
    drop(conn);
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = over(stream);
    hello(&mut conn);
    answers.insert(format::GNOME.to_string(), format::build_gnome("cut", &["/tmp/b.txt".to_string()]));
    offer(&mut conn, 10, &[format::GNOME]);
    serve_n(&mut conn, &answers, 1);
    let line = changed(&rx);
    assert_eq!(field_str(&line, "clip").as_deref(), Some("cut"));
    assert_eq!(field_str_array(&line, "paths"), vec!["/tmp/b.txt".to_string()]);
}

// One cut-form clear against the fake: the null source follows only an exact cut match.
fn clear_case(gnome: Vec<u8>, wanted: Vec<String>) -> bool {
    let (_dir, listener, path) = serve("clip-cut-case");
    let worker = std::thread::spawn(move || {
        let mut conn = Conn::connect_to(&path).unwrap();
        clear_cut_on(&mut conn, &wanted).unwrap()
    });
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = over(stream);
    let registry = expect(&mut conn, 1, 1);
    let callback = expect(&mut conn, 1, 0);
    for (index, (interface, version)) in [("wl_seat", 1u32), ("ext_data_control_manager_v1", 1u32)].iter().enumerate() {
        let mut payload = Vec::new();
        wire::put_u32(&mut payload, 10 + index as u32);
        wire::put_string(&mut payload, interface);
        wire::put_u32(&mut payload, *version);
        conn.send(registry, 0, &payload, &[]).unwrap();
    }
    conn.send(callback, 0, &[], &[]).unwrap();
    let _ = expect(&mut conn, 2, 0);
    let _ = expect(&mut conn, 2, 0);
    let _ = expect(&mut conn, 5, 1);
    let callback = expect(&mut conn, 1, 0);
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, 10);
    conn.send(6, 0, &payload, &[]).unwrap();
    payload.clear();
    wire::put_string(&mut payload, format::GNOME);
    conn.send(10, 0, &payload, &[]).unwrap();
    payload.clear();
    wire::put_u32(&mut payload, 10);
    conn.send(6, 1, &payload, &[]).unwrap();
    conn.send(callback, 0, &[], &[]).unwrap();
    let mut answers = HashMap::new();
    answers.insert(format::GNOME.to_string(), gnome);
    serve_n(&mut conn, &answers, 1);
    // A clear is a drain sync, a null source and a closing sync; anything else is the connection ending.
    match conn.next_raw(MS).unwrap() {
        Some(event) if event.sender == 1 && event.opcode == 0 => {
            let mut at = 0;
            let drain = wire::get_u32(&event.body, &mut at).unwrap();
            conn.send(drain, 0, &[], &[]).unwrap();
            let event = conn.next_raw(MS).unwrap().expect("a null source");
            assert_eq!((event.sender, event.opcode), (6, 0));
            let mut at = 0;
            assert_eq!(wire::get_u32(&event.body, &mut at), Some(0));
            let callback = expect(&mut conn, 1, 0);
            conn.send(callback, 0, &[], &[]).unwrap();
            assert!(worker.join().unwrap());
            true
        }
        _ => {
            assert!(!worker.join().unwrap());
            false
        }
    }
}

#[test]
fn a_spent_foreign_cut_clears() {
    let gnome = format::build_gnome("cut", &["/tmp/a.txt".to_string(), "/tmp/b.txt".to_string()]);
    assert!(clear_case(gnome, vec!["/tmp/a.txt".to_string(), "/tmp/b.txt".to_string()]));
}

#[test]
fn a_copy_and_a_stale_cut_never_clear() {
    let gnome = format::build_gnome("copy", &["/tmp/a.txt".to_string()]);
    assert!(!clear_case(gnome, vec!["/tmp/a.txt".to_string()]), "the cut form never clears a copy");
    let gnome = format::build_gnome("cut", &["/tmp/a.txt".to_string()]);
    assert!(!clear_case(gnome, vec!["/tmp/other.txt".to_string()]), "another copy arriving in between clears nothing");
}

#[test]
fn a_thousand_superseded_offers_are_destroyed() {
    let (_dir, listener, path) = serve("clip-watch-retire");
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || watch_loop(tx, Some(path), NO_RETRY_WAIT));
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = over(stream);
    hello(&mut conn);
    // A thousand offers with no types between them: nothing to receive, only to retire.
    for id in 100..1100u32 {
        let mut payload = Vec::new();
        wire::put_u32(&mut payload, id);
        conn.send(6, 0, &payload, &[]).unwrap();
    }
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, 1099);
    conn.send(6, 1, &payload, &[]).unwrap();
    // Every superseded offer is destroyed; the current one stays held.
    let incoming = events(conn);
    let mut destroyed = Vec::new();
    for _ in 0..999 {
        let event = next_within(&incoming, "a destroy");
        assert_eq!(event.opcode, 1);
        assert!(event.body.is_empty());
        destroyed.push(event.sender);
    }
    destroyed.sort_unstable();
    assert_eq!(destroyed, (100..1099u32).collect::<Vec<_>>());
    // The surviving offer reads as nothing, and that single none still emits.
    let line = changed(&rx);
    assert_eq!(field_str(&line, "clip").as_deref(), Some("none"));
}

#[test]
fn an_over_cap_selection_is_refused_not_broadcast() {
    let (_dir, listener, path) = serve("clip-watch-cap");
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || watch_loop(tx, Some(path), NO_RETRY_WAIT));
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = over(stream);
    hello(&mut conn);
    let paths: Vec<String> = (0..100001).map(|i| format!("/tmp/f{:06}.txt", i)).collect();
    let mut answers = HashMap::new();
    answers.insert(format::GNOME.to_string(), format::build_gnome("copy", &paths));
    offer(&mut conn, 10, &[format::GNOME]);
    assert_eq!(serve_n(&mut conn, &answers, 1), vec![(10, format::GNOME.to_string())]);
    // Refused out loud, never as a 100001-path changed line.
    let line = changed(&rx);
    assert_eq!(field_str(&line, "clip").as_deref(), Some("none"));
    assert!(line.contains("past the 100000 cap"), "an honest error line: {}", line);
}

#[test]
fn a_primary_selection_retires_only_its_offer_and_keeps_the_clipboard() {
    let (_dir, listener, path) = serve("clip-watch-primary");
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || watch_loop(tx, Some(path), NO_RETRY_WAIT));
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = over(stream);
    hello(&mut conn);
    let mut answers = HashMap::new();
    answers.insert(format::GNOME.to_string(), format::build_gnome("copy", &["/tmp/a".into()]));
    offer(&mut conn, 10, &[format::GNOME]);
    serve_n(&mut conn, &answers, 1);
    assert_eq!(field_str(&changed(&rx), "clip").as_deref(), Some("copy"));
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, 11);
    conn.send(6, 0, &payload, &[]).unwrap();
    conn.send(6, 3, &payload, &[]).unwrap();
    let retired = conn.next_raw(MS).unwrap().expect("primary offer retired");
    assert_eq!((retired.sender, retired.opcode), (11, 1), "primary must keep the clipboard offer");
    payload.clear();
    wire::put_u32(&mut payload, 10);
    conn.send(6, 1, &payload, &[]).unwrap();
    serve_n(&mut conn, &answers, 1);
    answers.insert(format::GNOME.to_string(), format::build_gnome("cut", &["/tmp/sentinel".into()]));
    offer(&mut conn, 12, &[format::GNOME]);
    serve_n(&mut conn, &answers, 1);
    let sentinel = changed(&rx);
    assert_eq!(field_str(&sentinel, "clip").as_deref(), Some("cut"));
    assert_eq!(field_str_array(&sentinel, "paths"), vec!["/tmp/sentinel"]);
}
