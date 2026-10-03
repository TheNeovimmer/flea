// End to end against a fake compositor on a UnixListener in the test's own sandbox; connect_to reads no env.
use super::*;
use crate::backend::testdir::TestDir;
use crate::clip::owner::{own_on, serve_owner};
use crate::clip::receive::receive_type_with;
use std::collections::HashMap;
use std::os::fd::{AsRawFd, OwnedFd};
use std::os::unix::net::{UnixListener, UnixStream};
use std::time::Duration;

const MS: u32 = 5000;
const TEST_WATCHDOG: Duration = Duration::from_millis(MS as u64);
// Bounds a hang while the fake compositor reads a request or its descriptor.
const TEST_READ_MS: u32 = 2000;

// One globals round: the seat, the managers named, one unknown event the client skips, then the sync's done.
pub(super) fn fake_hello(conn: &mut Conn, managers: &[(&str, u32)]) -> (u32, u32) {
    let registry = expect(conn, 1, DISPLAY_GET_REGISTRY);
    let callback = expect(conn, 1, DISPLAY_SYNC);
    let mut payload = Vec::new();
    let mut names = vec![("wl_seat", 1u32)];
    names.extend(managers.iter().copied());
    for (index, (interface, version)) in names.iter().enumerate() {
        payload.clear();
        wire::put_u32(&mut payload, 10 + index as u32);
        wire::put_string(&mut payload, interface);
        wire::put_u32(&mut payload, *version);
        conn.send(registry, 0, &payload, &[]).unwrap();
    }
    // Unknown to this client: skipped by its size, never decoded.
    conn.send(99, 7, &[0u8; 12], &[]).unwrap();
    conn.send(callback, 0, &[], &[]).unwrap();
    (registry, callback)
}

// The next event must be this request; its new_id (or only) word is the answer.
pub(super) fn expect(conn: &mut Conn, sender: u32, opcode: u16) -> u32 {
    let event = conn.next_raw(MS).unwrap().expect("a request");
    assert_eq!((event.sender, event.opcode), (sender, opcode));
    let mut at = 0;
    wire::get_u32(&event.body, &mut at).unwrap()
}

fn serve(dir: &TestDir) -> (UnixListener, std::path::PathBuf) {
    let path = dir.join("fake-wayland");
    (UnixListener::bind(&path).unwrap(), path)
}

fn read_to_end(stream: &UnixStream) -> Vec<u8> {
    stream.set_read_timeout(Some(TEST_WATCHDOG)).unwrap();
    let mut out = Vec::new();
    use std::io::Read;
    let mut stream = stream;
    stream.read_to_end(&mut out).unwrap();
    out
}

#[test]
fn the_ext_manager_owns_and_serves_every_type_until_cancelled() {
    let dir = TestDir::new("clip-ext");
    let (listener, path) = serve(&dir);
    let paths = vec!["/tmp/a b.txt".to_string(), "/tmp/c.txt".to_string()];
    let token = "ab12cd34ab12cd34ab12cd34ab12cd34".to_string();
    let worker = std::thread::spawn({
        let paths = paths.clone();
        let token = token.clone();
        move || {
            let mut conn = Conn::connect_to(&path).unwrap();
            let bound = handshake(&mut conn).unwrap();
            assert!(bound.ext);
            let mut owner = own_on(conn, &bound, "cut", &paths, &token).unwrap();
            serve_owner(&mut owner).unwrap();
        }
    });
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = Conn::over(OwnedFd::from(stream));
    fake_hello(&mut conn, &[(wire::EXT_MANAGER, 1)]);
    // Binds, then the source, its offers, the device and the selection, up to the sync.
    let mut offers = Vec::new();
    let mut selected = None;
    loop {
        let event = conn.next_raw(MS).unwrap().expect("a request");
        if event.sender == 1 && event.opcode == 0 {
            break;
        }
        if event.sender == 6 && event.opcode == 0 {
            let mut at = 0;
            offers.push(wire::get_string(&event.body, &mut at).unwrap());
        }
        if event.sender == 7 && event.opcode == 0 {
            let mut at = 0;
            selected = wire::get_u32(&event.body, &mut at);
        }
    }
    assert_eq!(selected, Some(6));
    let want = format::offered("cut");
    assert_eq!(offers, want, "every type is offered, the cut one included");
    conn.send(8, 0, &[], &[]).unwrap();
    // Every type is then asked for and its bytes checked.
    let mut seen: HashMap<String, Vec<u8>> = HashMap::new();
    seen.insert(format::FLEA.to_string(), format::build_flea("cut", &token));
    seen.insert(format::GNOME.to_string(), format::build_gnome("cut", &paths));
    seen.insert(format::URILIST.to_string(), format::build_urilist(&paths));
    seen.insert(format::PLAIN_UTF8.to_string(), format::build_plain(&paths));
    seen.insert(format::PLAIN.to_string(), format::build_plain(&paths));
    seen.insert(format::UTF8_STRING.to_string(), format::build_plain(&paths));
    seen.insert(format::KDE_CUT.to_string(), format::build_kde_cut());
    for mime in want {
        let mut payload = Vec::new();
        wire::put_string(&mut payload, mime);
        let (ours, theirs) = UnixStream::pair().unwrap();
        conn.send(6, 0, &payload, &[theirs.as_raw_fd()]).unwrap();
        drop(theirs);
        assert_eq!(read_to_end(&ours), seen[mime], "wrong bytes for {}", mime);
    }
    conn.send(6, 1, &[], &[]).unwrap();
    worker.join().unwrap();
}

