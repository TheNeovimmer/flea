// The data-control reader: handshake, reading the selection and clearing it.
// Owning lives in owner.rs, the reply shape in reply.rs.
use super::format;
use super::reply::Got;
use super::wire::{self, Conn, RawEvent};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::os::raw::c_int;
use std::time::{Duration, Instant};

pub(crate) const DISPLAY_SYNC: u16 = 0;
const DISPLAY_GET_REGISTRY: u16 = 1;
const REGISTRY_BIND: u16 = 0;
pub(crate) const MANAGER_CREATE_SOURCE: u16 = 0;
pub(crate) const MANAGER_GET_DEVICE: u16 = 1;
pub(crate) const DEVICE_SET_SELECTION: u16 = 0;
pub(crate) const SOURCE_OFFER: u16 = 0;
const OFFER_RECEIVE: u16 = 0;

// A handshake and one selection collection each finish in one round trip; a receive waits
// on a foreign process, so only it gets the brief's own 2 s timeout.
pub(crate) const ROUNDTRIP_MS: u32 = 5000;
const READ_MS: u32 = 2000;
// One read never holds more than this, whatever the source keeps sending.
const READ_CAP: u64 = 64 * 1024 * 1024;

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
    // pipe2 sets CLOEXEC atomically: a fork between pipe and fcntl would hand the write
    // end to a child, and the read would never end.
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

#[derive(Debug)]
pub struct Bound {
    pub seat: u32,
    pub manager: u32,
    #[cfg_attr(not(test), allow(dead_code))]
    pub ext: bool,
}

// A wl_display.error names its failing object, code and message; it always fails the call.
pub(crate) fn check_error(event: &RawEvent) -> Option<String> {
    if event.sender != 1 || event.opcode != 0 {
        return None;
    }
    let mut at = 0;
    let object = wire::get_u32(&event.body, &mut at).unwrap_or(0);
    let code = wire::get_u32(&event.body, &mut at).unwrap_or(0);
    let message = wire::get_string(&event.body, &mut at).unwrap_or_default();
    Some(format!("the compositor refused object {} code {} ({})", object, code, message))
}

struct Globals {
    seat: Option<u32>,
    ext: Option<u32>,
    zwlr: Option<(u32, u32)>,
}

// Registry globals, then one sync round trip to collect them; no manager is an honest error.
pub fn handshake(conn: &mut Conn) -> Result<Bound, String> {
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, 2);
    conn.send(1, DISPLAY_GET_REGISTRY, &payload, &[])?;
    payload.clear();
    wire::put_u32(&mut payload, 3);
    conn.send(1, DISPLAY_SYNC, &payload, &[])?;
    let mut globals = Globals { seat: None, ext: None, zwlr: None };
    loop {
        let event = conn.next_raw(ROUNDTRIP_MS)?.ok_or_else(|| "the compositor closed the connection".to_string())?;
        if let Some(failure) = check_error(&event) {
            return Err(failure);
        }
        if event.sender == 3 && event.opcode == 0 {
            break;
        }
        if event.sender == 2 && event.opcode == 0 {
            let mut at = 0;
            let name = wire::get_u32(&event.body, &mut at);
            let interface = wire::get_string(&event.body, &mut at);
            let version = wire::get_u32(&event.body, &mut at);
            match (name, interface.as_deref(), version) {
                (Some(_), Some(interface), Some(_)) if interface == "wl_seat" && globals.seat.is_none() => {
                    globals.seat = name;
                }
                (Some(_), Some(interface), Some(_)) if interface == wire::EXT_MANAGER && globals.ext.is_none() => {
                    globals.ext = name;
                }
                (Some(_), Some(interface), Some(_)) if interface == wire::ZWLR_MANAGER => {
                    globals.zwlr = name.zip(version);
                }
                _ => {}
            }
        }
    }
    let seat_name = globals.seat.ok_or_else(|| "the compositor offers no seat, so there is no clipboard".to_string())?;
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, seat_name);
    wire::put_string(&mut payload, "wl_seat");
    wire::put_u32(&mut payload, 1);
    wire::put_u32(&mut payload, 4);
    conn.send(2, REGISTRY_BIND, &payload, &[])?;
    payload.clear();
    if let Some(name) = globals.ext {
        wire::put_u32(&mut payload, name);
        wire::put_string(&mut payload, wire::EXT_MANAGER);
        wire::put_u32(&mut payload, 1);
        wire::put_u32(&mut payload, 5);
        conn.send(2, REGISTRY_BIND, &payload, &[])?;
        return Ok(Bound { seat: 4, manager: 5, ext: true });
    }
    let (name, version) = globals.zwlr.ok_or_else(|| "no clipboard protocol: neither data-control manager is offered".to_string())?;
    wire::put_u32(&mut payload, name);
    wire::put_string(&mut payload, wire::ZWLR_MANAGER);
    wire::put_u32(&mut payload, version.min(2));
    wire::put_u32(&mut payload, 5);
    conn.send(2, REGISTRY_BIND, &payload, &[])?;
    Ok(Bound { seat: 4, manager: 5, ext: false })
}

