// The backend's clipboard requests, each answering one {"t":"clip",...} line that ui/js/Messages.js reads.
use crate::backend::opsreq::OpMsg;
use crate::clip::{control, own, reply, watch};
use std::sync::mpsc::Sender;

// Validated before any spawn: a bad op or path answers rather than owning.
pub fn request_set(replies: Sender<OpMsg>, op: String, paths: Vec<String>) {
    set_with(replies, move || own::spawn_owner(&op, &paths));
}

// The owner's ready wait is up to 2 s, so the start answers beside the loop the way get does.
fn set_with(replies: Sender<OpMsg>, start: impl FnOnce() -> Result<String, String> + Send + 'static) {
    beside(replies, move || match start() {
        Ok(token) => reply::reply_set(true, &token, ""),
        Err(e) => reply::reply_set(false, "", &e),
    });
}

// A read can block on a foreign source, so this answers beside the loop like jump does.
pub fn request_get(replies: Sender<OpMsg>) {
    beside(replies, || match control::get() {
        Ok(got) => reply::reply_get(true, Some(&got), ""),
        Err(e) => reply::reply_get(false, None, &e),
    });
}

// Either clear form can block on a foreign owner, so both answer from a thread like get.
pub fn request_clear(replies: Sender<OpMsg>, token: String, cut: Vec<String>) {
    beside(replies, move || clear_line(&token, &cut));
}

fn clear_line(token: &str, cut: &[String]) -> String {
    if !cut.is_empty() {
        match control::clear_cut(cut) {
            Ok(cleared) => reply::reply_clear(true, cleared, ""),
            Err(e) => reply::reply_clear(false, false, &e),
        }
    } else if token.is_empty() {
        reply::reply_clear(false, false, "the token names the copy to clear")
    } else {
        reply::reply_clear(true, own::withdraw(token), "")
    }
}

// One thread per request: its line goes back through the ops channel the loop already drains.
fn beside(replies: Sender<OpMsg>, work: impl FnOnce() -> String + Send + 'static) {
    std::thread::spawn(move || {
        let _ = replies.send(OpMsg::Meta { line: work() });
    });
}

// Idempotent: the first starts the watcher's one thread, later ones answer nothing.
pub fn request_watch(replies: Sender<OpMsg>, watching: &mut bool) {
    if *watching {
        return;
    }
    *watching = true;
    watch::request_watch(replies);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::{field_str, field_usize};

    #[test]
    fn a_bad_set_is_refused_before_any_owner_starts() {
        for (op, path) in [("move", "/tmp/a"), ("copy", "relative/a")] {
            let (tx, rx) = std::sync::mpsc::channel();
            request_set(tx, op.into(), vec![path.into()]);
            let line = match rx.recv_timeout(std::time::Duration::from_secs(5)).unwrap() {
                OpMsg::Meta { line } => line,
                _ => panic!("a set reply"),
            };
            assert_eq!(field_str(&line, "t").as_deref(), Some("clip"));
            assert_eq!(field_str(&line, "op").as_deref(), Some("set"));
            assert!(line.contains(r#""ok":false"#));
        }
    }

    #[test]
    fn an_empty_clear_token_is_refused() {
        let (tx, rx) = std::sync::mpsc::channel();
        request_clear(tx, String::new(), Vec::new());
        let line = match rx.recv_timeout(std::time::Duration::from_secs(5)).expect("a clear reply") {
            OpMsg::Meta { line } => line,
            _ => panic!("a clear reply"),
        };
        assert!(line.contains(r#""ok":false"#));
        assert_eq!(field_str(&line, "op").as_deref(), Some("clear"));
    }

    #[test]
    fn the_get_error_shape_carries_no_clip() {
        let line = reply::reply_get(false, None, "no clipboard protocol: neither data-control manager is offered");
        assert_eq!(field_str(&line, "t").as_deref(), Some("clip"));
        assert!(line.contains(r#""ok":false"#));
        let line = reply::reply_get(true, Some(&reply::Got {
            clip: "cut".into(), paths: vec!["/a".into()], token: "t".into(), skipped: 1,
        }), "");
        assert_eq!(field_str(&line, "clip").as_deref(), Some("cut"));
        assert_eq!(field_usize(&line, "skipped"), Some(1));
    }
}

#[cfg(test)]
#[path = "clipreq_tests.rs"]
mod threading_tests;