#[test]
fn the_zwlr_manager_is_the_fallback_at_the_version_it_offers() {
    for (offered, bound) in [(2u32, 2u32), (1, 1)] {
        let dir = TestDir::new("clip-zwlr");
        let (listener, path) = serve(&dir);
        let worker = std::thread::spawn(move || {
            let mut conn = Conn::connect_to(&path).unwrap();
            let bound = handshake(&mut conn).unwrap();
            assert!(!bound.ext);
        });
        let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
        let mut conn = Conn::over(OwnedFd::from(stream));
        fake_hello(&mut conn, &[(wire::ZWLR_MANAGER, offered)]);
        // The bind names the offered version, capped at 2.
        loop {
            let event = conn.next_raw(MS).unwrap().expect("a bind");
            if event.sender != 2 || event.opcode != 0 {
                continue;
            }
            let mut at = 0;
            let _ = wire::get_u32(&event.body, &mut at).unwrap();
            let interface = wire::get_string(&event.body, &mut at).unwrap();
            let version = wire::get_u32(&event.body, &mut at).unwrap();
            if interface == wire::ZWLR_MANAGER {
                assert_eq!(version, bound);
                break;
            }
        }
        worker.join().unwrap();
    }
}

#[test]
fn neither_manager_is_an_honest_error_and_not_a_hang() {
    let dir = TestDir::new("clip-nomanager");
    let (listener, path) = serve(&dir);
    let worker = std::thread::spawn(move || {
        let mut conn = Conn::connect_to(&path).unwrap();
        let err = handshake(&mut conn).unwrap_err();
        assert!(err.contains("no clipboard protocol"), "unexpected: {}", err);
    });
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = Conn::over(OwnedFd::from(stream));
    fake_hello(&mut conn, &[]);
    worker.join().unwrap();
}

#[test]
fn a_display_error_is_a_hard_failure_with_its_message() {
    let dir = TestDir::new("clip-error");
    let (listener, path) = serve(&dir);
    let worker = std::thread::spawn(move || {
        let mut conn = Conn::connect_to(&path).unwrap();
        let err = handshake(&mut conn).unwrap_err();
        assert!(err.contains("no such seat"), "unexpected: {}", err);
    });
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = Conn::over(OwnedFd::from(stream));
    let _ = expect(&mut conn, 1, DISPLAY_GET_REGISTRY);
    let callback = expect(&mut conn, 1, DISPLAY_SYNC);
    let _ = callback;
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, 1);
    wire::put_u32(&mut payload, 0);
    wire::put_string(&mut payload, "no such seat");
    conn.send(1, 0, &payload, &[]).unwrap();
    worker.join().unwrap();
}

// A selection the fake owns: an offer, its types, the selection line, then serve receives.
pub(super) fn fake_selection(conn: &mut Conn, device: u32, types: &[&str]) {
    let _ = expect(conn, 5, MANAGER_GET_DEVICE);
    let callback = expect(conn, 1, DISPLAY_SYNC);
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, 10);
    conn.send(device, 0, &payload, &[]).unwrap();
    for mime in types {
        payload.clear();
        wire::put_string(&mut payload, mime);
        conn.send(10, 0, &payload, &[]).unwrap();
    }
    payload.clear();
    wire::put_u32(&mut payload, 10);
    conn.send(device, 1, &payload, &[]).unwrap();
    conn.send(callback, 0, &[], &[]).unwrap();
}