pub struct Selection {
    pub offer: u32,
    pub types: Vec<String>,
}

// After get_data_device the compositor sends the current selection at once; the sync collects it.
pub fn read_selection(conn: &mut Conn, bound: &Bound) -> Result<Option<Selection>, String> {
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, 6);
    wire::put_u32(&mut payload, bound.seat);
    conn.send(bound.manager, MANAGER_GET_DEVICE, &payload, &[])?;
    payload.clear();
    wire::put_u32(&mut payload, 7);
    conn.send(1, DISPLAY_SYNC, &payload, &[])?;
    let mut offers: Vec<(u32, Vec<String>)> = Vec::new();
    let mut selected: Option<u32> = None;
    loop {
        let event = conn.next_raw(ROUNDTRIP_MS)?.ok_or_else(|| "the compositor closed the connection".to_string())?;
        if let Some(failure) = check_error(&event) {
            return Err(failure);
        }
        if event.sender == 7 && event.opcode == 0 {
            break;
        }
        if event.sender == 6 && event.opcode == 0 {
            let mut at = 0;
            if let Some(id) = wire::get_u32(&event.body, &mut at) {
                offers.push((id, Vec::new()));
            }
            continue;
        }
        if event.sender == 6 && event.opcode == 1 {
            let mut at = 0;
            selected = wire::get_u32(&event.body, &mut at);
            continue;
        }
        if event.opcode == 0 {
            if let Some(entry) = offers.iter_mut().find(|(id, _)| *id == event.sender) {
                let mut at = 0;
                if let Some(mime) = wire::get_string(&event.body, &mut at) {
                    entry.1.push(mime);
                }
            }
        }
    }
    match selected {
        None | Some(0) => Ok(None),
        Some(id) => Ok(offers.into_iter().find(|(offer, _)| *offer == id).map(|(offer, types)| Selection { offer, types })),
    }
}

