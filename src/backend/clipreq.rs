// The backend's clipboard requests: set owns through a detached flea --clip-own,
// get reads off the request thread, clear wipes its own token or a spent foreign cut,
// watch reports every selection. One response shape, {"t":"clip",...}, read by
// ui/js/Messages.js into clipResult.
use crate::backend::opsreq::OpMsg;
use crate::clip::{control, own, reply, watch};
use std::sync::mpsc::Sender;

fn say(out: &mut impl std::io::Write, line: &str) {
    writeln!(out, "{}", line).ok();
    out.flush().ok();
}

// Validated before any spawn: a bad op or path answers rather than owning.
pub fn request_set(out: &mut impl std::io::Write, op: &str, paths: Vec<String>) {
    match own::spawn_owner(op, &paths) {
        Ok(token) => say(out, &reply::reply_set(true, &token, "")),
        Err(e) => say(out, &reply::reply_set(false, "", &e)),
    }
}

// A read can block on a foreign source, so this answers beside the loop like jump does.
pub fn request_get(replies: Sender<OpMsg>) {
    std::thread::spawn(move || {
        let line = match control::get() {
            Ok(got) => reply::reply_get(true, Some(&got), ""),
            Err(e) => reply::reply_get(false, None, &e),
        };
        let _ = replies.send(OpMsg::Meta { line });
    });
}

pub fn request_clear(replies: Sender<OpMsg>, token: String, cut: Vec<String>) {
    // Either form can block on a foreign owner, up to 2 s a read, so both answer from
    // a thread the way get does; the loop never stalls behind a hung clipboard.
    std::thread::spawn(move || {
        let line = if !cut.is_empty() {
            match control::clear_cut(&cut) {
                Ok(cleared) => reply::reply_clear(true, cleared, ""),
                Err(e) => reply::reply_clear(false, false, &e),
            }
        } else if token.is_empty() {
            reply::reply_clear(false, false, "the token names the copy to clear")
        } else {
            reply::reply_clear(true, own::withdraw(&token), "")
        };
        let _ = replies.send(OpMsg::Meta { line });
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
        let mut out = Vec::new();
        request_set(&mut out, "move", vec!["/tmp/a".to_string()]);
        let line = String::from_utf8(out).unwrap();
        assert_eq!(field_str(&line, "t").as_deref(), Some("clip"));
        assert_eq!(field_str(&line, "op").as_deref(), Some("set"));
        assert!(line.contains(r#""ok":false"#));
        let mut out = Vec::new();
        request_set(&mut out, "copy", vec!["relative/a".to_string()]);
        assert!(String::from_utf8(out).unwrap().contains(r#""ok":false"#));
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
    fn a_clear_never_holds_the_request_loop() {
        let _held = crate::clip::ENV_GUARD.lock().unwrap_or_else(|e| e.into_inner());
        let dir = crate::backend::testdir::TestDir::new("clip-clear-hang");
        let sock = dir.join("hang");
        let listener = std::os::unix::net::UnixListener::bind(&sock).unwrap();
        let old = std::env::var_os("WAYLAND_DISPLAY");
        std::env::set_var("WAYLAND_DISPLAY", &sock);
        // Accept and never answer: the cut's handshake would stall the loop for its whole timeout.
        std::thread::spawn(move || {
            let _ = listener.accept();
            std::thread::sleep(std::time::Duration::from_secs(30));
        });
        let (tx, _rx) = std::sync::mpsc::channel();
        let start = std::time::Instant::now();
        request_clear(tx, String::new(), vec!["/tmp/a.txt".to_string()]);
        let elapsed = start.elapsed();
        match old {
            Some(v) => std::env::set_var("WAYLAND_DISPLAY", v),
            None => std::env::remove_var("WAYLAND_DISPLAY"),
        }
        assert!(elapsed < std::time::Duration::from_secs(2), "clear answers from its thread in {:?}", elapsed);
    }

    #[test]
    fn a_watch_starts_once_and_the_second_is_silent() {
        let (tx, rx) = std::sync::mpsc::channel();
        let mut watching = false;
        // No compositor here, so the thread ends after one honest error line.
        request_watch(tx.clone(), &mut watching);
        assert!(watching);
        request_watch(tx, &mut watching);
        let mut lines = 0;
        for m in rx.iter() {
            if let OpMsg::Meta { line } = m {
                assert!(line.contains(r#""op":"changed""#));
                lines += 1;
            }
        }
        assert_eq!(lines, 1, "one watcher means one error line, never two");
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
