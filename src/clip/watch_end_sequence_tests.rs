// Barriers and a held receive pipe order exit reads against real watcher events.
use super::*;
use std::io::Write;
use std::sync::Barrier;

const INITIAL_OFFER: u32 = 20;
const PENDING_OFFER: u32 = INITIAL_OFFER + 1;
const PRIMARY_BARRIER_OFFER: u32 = PENDING_OFFER + 1;
const BARRIER_PARTIES: usize = 2;
const FLEA_RECEIVES: usize = 2;

fn pending_selection(watching: &mut Watching) -> std::fs::File {
    let conn = watching.conn.as_mut().unwrap();
    offer(conn, PENDING_OFFER, &[format::GNOME]);
    let retired = conn.next_raw(MS).unwrap().expect("the old offer is retired");
    assert_eq!((retired.sender, retired.opcode), (INITIAL_OFFER, OFFER_DESTROY));
    let request = conn.next_raw(MS).unwrap().expect("the pending GNOME receive");
    assert_eq!((request.sender, request.opcode), (PENDING_OFFER, OFFER_RECEIVE));
    std::fs::File::from(conn.take_fd(MS).unwrap().unwrap())
}

fn ordered_reads(exit_first: bool) {
    let state = shared();
    let mut watching = Watching::with_state(state.clone(), false);
    watching.report(INITIAL_OFFER, TOKEN, None);
    let mut pending = if exit_first { None } else { Some(pending_selection(&mut watching)) };
    let started = Arc::new(Barrier::new(BARRIER_PARTIES));
    let release = Arc::new(Barrier::new(BARRIER_PARTIES));
    let (replies, exit_lines) = channel();
    let reader_started = started.clone();
    let reader_release = release.clone();
    let reader = std::thread::spawn(move || reread(&replies, &state, TOKEN, || {
        reader_started.wait();
        reader_release.wait();
        Ok(crate::clip::control::OfferFiles {
            op: "none".into(), paths: Vec::new(), token: String::new(), skipped: 0, owner_pid: None,
        })
    }, || false, |_| {}));
    started.wait();
    if exit_first {
        pending = Some(pending_selection(&mut watching));
    }
    release.wait();
    let reported = reader.join().unwrap();
    let mut pending = pending.unwrap();
    pending.write_all(&format::build_gnome("copy", &["/tmp/new".into()])).unwrap();
    drop(pending);
    watching.finish();
    if exit_first {
        assert!(!reported, "an exit read begun before the selection event must yield");
        assert!(exit_lines.try_recv().is_err(), "the older exit read emits nothing");
        let line = changed(&watching.incoming);
        assert_eq!(field_str_array(&line, "paths"), vec!["/tmp/new"]);
    } else {
        assert!(reported, "an exit read begun after the selection event may report");
        assert_eq!(field_str(&changed(&exit_lines), "clip").as_deref(), Some("none"));
        assert!(watching.incoming.try_recv().is_err(), "delayed watcher bytes cannot restore the ended selection");
    }
}

#[test]
fn an_earlier_exit_read_yields_to_a_pending_selection_event() {
    ordered_reads(true);
}

#[test]
fn a_later_exit_read_invalidates_pending_watcher_bytes() {
    ordered_reads(false);
}

#[test]
fn a_reconnected_identical_selection_still_watches_its_owner() {
    let mut owner = child();
    let mut watching = Watching::with_state(shared(), true);
    watching.report(INITIAL_OFFER, TOKEN, Some(owner.0.id()));
    watching.conn.take();
    let mut conn = over(crate::clip::testutil::accept(&watching.listener, TEST_WATCHDOG).unwrap());
    hello(&mut conn);
    let answers = HashMap::from([
        (format::FLEA.into(), format!("cut {} {}", TOKEN, owner.0.id()).into_bytes()),
        (format::GNOME.into(), format::build_gnome("cut", &["/tmp/a".into()])),
    ]);
    offer(&mut conn, INITIAL_OFFER, &[format::FLEA, format::GNOME]);
    serve_n(&mut conn, &answers, FLEA_RECEIVES);
    // A primary-offer retirement proves the preceding selection read and tracking completed.
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, PRIMARY_BARRIER_OFFER);
    conn.send(READER_DEVICE, DEVICE_DATA_OFFER, &payload, &[]).unwrap();
    conn.send(READER_DEVICE, DEVICE_PRIMARY_SELECTION, &payload, &[]).unwrap();
    let retired = conn.next_raw(MS).unwrap().expect("the watcher finished the repeated selection");
    assert_eq!((retired.sender, retired.opcode), (PRIMARY_BARRIER_OFFER, OFFER_DESTROY));
    watching.conn = Some(conn);
    owner.0.kill().unwrap();
    let fresh = crate::clip::testutil::accept(&watching.listener, TEST_WATCHDOG);
    let received_fresh = fresh.is_ok();
    if let Ok(stream) = fresh {
        let mut fresh = over(stream);
        let callback = read_start(&mut fresh);
        empty(&mut fresh, callback);
        assert_eq!(field_str(&changed(&watching.incoming), "clip").as_deref(), Some("none"));
        assert!(fresh.next_raw(MS).unwrap().is_none(), "the fresh read completed");
    }
    std::fs::remove_file(watching.root.join("socket")).unwrap();
    watching.finish();
    assert!(received_fresh, "a repeated selection after reconnect must arm the owner's exit read");
    assert!(field_str(&changed(&watching.incoming), "error").is_some(), "only the final connection-loss error remains");
    assert!(watching.incoming.try_recv().is_err(), "the repeated selection is still deduped");
}