// One offered type, through a pipe the source closes; a source that never closes hits the timeout.
pub fn receive_type(conn: &mut Conn, offer: u32, mime: &str) -> Result<Vec<u8>, String> {
    let (read, write) = make_pipe()?;
    let mut payload = Vec::new();
    wire::put_string(&mut payload, mime);
    conn.send(offer, OFFER_RECEIVE, &payload, &[write.as_raw_fd()])?;
    drop(write);
    let end = Instant::now() + Duration::from_millis(READ_MS as u64);
    let mut out = Vec::new();
    let mut file = std::fs::File::from(read);
    use std::io::Read;
    loop {
        let left = end.saturating_duration_since(Instant::now());
        if left.is_zero() || !readable(file.as_raw_fd(), left.as_millis().min(u32::MAX as u128) as u32)? {
            return Err("a clipboard source never closed its pipe".to_string());
        }
        let mut chunk = [0u8; 65536];
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

// One offer read as files, the same way for get and the watcher: our own token first,
// then GNOME's shape, then the uri-list. A failed receive falls through to the next shape;
// only a dead connection fails the read. No file shape offered means no receive at all.
pub(crate) struct OfferFiles {
    pub op: String,
    pub paths: Vec<String>,
    pub token: String,
    pub skipped: usize,
}

// What a refused read is: a selection past the path cap. Anything dead never fails the
// read at all; a failed receive just falls through to the next shape, as it always has.
pub(crate) enum ReadFail {
    Capped(String),
}

impl ReadFail {
    fn message(self) -> String {
        match self {
            ReadFail::Capped(e) => e,
        }
    }
}

pub(crate) fn read_offer(conn: &mut Conn, offer: u32, types: &[String]) -> Result<OfferFiles, ReadFail> {
    let none = OfferFiles { op: "none".to_string(), paths: Vec::new(), token: String::new(), skipped: 0 };
    let has = |mime: &str| types.iter().any(|t| t == mime);
    if has(format::FLEA) {
        if let Ok(bytes) = receive_type(conn, offer, format::FLEA) {
            if let Some((op, token)) = format::parse_flea(&bytes) {
                let mut got = OfferFiles { op, paths: Vec::new(), token, skipped: 0 };
                // The token names our own copy; the paths still come from a file shape beside it.
                if has(format::GNOME) {
                    if let Ok(bytes) = receive_type(conn, offer, format::GNOME) {
                        if let Some((_, paths, skipped)) = format::parse_gnome(&bytes) {
                            format::check_path_cap(&paths).map_err(ReadFail::Capped)?;
                            got.paths = paths;
                            got.skipped = skipped;
                        }
                    }
                }
                if got.paths.is_empty() && has(format::URILIST) {
                    if let Ok(bytes) = receive_type(conn, offer, format::URILIST) {
                        let (paths, skipped) = format::parse_urilist(&bytes);
                        format::check_path_cap(&paths).map_err(ReadFail::Capped)?;
                        got.paths = paths;
                        got.skipped = skipped;
                    }
                }
                if !got.paths.is_empty() || !got.token.is_empty() {
                    return Ok(got);
                }
            }
        }
    }
    if has(format::GNOME) {
        if let Ok(bytes) = receive_type(conn, offer, format::GNOME) {
            if let Some((op, paths, skipped)) = format::parse_gnome(&bytes) {
                if !paths.is_empty() {
                    format::check_path_cap(&paths).map_err(ReadFail::Capped)?;
                    return Ok(OfferFiles { op, paths, token: String::new(), skipped });
                }
            }
        }
    }
    if has(format::URILIST) {
        if let Ok(bytes) = receive_type(conn, offer, format::URILIST) {
            let (paths, skipped) = format::parse_urilist(&bytes);
            if !paths.is_empty() {
                format::check_path_cap(&paths).map_err(ReadFail::Capped)?;
                let mut op = "copy".to_string();
                if has(format::KDE_CUT) {
                    if let Ok(cut) = receive_type(conn, offer, format::KDE_CUT) {
                        if format::parse_kde_cut(&cut) {
                            op = "cut".to_string();
                        }
                    }
                }
                return Ok(OfferFiles { op, paths, token: String::new(), skipped });
            }
        }
    }
    Ok(none)
}

// The current selection as files: our own token first, then GNOME's shape, then the uri-list.
pub fn get_on(conn: &mut Conn) -> Result<Got, String> {
    let bound = handshake(conn)?;
    let none = Got { clip: "none".to_string(), paths: Vec::new(), token: String::new(), skipped: 0 };
    let Some(selection) = read_selection(conn, &bound)? else {
        return Ok(none);
    };
    let read = read_offer(conn, selection.offer, &selection.types).map_err(ReadFail::message)?;
    Ok(Got { clip: read.op, paths: read.paths, token: read.token, skipped: read.skipped })
}

pub fn get() -> Result<Got, String> {
    let mut conn = Conn::connect()?;
    get_on(&mut conn)
}

// Clear only when the selection still carries this token; a newer copy is never wiped.
pub fn clear_on(conn: &mut Conn, token: &str) -> Result<bool, String> {
    let bound = handshake(conn)?;
    let Some(selection) = read_selection(conn, &bound)? else {
        return Ok(false);
    };
    if !selection.types.iter().any(|t| t == format::FLEA) {
        return Ok(false);
    }
    let bytes = receive_type(conn, selection.offer, format::FLEA)?;
    let own = match format::parse_flea(&bytes) {
        Some((_, own)) => own,
        None => return Ok(false),
    };
    if own != token {
        return Ok(false);
    }
    null_selection(conn)
}

pub fn clear(token: &str) -> Result<bool, String> {
    let mut conn = Conn::connect()?;
    clear_on(&mut conn, token)
}

// A spent cut from another application: clear only when the selection is still a cut
// whose paths equal these exactly, same order. A copy is never cleared, whatever it holds.
pub fn clear_cut_on(conn: &mut Conn, wanted: &[String]) -> Result<bool, String> {
    let bound = handshake(conn)?;
    let Some(selection) = read_selection(conn, &bound)? else {
        return Ok(false);
    };
    let read = read_offer(conn, selection.offer, &selection.types).map_err(ReadFail::message)?;
    if read.op != "cut" || read.paths.is_empty() || read.paths != wanted {
        return Ok(false);
    }
    null_selection(conn)
}

pub fn clear_cut(wanted: &[String]) -> Result<bool, String> {
    let mut conn = Conn::connect()?;
    clear_cut_on(&mut conn, wanted)
}

// Set no source, then one round trip so the compositor has taken it before we answer.
fn null_selection(conn: &mut Conn) -> Result<bool, String> {
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, 0);
    conn.send(6, DEVICE_SET_SELECTION, &payload, &[])?;
    payload.clear();
    wire::put_u32(&mut payload, 7);
    conn.send(1, DISPLAY_SYNC, &payload, &[])?;
    loop {
        let event = conn.next_raw(ROUNDTRIP_MS)?.ok_or_else(|| "the compositor closed the connection".to_string())?;
        if let Some(failure) = check_error(&event) {
            return Err(failure);
        }
        if event.sender == 7 && event.opcode == 0 {
            return Ok(true);
        }
    }
}

#[cfg(test)]
#[path = "control_tests.rs"]
mod tests;
