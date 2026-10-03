use super::*;
use std::io::Write;

enum Loss {
    Closed,
    Refused,
    Partial,
}

#[test]
fn the_final_lost_line_keeps_the_last_dropped_connection_cause() {
    const REFUSAL_OBJECT: u32 = READER_DEVICE;
    const REFUSAL_CODE: u32 = 7;
    const REFUSAL_TEXT: &str = "clipboard permission revoked";
    const PARTIAL_BYTES: usize = std::mem::size_of::<u32>();
    for (loss, cause) in [
        (Loss::Closed, "the compositor closed the connection"),
        (Loss::Refused, "the compositor refused object 6 code 7 (clipboard permission revoked)"),
        (Loss::Partial, "the compositor closed the connection mid-message"),
    ] {
        let (_dir, listener, path) = serve("clip-watch-lost-cause");
        let (tx, rx) = std::sync::mpsc::channel();
        let watcher = std::thread::spawn(move || watch_loop(tx, Some(path), NO_RETRY_WAIT));
        for attempt in 0..=RETRIES {
            let stream = crate::clip::testutil::accept(&listener, TEST_WATCHDOG).unwrap();
            let mut raw = stream.try_clone().unwrap();
            let mut conn = over(stream);
            hello(&mut conn);
            // Earlier drops are plain EOF, so only the final connection supplies the expected cause.
            if attempt == RETRIES {
                match loss {
                    Loss::Closed => {}
                    Loss::Refused => {
                        let mut body = Vec::new();
                        wire::put_u32(&mut body, REFUSAL_OBJECT);
                        wire::put_u32(&mut body, REFUSAL_CODE);
                        wire::put_string(&mut body, REFUSAL_TEXT);
                        conn.send(DISPLAY, DISPLAY_ERROR, &body, &[]).unwrap();
                    }
                    Loss::Partial => {
                        raw.write_all(&wire::request(READER_DEVICE, DEVICE_SELECTION, &[])[..PARTIAL_BYTES]).unwrap();
                    }
                }
            }
            drop(raw);
            drop(conn);
        }
        let error = field_str(&changed(&rx), "error").expect("the lost connection cause");
        assert_eq!(error, format!("the clipboard connection was lost: {}", cause));
        watcher.join().unwrap();
    }
}