fn serve_receives(conn: &mut Conn, answers: &HashMap<String, Vec<u8>>) -> Vec<String> {
    let mut asked = Vec::new();
    loop {
        let event = match conn.next_raw(TEST_READ_MS).unwrap() {
            Some(event) => event,
            None => return asked,
        };
        if event.sender != 10 || event.opcode != 0 {
            continue;
        }
        let mut at = 0;
        let mime = wire::get_string(&event.body, &mut at).unwrap();
        let fd = conn.take_fd(TEST_READ_MS).unwrap().expect("a pipe");
        use std::io::Write;
        let mut file = std::fs::File::from(fd);
        file.write_all(&answers[&mime]).unwrap();
        asked.push(mime);
    }
}

#[test]
fn get_reads_the_token_then_the_files() {
    let dir = TestDir::new("clip-get");
    let (listener, path) = serve(&dir);
    let token = "ab12cd34ab12cd34ab12cd34ab12cd34".to_string();
    let probe = token.clone();
    let worker = std::thread::spawn(move || {
        let mut conn = Conn::connect_to(&path).unwrap();
        let got = get_on(&mut conn).unwrap();
        assert_eq!(got.clip, "copy");
        assert_eq!(got.paths, vec!["/tmp/a.txt".to_string()]);
        assert_eq!(got.token, probe);
        assert_eq!(got.skipped, 0);
    });
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = Conn::over(OwnedFd::from(stream));
    fake_hello(&mut conn, &[(wire::EXT_MANAGER, 1)]);
    let _ = expect(&mut conn, 2, REGISTRY_BIND);
    let _ = expect(&mut conn, 2, REGISTRY_BIND);
    fake_selection(&mut conn, 6, &[format::FLEA, format::GNOME, format::URILIST, format::KDE_CUT]);
    let mut answers = HashMap::new();
    answers.insert(format::FLEA.to_string(), format::build_flea("copy", &token));
    answers.insert(format::GNOME.to_string(), format::build_gnome("copy", &["/tmp/a.txt".to_string()]));
    answers.insert(format::URILIST.to_string(), format::build_urilist(&["/tmp/a.txt".to_string()]));
    let asked = serve_receives(&mut conn, &answers);
    assert_eq!(asked, vec![format::FLEA.to_string(), format::GNOME.to_string()]);
    worker.join().unwrap();
}

#[test]
fn an_empty_selection_is_none_and_text_alone_is_none() {
    for types in [vec![], vec![format::PLAIN_UTF8]] {
        let dir = TestDir::new("clip-none");
        let (listener, path) = serve(&dir);
        let worker = std::thread::spawn(move || {
            let mut conn = Conn::connect_to(&path).unwrap();
            let got = get_on(&mut conn).unwrap();
            assert_eq!(got.clip, "none");
            assert!(got.paths.is_empty());
        });
        let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
        let mut conn = Conn::over(OwnedFd::from(stream));
        fake_hello(&mut conn, &[(wire::EXT_MANAGER, 1)]);
        let _ = expect(&mut conn, 2, REGISTRY_BIND);
        let _ = expect(&mut conn, 2, REGISTRY_BIND);
        if types.is_empty() {
            let _ = expect(&mut conn, 5, MANAGER_GET_DEVICE);
            let callback = expect(&mut conn, 1, DISPLAY_SYNC);
            let mut payload = Vec::new();
            wire::put_u32(&mut payload, 0);
            conn.send(6, 1, &payload, &[]).unwrap();
            conn.send(callback, 0, &[], &[]).unwrap();
        } else {
            fake_selection(&mut conn, 6, &[format::PLAIN_UTF8]);
            let answers: HashMap<String, Vec<u8>> = HashMap::new();
            let _ = serve_receives(&mut conn, &answers);
        }
        worker.join().unwrap();
    }
}

#[test]
fn clear_with_a_stale_token_leaves_the_selection() {
    let dir = TestDir::new("clip-stale");
    let (listener, path) = serve(&dir);
    let worker = std::thread::spawn(move || {
        let mut conn = Conn::connect_to(&path).unwrap();
        assert!(!clear_on(&mut conn, "ff12cd34ff12cd34ff12cd34ff12cd34").unwrap());
    });
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = Conn::over(OwnedFd::from(stream));
    fake_hello(&mut conn, &[(wire::EXT_MANAGER, 1)]);
    let _ = expect(&mut conn, 2, REGISTRY_BIND);
    let _ = expect(&mut conn, 2, REGISTRY_BIND);
    fake_selection(&mut conn, 6, &[format::FLEA]);
    let mut answers = HashMap::new();
    answers.insert(format::FLEA.to_string(), format::build_flea("copy", "ab12cd34ab12cd34ab12cd34ab12cd34"));
    let asked = serve_receives(&mut conn, &answers);
    assert_eq!(asked, vec![format::FLEA.to_string()]);
    // No set_selection with a null source follows: the client drops the connection instead.
    assert!(conn.next_raw(TEST_READ_MS).unwrap().is_none(), "a stale token must clear nothing");
    worker.join().unwrap();
}

