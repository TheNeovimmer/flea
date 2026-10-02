// The clipboard owner: a source offering every type and holding the selection.
// Ids are fixed per connection: source 6, device 7, callback 8; the reader's ids
// are control.rs's. serve_owner answers sends until cancelled or the server is lost.
use super::control::{check_error, Bound, DEVICE_SET_SELECTION, DISPLAY_SYNC, MANAGER_CREATE_SOURCE,
    MANAGER_GET_DEVICE, ROUNDTRIP_MS, SOURCE_OFFER};
use super::format;
use super::wire::{self, Conn};
use std::collections::{HashMap, HashSet};
use std::os::fd::AsRawFd;
use std::os::raw::c_int;
use std::time::{Duration, Instant};

// Block until the event or the descriptor arrives; the owner serves until it is replaced.
pub const WAIT_FOREVER: u32 = u32::MAX;
// One send never holds the serve loop past this: a reader that stopped reading must not
// wedge the owner past the cancelled event that ends it.
const SEND_TIMEOUT_MS: u32 = 2000;

#[repr(C)]
struct PollFd {
    fd: c_int,
    events: i16,
    revents: i16,
}

const POLLOUT: i16 = 4;

extern "C" {
    fn close(fd: c_int) -> c_int;
    fn open(path: *const std::os::raw::c_char, flags: c_int) -> c_int;
    fn dup2(old: c_int, new: c_int) -> c_int;
    fn poll(fds: *mut PollFd, nfds: usize, timeout: c_int) -> c_int;
    fn fcntl(fd: c_int, cmd: c_int, arg: c_int) -> c_int;
}

const O_RDWR: c_int = 2;
const F_SETFL: c_int = 4;
const O_NONBLOCK: c_int = 0o4000;

// After ready the owner holds no pipe of its parent open; stdio is /dev/null from here.
pub fn detach_stdio() {
    let null = unsafe { open(c"/dev/null".as_ptr(), O_RDWR) };
    if null < 0 {
        return;
    }
    unsafe {
        dup2(null, 0);
        dup2(null, 1);
        dup2(null, 2);
        if null > 2 {
            close(null);
        }
    }
}

#[cfg(test)]
#[path = "owner_tests.rs"]
mod tests;

pub struct Owner {
    conn: Conn,
    source: u32,
    bytes: HashMap<String, Vec<u8>>,
}

// A source offering every type and holding the selection; serve_owner answers its sends.
pub fn own_on(mut conn: Conn, bound: &Bound, op: &str, paths: &[String], token: &str) -> Result<Owner, String> {
    let mut bytes = HashMap::new();
    bytes.insert(format::FLEA.to_string(), format::build_flea(op, token));
    bytes.insert(format::GNOME.to_string(), format::build_gnome(op, paths));
    bytes.insert(format::URILIST.to_string(), format::build_urilist(paths));
    bytes.insert(format::PLAIN_UTF8.to_string(), format::build_plain(paths));
    bytes.insert(format::PLAIN.to_string(), format::build_plain(paths));
    bytes.insert(format::UTF8_STRING.to_string(), format::build_plain(paths));
    if op == "cut" {
        bytes.insert(format::KDE_CUT.to_string(), format::build_kde_cut());
    }
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, 6);
    conn.send(bound.manager, MANAGER_CREATE_SOURCE, &payload, &[])?;
    for mime in format::offered(op) {
        payload.clear();
        wire::put_string(&mut payload, mime);
        conn.send(6, SOURCE_OFFER, &payload, &[])?;
    }
    payload.clear();
    wire::put_u32(&mut payload, 7);
    wire::put_u32(&mut payload, bound.seat);
    conn.send(bound.manager, MANAGER_GET_DEVICE, &payload, &[])?;
    payload.clear();
    wire::put_u32(&mut payload, 6);
    conn.send(7, DEVICE_SET_SELECTION, &payload, &[])?;
    payload.clear();
    wire::put_u32(&mut payload, 8);
    conn.send(1, DISPLAY_SYNC, &payload, &[])?;
    loop {
        let event = conn.next_raw(ROUNDTRIP_MS)?.ok_or_else(|| "the compositor closed the connection".to_string())?;
        if let Some(failure) = check_error(&event) {
            return Err(failure);
        }
        if event.sender == 8 && event.opcode == 0 {
            return Ok(Owner { conn, source: 6, bytes });
        }
    }
}

// Every send writes that type's bytes and closes; cancelled (or a lost server) ends the owner.
pub fn serve_owner(owner: &mut Owner) -> Result<(), String> {
    let mut offers: HashSet<u32> = HashSet::new();
    loop {
        let event = owner.conn.next_raw(WAIT_FOREVER)?.ok_or_else(|| "the compositor closed the connection".to_string())?;
        if let Some(failure) = check_error(&event) {
            return Err(failure);
        }
        // The device collects offers the same way the watcher's does; superseded ones are
        // destroyed on every selection, primary ones included.
        if event.sender == 7 {
            match event.opcode {
                0 => {
                    let mut at = 0;
                    if let Some(id) = wire::get_u32(&event.body, &mut at) {
                        offers.insert(id);
                    }
                }
                1 | 3 => {
                    let mut at = 0;
                    let current = match wire::get_u32(&event.body, &mut at) {
                        Some(id) if id != 0 => Some(id),
                        _ => None,
                    };
                    for id in std::mem::take(&mut offers) {
                        if Some(id) != current {
                            let _ = owner.conn.send(id, 1, &[], &[]);
                        } else {
                            offers.insert(id);
                        }
                    }
                }
                _ => {}
            }
            continue;
        }
        if event.sender != owner.source {
            continue;
        }
        if event.opcode == 1 {
            return Ok(());
        }
        if event.opcode != 0 {
            continue;
        }
        let mut at = 0;
        let Some(mime) = wire::get_string(&event.body, &mut at) else {
            continue;
        };
        let Some(fd) = owner.conn.take_fd(ROUNDTRIP_MS)? else {
            continue;
        };
        if let Some(body) = owner.bytes.get(&mime).cloned() {
            // The close is the reader's EOF either way: an abandoned send still ends its wait.
            write_deadline(fd, &body, SEND_TIMEOUT_MS);
        }
    }
}

// One send, without ever blocking past the deadline: the fd closes on every path,
// so a reader that stopped reading learns EOF instead of wedging the serve loop.
fn write_deadline(fd: std::os::fd::OwnedFd, bytes: &[u8], timeout_ms: u32) {
    if unsafe { fcntl(fd.as_raw_fd(), F_SETFL, O_NONBLOCK) } != 0 {
        return;
    }
    let mut file = std::fs::File::from(fd);
    use std::io::Write;
    let end = Instant::now() + Duration::from_millis(timeout_ms as u64);
    let mut rest = bytes;
    while !rest.is_empty() {
        let left = end.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return;
        }
        let mut p = PollFd { fd: file.as_raw_fd(), events: POLLOUT, revents: 0 };
        if unsafe { poll(&mut p, 1, left.as_millis().min(u32::MAX as u128) as c_int) } <= 0 {
            return;
        }
        match file.write(rest) {
            Ok(0) => return,
            Ok(n) => rest = &rest[n..],
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
            Err(_) => return,
        }
    }
}
