use super::*;
use super::tests::{expect, fake_hello, fake_selection};
use std::io::Write;
use std::os::unix::net::UnixStream;

const TEST_WAIT_MS: u32 = 5000;

#[test]
fn queued_replacements_survive_token_and_cut_clear() {
    let mut results = Vec::new();
    for cut in [false, true] {
        let (client, server) = UnixStream::pair().unwrap();
        let worker = std::thread::spawn(move || {
            let mut conn = Conn::over(client.into());
            if cut {
                clear_cut_on(&mut conn, &["/tmp/a".into()]).unwrap()
            } else {
                clear_on(&mut conn, "ab12cd34ab12cd34ab12cd34ab12cd34").unwrap()
            }
        });
        let mut conn = Conn::over(server.into());
        fake_hello(&mut conn, &[(wire::EXT_MANAGER, 1)]);
        expect(&mut conn, 2, REGISTRY_BIND);
        expect(&mut conn, 2, REGISTRY_BIND);
        let mime = if cut { format::GNOME } else { format::FLEA };
        fake_selection(&mut conn, 6, &[mime]);
        let request = conn.next_raw(TEST_WAIT_MS).unwrap().unwrap();
        assert_eq!((request.sender, request.opcode), (10, OFFER_RECEIVE));
        let fd = conn.take_fd(TEST_WAIT_MS).unwrap().unwrap();
        let mut payload = Vec::new();
        wire::put_u32(&mut payload, 11);
        conn.send(6, 0, &payload, &[]).unwrap();
        conn.send(6, 1, &payload, &[]).unwrap();
        let bytes = if cut { format::build_gnome("cut", &["/tmp/a".into()]) }
            else { format::build_flea("copy", "ab12cd34ab12cd34ab12cd34ab12cd34") };
        std::fs::File::from(fd).write_all(&bytes).unwrap();
        let mut null_seen = false;
        while let Some(event) = conn.next_raw(TEST_WAIT_MS).unwrap() {
            if event.sender == 6 && event.opcode == DEVICE_SET_SELECTION {
                null_seen = true;
            } else if event.sender == 1 && event.opcode == DISPLAY_SYNC {
                let mut at = 0;
                let callback = wire::get_u32(&event.body, &mut at).unwrap();
                conn.send(callback, 0, &[], &[]).unwrap();
            }
        }
        results.push((cut, null_seen, worker.join().unwrap()));
    }
    assert_eq!(results, vec![(false, false, false), (true, false, false)], "queued replacements must never receive a null selection");
}