#[test]
fn clear_with_the_live_token_clears() {
    let dir = TestDir::new("clip-clear");
    let (listener, path) = serve(&dir);
    let token = "ab12cd34ab12cd34ab12cd34ab12cd34".to_string();
    let probe = token.clone();
    let worker = std::thread::spawn(move || {
        let mut conn = Conn::connect_to(&path).unwrap();
        assert!(clear_on(&mut conn, &probe).unwrap());
    });
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = Conn::over(OwnedFd::from(stream));
    fake_hello(&mut conn, &[(wire::EXT_MANAGER, 1)]);
    let _ = expect(&mut conn, 2, REGISTRY_BIND);
    let _ = expect(&mut conn, 2, REGISTRY_BIND);
    fake_selection(&mut conn, 6, &[format::FLEA]);
    let mut answers = HashMap::new();
    answers.insert(format::FLEA.to_string(), format::build_flea("copy", &token));
    let event = conn.next_raw(MS).unwrap().expect("a receive");
    assert_eq!((event.sender, event.opcode), (10, 0));
    let fd = conn.take_fd(MS).unwrap().expect("a pipe");
    use std::io::Write;
    let mut file = std::fs::File::from(fd);
    file.write_all(&answers[format::FLEA]).unwrap();
    drop(file);
    // A drain sync first, then the null source and the closing sync.
    let drain = expect(&mut conn, 1, DISPLAY_SYNC);
    conn.send(drain, 0, &[], &[]).unwrap();
    let event = conn.next_raw(MS).unwrap().expect("a clear");
    assert_eq!((event.sender, event.opcode), (6, 0));
    let mut at = 0;
    assert_eq!(wire::get_u32(&event.body, &mut at), Some(0));
    let callback = expect(&mut conn, 1, DISPLAY_SYNC);
    conn.send(callback, 0, &[], &[]).unwrap();
    worker.join().unwrap();
}

// The shortest read deadline: the fake holds the write end open, so the read can only time out.
const HUNG_READ_MS: u32 = 1;

#[test]
fn a_source_that_never_closes_hits_the_timeout() {
    let dir = TestDir::new("clip-hung");
    let (listener, path) = serve(&dir);
    let worker = std::thread::spawn(move || {
        let mut conn = Conn::connect_to(&path).unwrap();
        let got = get_on_with(&mut conn, |conn, offer, mime| receive_type_with(conn, offer, mime, HUNG_READ_MS)).unwrap();
        assert_eq!(got.clip, "none", "an unreadable selection is none, not a hang");
    });
    let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
    let mut conn = Conn::over(OwnedFd::from(stream));
    fake_hello(&mut conn, &[(wire::EXT_MANAGER, 1)]);
    let _ = expect(&mut conn, 2, REGISTRY_BIND);
    let _ = expect(&mut conn, 2, REGISTRY_BIND);
    fake_selection(&mut conn, 6, &[format::URILIST]);
    let event = conn.next_raw(MS).unwrap().expect("a receive");
    assert_eq!((event.sender, event.opcode), (10, OFFER_RECEIVE));
    // Hold the pipe's write end, never writing nor closing, until the client has given up.
    let fd = conn.take_fd(MS).unwrap().expect("a pipe");
    worker.join().unwrap();
    drop(fd);
}

#[test]
fn the_socket_path_prefers_an_absolute_display() {
    // Process-global names: serialised with every other borrower.
    let _held = crate::clip::ENV_GUARD.lock().unwrap_or_else(|e| e.into_inner());
    let old_display = std::env::var_os("WAYLAND_DISPLAY");
    let old_runtime = std::env::var_os("XDG_RUNTIME_DIR");
    std::env::set_var("WAYLAND_DISPLAY", "/tmp/abs-wayland-0");
    std::env::remove_var("XDG_RUNTIME_DIR");
    assert_eq!(wire::socket_path().unwrap(), std::path::PathBuf::from("/tmp/abs-wayland-0"));
    std::env::set_var("WAYLAND_DISPLAY", "wayland-0");
    std::env::set_var("XDG_RUNTIME_DIR", "/run/user/7");
    assert_eq!(wire::socket_path().unwrap(), std::path::PathBuf::from("/run/user/7/wayland-0"));
    match old_display {
        Some(v) => std::env::set_var("WAYLAND_DISPLAY", v),
        None => std::env::remove_var("WAYLAND_DISPLAY"),
    }
    match old_runtime {
        Some(v) => std::env::set_var("XDG_RUNTIME_DIR", v),
        None => std::env::remove_var("XDG_RUNTIME_DIR"),
    }
}
