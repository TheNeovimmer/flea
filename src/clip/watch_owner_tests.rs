// Owner exits against the watcher's report path, without relying on a compositor's empty-selection event.
use super::*;
use crate::clip::own;
use std::sync::mpsc::{channel, Receiver, TryRecvError};

const TEST_REAPER_WATCHDOG: Duration = Duration::from_secs(5);
const NONE: &str = r#"{"t":"clip","op":"changed","clip":"none","paths":[],"token":"","skipped":0}"#;

struct StandIn(Option<std::process::Child>);

impl Drop for StandIn {
    fn drop(&mut self) {
        if let Some(child) = self.0.as_mut() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

struct Observer { state: Shared, replies: Sender<OpMsg> }

fn observer() -> (Observer, Receiver<OpMsg>) {
    let (replies, incoming) = channel();
    let state = shared();
    (Observer { state, replies }, incoming)
}

fn line(incoming: &Receiver<OpMsg>) -> String {
    match incoming.try_recv().expect("the completed owner must have sent changed none") {
        OpMsg::Meta { line } => line,
        _ => panic!("a clipboard line"),
    }
}

fn no_line(incoming: &Receiver<OpMsg>) {
    assert!(matches!(incoming.try_recv(), Err(TryRecvError::Empty)), "no extra clipboard line");
}

fn spawn() -> StandIn {
    StandIn(Some(std::process::Command::new("/bin/true").spawn().unwrap()))
}

fn end(mut child: StandIn, token: &str) {
    let reaper = own::start_reaper(child.0.take().unwrap(), token.to_string());
    let (done, ended) = channel();
    std::thread::spawn(move || {
        let _ = done.send(reaper.join());
    });
    ended.recv_timeout(TEST_REAPER_WATCHDOG).expect("the owner reaper must finish").unwrap();
}

fn report_cut(observed: &Observer, incoming: &Receiver<OpMsg>, token: &str) {
    emit(&observed.replies, &observed.state, "cut", &["/tmp/f2".into()], token, 0);
    assert_eq!(line(incoming), changed("cut", &["/tmp/f2".into()], token, 0));
}

fn report_end(observed: &Observer, token: &str, op: &str, read_token: &str) {
    reread(&observed.replies, &observed.state, token, || Ok(super::super::control::OfferFiles {
        op: op.into(), paths: if op == "none" { Vec::new() } else { vec!["/tmp/f2".into()] },
        token: read_token.into(), skipped: 0, owner_pid: None,
    }), || false, |_| {});
}

#[test]
fn the_current_owners_end_reports_exactly_one_none() {
    const TOKEN: &str = "038a038a038a038a038a038a038a038a";
    let (observed, incoming) = observer();
    let child = spawn();
    report_cut(&observed, &incoming, TOKEN);
    end(child, TOKEN);
    report_end(&observed, TOKEN, "none", "");
    assert_eq!(line(&incoming), NONE);
    no_line(&incoming);
}

#[test]
fn a_later_spawned_owner_is_read_instead_of_guessing_none() {
    const TOKEN: &str = "038d038d038d038d038d038d038d038d";
    const LATER: &str = "038b038b038b038b038b038b038b038b";
    let (observed, incoming) = observer();
    let child = spawn();
    report_cut(&observed, &incoming, TOKEN);
    let later = spawn();
    end(child, TOKEN);
    report_end(&observed, TOKEN, "cut", LATER);
    assert_eq!(line(&incoming), changed("cut", &["/tmp/f2".into()], LATER, 0));
    no_line(&incoming);
    end(later, LATER);
    no_line(&incoming);
}

#[test]
fn a_new_selection_reported_before_the_owners_end_suppresses_none() {
    const TOKEN: &str = "038e038e038e038e038e038e038e038e";
    let (observed, incoming) = observer();
    let child = spawn();
    report_cut(&observed, &incoming, TOKEN);
    // A foreign selection has no token, and it must remain current when the old owner exits.
    emit(&observed.replies, &observed.state, "copy", &["/tmp/new".into()], "", 0);
    assert_eq!(line(&incoming), changed("copy", &["/tmp/new".into()], "", 0));
    end(child, TOKEN);
    assert!(!reread(&observed.replies, &observed.state, TOKEN, || panic!("a newer report skips the read"), || false, |_| {}));
    no_line(&incoming);
}

#[test]
fn an_owner_end_then_a_real_selection_reports_none_then_the_selection_without_duplicates() {
    const TOKEN: &str = "038f038f038f038f038f038f038f038f";
    const LATER: &str = "038c038c038c038c038c038c038c038c";
    let (observed, incoming) = observer();
    let child = spawn();
    report_cut(&observed, &incoming, TOKEN);
    end(child, TOKEN);
    report_end(&observed, TOKEN, "none", "");
    assert_eq!(line(&incoming), NONE);
    report_end(&observed, TOKEN, "none", "");
    emit(&observed.replies, &observed.state, "none", &[], "", 0);
    no_line(&incoming);
    emit(&observed.replies, &observed.state, "cut", &["/tmp/new".into()], LATER, 0);
    assert_eq!(line(&incoming), changed("cut", &["/tmp/new".into()], LATER, 0));
    report_end(&observed, TOKEN, "none", "");
    no_line(&incoming);
}

#[test]
fn an_owner_end_without_a_running_watcher_sends_nothing() {
    const TOKEN: &str = "03800380038003800380038003800380";
    let (observed, incoming) = observer();
    let child = spawn();
    report_cut(&observed, &incoming, TOKEN);
    end(child, TOKEN);
    no_line(&incoming);
}

#[test]
fn a_read_of_the_same_token_emits_nothing_even_if_file_bytes_differ() {
    let (observed, incoming) = observer();
    report_cut(&observed, &incoming, "same-token");
    assert!(reread(&observed.replies, &observed.state, "same-token", || Ok(super::super::control::OfferFiles {
        op: "cut".into(), paths: vec!["/tmp/different".into()], token: "same-token".into(), skipped: 0, owner_pid: None,
    }), || false, |_| panic!("same token must not replace its waiter")));
    no_line(&incoming);
}
