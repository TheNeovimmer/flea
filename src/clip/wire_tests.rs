use super::*;
use std::os::fd::AsRawFd;

// The codec's own checks: padding, the null string, skipping by size, the error event.
#[test]
fn a_string_round_trips_with_its_padding() {
    for (text, padded) in [("", 4), ("a", 4), ("ab", 4), ("abc", 4), ("abcd", 8)] {
        let mut out = Vec::new();
        put_string(&mut out, text);
        assert_eq!(&out[..4], &((text.len() + 1) as u32).to_ne_bytes());
        assert_eq!(out.len(), 4 + padded, "padding of {:?}", text);
        let mut at = 0;
        assert_eq!(get_string(&out, &mut at).as_deref(), Some(text));
        assert_eq!(at, 4 + padded);
    }
}

#[test]
fn a_null_string_is_a_zero_length_and_reads_as_empty() {
    let mut out = Vec::new();
    put_null_string(&mut out);
    assert_eq!(out, vec![0, 0, 0, 0]);
    let mut at = 0;
    assert_eq!(get_string(&out, &mut at).as_deref(), Some(""));
}

#[test]
fn a_truncated_or_unterminated_string_is_none() {
    let mut at = 0;
    assert!(get_string(&[3, 0, 0, 0, b'a', b'b'], &mut at).is_none());
    assert!(get_string(&[4, 0, 0, 0, b'a', b'b', b'c', 0], &mut at).is_none());
}

#[test]
fn a_request_header_names_its_size_with_the_header() {
    let bytes = request(7, 3, &[1, 2, 3, 4]);
    assert_eq!(&bytes[..4], &7u32.to_ne_bytes());
    assert_eq!(&bytes[4..8], &(((12u32) << 16 | 3).to_ne_bytes()));
    assert_eq!(&bytes[8..], &[1, 2, 3, 4]);
}

#[test]
fn descriptors_queue_across_reads_until_their_body_arrives() {
    let (a, b) = crate::backend::fdpass::pair().unwrap();
    let file = std::fs::File::create("/dev/null").unwrap();
    let raw = [file.as_raw_fd()];
    crate::backend::fdpass::send_stream(a.as_raw_fd(), &request(1, 0, &[]), &raw).unwrap();
    let mut conn = Conn::over(b);
    // The body arrives first and the descriptor is queued behind it, either order works.
    let event = conn.next_raw(2000).unwrap().expect("an event");
    assert_eq!((event.sender, event.opcode), (1, 0));
    let fd = conn.take_fd(2000).unwrap().expect("a descriptor");
    assert!(fd.as_raw_fd() >= 0);
}

#[test]
fn five_and_twenty_eight_descriptors_arrive_whole_in_one_sendmsg() {
    // libwayland's per-sendmsg maximum is 28; a flush of 5 once wedged an owner at 4.
    use std::os::unix::fs::MetadataExt;
    let dir = crate::backend::testdir::TestDir::new("clip-many-fds");
    for n in [5, 28] {
        let files: Vec<std::fs::File> = (0..n)
            .map(|i| std::fs::File::open(dir.file(&format!("f{}.txt", i), "x")).unwrap())
            .collect();
        let want: Vec<(u64, u64)> = files.iter().map(|f| {
            let m = f.metadata().unwrap();
            (m.dev(), m.ino())
        }).collect();
        let raw: Vec<std::os::fd::RawFd> = files.iter().map(|f| f.as_raw_fd()).collect();
        let (a, b) = crate::backend::fdpass::pair().unwrap();
        crate::backend::fdpass::send_stream(a.as_raw_fd(), &request(1, 0, &[]), &raw).unwrap();
        drop(files);
        let mut conn = Conn::over(b);
        let event = conn.next_raw(2000).unwrap().expect("an event");
        assert_eq!((event.sender, event.opcode), (1, 0));
        let mut got = Vec::new();
        for _ in 0..n {
            got.push(conn.take_fd(2000).unwrap().expect("a descriptor"));
        }
        assert_eq!(got.len(), n);
        for (fd, (dev, ino)) in got.iter().zip(want.iter()) {
            let file = std::fs::File::from(fd.try_clone().unwrap());
            let m = file.metadata().unwrap();
            assert_eq!((m.dev(), m.ino()), (*dev, *ino));
        }
    }
}

#[test]
fn a_partial_message_timeout_is_not_eof_and_can_resume() {
    use std::io::Write;
    let (a, mut b) = std::os::unix::net::UnixStream::pair().unwrap();
    let mut conn = Conn::over(a.into());
    let bytes = request(9, 0, b"abcd");
    b.write_all(&bytes[..4]).unwrap();
    let error = conn.next_raw(0).err().expect("a partial message deadline");
    assert_eq!(error, "the compositor did not finish a message within 0 ms");
    b.write_all(&bytes[4..]).unwrap();
    let event = conn.next_raw(0).unwrap().unwrap();
    assert_eq!((event.sender, event.body), (9, b"abcd".to_vec()));
}

#[test]
fn a_partial_message_eof_names_the_closed_connection() {
    use std::io::Write;
    let (a, mut b) = std::os::unix::net::UnixStream::pair().unwrap();
    let mut conn = Conn::over(a.into());
    b.write_all(&request(9, 0, b"abcd")[..4]).unwrap();
    drop(b);
    assert_eq!(conn.next_raw(0).err().unwrap(), "the compositor closed the connection mid-message");
}

#[test]
fn a_silent_compositor_reports_timeout_instead_of_close() {
    const POLL_NOW_MS: u32 = 0;
    let (a, _silent) = std::os::unix::net::UnixStream::pair().unwrap();
    let mut conn = Conn::over(a.into());
    let error = conn.next_raw(POLL_NOW_MS).err().expect("a silent compositor timeout");
    assert_eq!(error, "the compositor timed out waiting for a message within 0 ms");
}
