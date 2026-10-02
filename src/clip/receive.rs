// A foreign source writes to a CLOEXEC pipe with a bounded read and payload.
use super::wire::{self, Conn};
use super::protocol::OFFER_RECEIVE;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::os::raw::c_int;
use std::time::{Duration, Instant};

const READ_MS: u32 = 2000;
const READ_CAP: u64 = 64 * 1024 * 1024;
const READ_CHUNK: usize = 64 * 1024;

#[repr(C)]
struct PollFd {
    fd: c_int,
    events: i16,
    revents: i16,
}

const POLLIN: i16 = 1;

extern "C" {
    fn poll(fds: *mut PollFd, nfds: usize, timeout: c_int) -> c_int;
    fn pipe2(fds: *mut c_int, flags: c_int) -> c_int;
}

const O_CLOEXEC: c_int = 0o2000000;

fn make_pipe() -> Result<(OwnedFd, OwnedFd), String> {
    // pipe2 sets CLOEXEC atomically, so a fork cannot hand the write end to a child and hang the read.
    let mut fds = [-1, -1];
    if unsafe { pipe2(fds.as_mut_ptr(), O_CLOEXEC) } != 0 {
        return Err(format!("a clipboard pipe could not be made ({})", std::io::Error::last_os_error()));
    }
    Ok(unsafe { (OwnedFd::from_raw_fd(fds[0]), OwnedFd::from_raw_fd(fds[1])) })
}

fn readable(fd: RawFd, timeout_ms: u32) -> Result<bool, String> {
    let mut p = PollFd { fd, events: POLLIN, revents: 0 };
    // WAIT_FOREVER arrives here as -1, which is poll's own infinite wait.
    let n = unsafe { poll(&mut p, 1, timeout_ms as c_int) };
    if n < 0 {
        return Err(format!("waiting for the clipboard failed ({})", std::io::Error::last_os_error()));
    }
    Ok(n > 0)
}

// One offered type, through a pipe the source closes; a source that never closes hits the timeout.
pub fn receive_type(conn: &mut Conn, offer: u32, mime: &str) -> Result<Vec<u8>, String> {
    receive_type_with(conn, offer, mime, READ_MS)
}

pub(crate) fn receive_type_with(conn: &mut Conn, offer: u32, mime: &str, timeout_ms: u32) -> Result<Vec<u8>, String> {
    let (read, write) = make_pipe()?;
    let mut payload = Vec::new();
    wire::put_string(&mut payload, mime);
    conn.send(offer, OFFER_RECEIVE, &payload, &[write.as_raw_fd()])?;
    drop(write);
    let end = Instant::now() + Duration::from_millis(timeout_ms as u64);
    let mut out = Vec::new();
    let mut file = std::fs::File::from(read);
    use std::io::Read;
    loop {
        let left = end.saturating_duration_since(Instant::now());
        if left.is_zero() || !readable(file.as_raw_fd(), left.as_millis().min(u32::MAX as u128) as u32)? {
            return Err("a clipboard source never closed its pipe".to_string());
        }
        let mut chunk = [0u8; READ_CHUNK];
        match file.read(&mut chunk) {
            Ok(0) => return Ok(out),
            Ok(n) => {
                out.extend_from_slice(&chunk[..n]);
                if out.len() as u64 > READ_CAP {
                    return Err("a clipboard read passed its 64 MiB cap".to_string());
                }
            }
            Err(e) => return Err(format!("a clipboard read failed ({})", e)),
        }
    }
}

