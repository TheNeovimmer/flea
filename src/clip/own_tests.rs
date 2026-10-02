use super::*;
use crate::backend::testdir::TestDir;
use std::sync::mpsc::{channel, RecvTimeoutError};

// A hang bound for a handshake that must arrive, never a duration the code under test is held to.
const TEST_WATCHDOG: Duration = Duration::from_secs(5);
const ECHILD: i32 = 10;

// A real child stands in for the owner: it records its pid, drains the payload, then ends or goes silent.
fn failed_child(quiet: bool) {
    let dir = TestDir::new("clip-owner-branches");
    let pidfile = dir.join("pid");
    let ending = if quiet { "printf 'payload-read\\n'\nexec tail -f /dev/null\n" } else { "exit 0\n" };
    let script = dir.script("owner", &format!("#!/bin/sh\necho $$ > '{}'\ncat >/dev/null\n{}", pidfile.display(), ending));
    let failed = spawn_owner_with(&script, "copy", &["/tmp/a".into()], |rx| {
        let read = rx.recv_timeout(TEST_WATCHDOG).unwrap();
        if quiet {
            assert_eq!(read.1.trim_end(), "payload-read", "the child consumed stdin before the ready deadline");
            Err(RecvTimeoutError::Timeout)
        } else {
            assert!(read.0 && read.1.is_empty(), "the real child ended stdout without ready");
            Ok(read)
        }
    });
    assert_eq!(failed.unwrap_err(), "the clipboard owner did not answer");
    let pid: c_int = std::fs::read_to_string(&pidfile).unwrap().trim().parse().unwrap();
    let mut status = 0;
    let result = unsafe { waitpid(pid, &mut status, WNOHANG) };
    let errno = std::io::Error::last_os_error().raw_os_error();
    if result == 0 {
        unsafe { kill(pid, SIGTERM); waitpid(pid, &mut status, 0); }
    }
    assert_eq!((result, errno), (-1, Some(ECHILD)), "this named child must already be reaped");
}

#[test]
fn an_owner_eof_failure_reaps_its_named_child() { failed_child(false); }

#[test]
fn an_owner_ready_deadline_reaps_its_named_child() { failed_child(true); }

#[test]
fn an_exited_owner_remains_unreaped_until_removed_from_the_map() {
    let token = "exit-race-test";
    let child = std::process::Command::new("/bin/true").spawn().unwrap();
    let pid = child.id();
    remember(token, pid);
    let (arrived, waiting) = channel();
    let (release, proceed) = channel();
    let worker = std::thread::spawn(move || reap_owner(child, token, || {
        arrived.send(()).unwrap();
        proceed.recv_timeout(TEST_WATCHDOG).unwrap();
    }));
    waiting.recv_timeout(TEST_WATCHDOG).unwrap();
    let recorded = owners().lock().unwrap().get(token).copied();
    let stat = std::fs::read_to_string(format!("/proc/{}/stat", pid));
    let zombie = stat.as_ref().ok().and_then(|s| s.rsplit_once(") "))
        .map(|(_, rest)| rest.starts_with("Z ")).unwrap_or(false);
    let signalled = withdraw(token);
    release.send(()).unwrap();
    worker.join().unwrap();
    assert_eq!(recorded, Some(pid));
    assert!(zombie, "a mapped exited owner must stay unreaped until the map lock removes it");
    assert!(signalled, "withdraw may signal this unreaped owned pid while it is mapped");
    assert!(!withdraw(token), "after removal withdraw cannot signal the pid");
}

#[test]
fn withdraw_kills_only_what_this_process_owns() {
    assert!(!withdraw("no-such-token"));
    let child = std::process::Command::new("/bin/sleep")
        .arg("30")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .expect("a sleeper");
    remember("test-token", child.id());
    let waiter = std::thread::spawn(move || reap_owner(child, "test-token", || {}));
    assert!(withdraw("test-token"));
    waiter.join().unwrap();
    assert!(!withdraw("test-token"), "a reaped owner leaves the map");
}
