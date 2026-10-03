// The data-control reader: handshake, reading the selection and clearing it (owning is owner.rs).
use super::format;
use super::reply::Got;
use super::wire::{self, Conn, RawEvent};
use super::protocol::*;
pub use super::receive::receive_type;

// Each compositor round trip is bounded independently of a foreign source's read.
pub(crate) const ROUNDTRIP_MS: u32 = 5000;

#[derive(Debug)]
pub struct Bound {
    pub seat: u32,
    pub manager: u32,
    #[cfg_attr(not(test), allow(dead_code))]
    pub ext: bool,
}

// A wl_display.error names its failing object, code and message; it always fails the call.
pub(crate) fn check_error(event: &RawEvent) -> Option<String> {
    if event.sender != DISPLAY || event.opcode != DISPLAY_ERROR {
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
    wire::put_u32(&mut payload, REGISTRY);
    conn.send(DISPLAY, DISPLAY_GET_REGISTRY, &payload, &[])?;
    payload.clear();
    wire::put_u32(&mut payload, GLOBALS_CALLBACK);
    conn.send(DISPLAY, DISPLAY_SYNC, &payload, &[])?;
    let mut globals = Globals { seat: None, ext: None, zwlr: None };
    loop {
        let event = conn.next_raw(ROUNDTRIP_MS)?.ok_or_else(|| "the compositor closed the connection".to_string())?;
        if let Some(failure) = check_error(&event) {
            return Err(failure);
        }
        if event.sender == GLOBALS_CALLBACK && event.opcode == CALLBACK_DONE {
            break;
        }
        if event.sender == REGISTRY && event.opcode == REGISTRY_GLOBAL {
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
    wire::put_u32(&mut payload, SEAT_VERSION);
    wire::put_u32(&mut payload, SEAT);
    conn.send(REGISTRY, REGISTRY_BIND, &payload, &[])?;
    payload.clear();
    if let Some(name) = globals.ext {
        wire::put_u32(&mut payload, name);
        wire::put_string(&mut payload, wire::EXT_MANAGER);
        wire::put_u32(&mut payload, EXT_MANAGER_VERSION);
        wire::put_u32(&mut payload, MANAGER);
        conn.send(REGISTRY, REGISTRY_BIND, &payload, &[])?;
        return Ok(Bound { seat: SEAT, manager: MANAGER, ext: true });
    }
    let (name, version) = globals.zwlr.ok_or_else(|| "no clipboard protocol: neither data-control manager is offered".to_string())?;
    wire::put_u32(&mut payload, name);
    wire::put_string(&mut payload, wire::ZWLR_MANAGER);
    wire::put_u32(&mut payload, version.min(ZWLR_MAX_VERSION));
    wire::put_u32(&mut payload, MANAGER);
    conn.send(REGISTRY, REGISTRY_BIND, &payload, &[])?;
    Ok(Bound { seat: SEAT, manager: MANAGER, ext: false })
}

pub struct Selection {
    pub offer: u32,
    pub types: Vec<String>,
}

// After get_data_device the compositor sends the current selection at once; the sync collects it.
pub fn read_selection(conn: &mut Conn, bound: &Bound) -> Result<Option<Selection>, String> {
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, READER_DEVICE);
    wire::put_u32(&mut payload, bound.seat);
    conn.send(bound.manager, MANAGER_GET_DEVICE, &payload, &[])?;
    payload.clear();
    wire::put_u32(&mut payload, READER_CALLBACK);
    conn.send(DISPLAY, DISPLAY_SYNC, &payload, &[])?;
    let mut offers: Vec<(u32, Vec<String>)> = Vec::new();
    let mut selected: Option<u32> = None;
    loop {
        let event = conn.next_raw(ROUNDTRIP_MS)?.ok_or_else(|| "the compositor closed the connection".to_string())?;
        if let Some(failure) = check_error(&event) {
            return Err(failure);
        }
        if event.sender == READER_CALLBACK && event.opcode == CALLBACK_DONE {
            break;
        }
        if event.sender == READER_DEVICE && event.opcode == DEVICE_DATA_OFFER {
            let mut at = 0;
            if let Some(id) = wire::get_u32(&event.body, &mut at) {
                offers.push((id, Vec::new()));
            }
            continue;
        }
        if event.sender == READER_DEVICE && event.opcode == DEVICE_SELECTION {
            let mut at = 0;
            selected = wire::get_u32(&event.body, &mut at);
            continue;
        }
        if event.opcode == OFFER_TYPE {
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

// One offer read as files for get and the watcher: our token, GNOME's shape, then the uri-list, each falling through.
pub(crate) struct OfferFiles {
    pub op: String,
    pub paths: Vec<String>,
    pub token: String,
    pub skipped: usize,
    pub owner_pid: Option<u32>,
}

// A refused read is a selection past the path cap; any failed receive falls through instead.
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
    read_offer_with(conn, offer, types, receive_type)
}

fn read_offer_with(conn: &mut Conn, offer: u32, types: &[String],
    mut receive: impl FnMut(&mut Conn, u32, &str) -> Result<Vec<u8>, String>) -> Result<OfferFiles, ReadFail> {
    let none = OfferFiles { op: "none".to_string(), paths: Vec::new(), token: String::new(), skipped: 0, owner_pid: None };
    let has = |mime: &str| types.iter().any(|t| t == mime);
    if has(format::FLEA) {
        if let Ok(bytes) = receive(conn, offer, format::FLEA) {
            if let Some((op, token)) = format::parse_flea(&bytes) {
                let mut got = OfferFiles { op, paths: Vec::new(), token, skipped: 0, owner_pid: format::flea_pid(&bytes) };
                // The token names our own copy; the paths still come from a file shape beside it.
                if has(format::GNOME) {
                    if let Ok(bytes) = receive(conn, offer, format::GNOME) {
                        if let Some((_, paths, skipped)) = format::parse_gnome(&bytes) {
                            format::check_path_cap(&paths).map_err(ReadFail::Capped)?;
                            got.paths = paths;
                            got.skipped = skipped;
                        }
                    }
                }
                if got.paths.is_empty() && has(format::URILIST) {
                    if let Ok(bytes) = receive(conn, offer, format::URILIST) {
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
        if let Ok(bytes) = receive(conn, offer, format::GNOME) {
            if let Some((op, paths, skipped)) = format::parse_gnome(&bytes) {
                if !paths.is_empty() {
                    format::check_path_cap(&paths).map_err(ReadFail::Capped)?;
                    return Ok(OfferFiles { op, paths, token: String::new(), skipped, owner_pid: None });
                }
            }
        }
    }
    if has(format::URILIST) {
        if let Ok(bytes) = receive(conn, offer, format::URILIST) {
            let (paths, skipped) = format::parse_urilist(&bytes);
            if !paths.is_empty() {
                format::check_path_cap(&paths).map_err(ReadFail::Capped)?;
                let mut op = "copy".to_string();
                if has(format::KDE_CUT) {
                    if let Ok(cut) = receive(conn, offer, format::KDE_CUT) {
                        if format::parse_kde_cut(&cut) {
                            op = "cut".to_string();
                        }
                    }
                }
                return Ok(OfferFiles { op, paths, token: String::new(), skipped, owner_pid: None });
            }
        }
    }
    Ok(none)
}

// The current selection as files: our own token first, then GNOME's shape, then the uri-list.
pub fn get_on(conn: &mut Conn) -> Result<Got, String> {
    get_on_with(conn, receive_type)
}

// The owner-exit reader retains the pid beside the same get handshake and offer parser.
pub(crate) fn get_files_on(conn: &mut Conn) -> Result<OfferFiles, String> {
    let mut failed = None;
    let read = get_files_with(conn, |conn, offer, mime| {
        let result = receive_type(conn, offer, mime);
        if let Err(error) = &result { failed = Some(error.clone()); }
        result
    })?;
    if let Some(error) = failed {
        return Err(error);
    }
    Ok(read)
}

fn get_on_with(conn: &mut Conn, receive: impl FnMut(&mut Conn, u32, &str) -> Result<Vec<u8>, String>) -> Result<Got, String> {
    let read = get_files_with(conn, receive)?;
    Ok(Got { clip: read.op, paths: read.paths, token: read.token, skipped: read.skipped })
}

fn get_files_with(conn: &mut Conn, receive: impl FnMut(&mut Conn, u32, &str) -> Result<Vec<u8>, String>) -> Result<OfferFiles, String> {
    let bound = handshake(conn)?;
    let none = OfferFiles { op: "none".to_string(), paths: Vec::new(), token: String::new(), skipped: 0, owner_pid: None };
    let Some(selection) = read_selection(conn, &bound)? else {
        return Ok(none);
    };
    read_offer_with(conn, selection.offer, &selection.types, receive).map_err(ReadFail::message)
}

pub fn get() -> Result<Got, String> {
    let mut conn = Conn::connect()?;
    get_on(&mut conn)
}

// Verify the token and drain queued replacements; a later copy can still race the null request.
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
    null_selection_if_current(conn, selection.offer)
}

pub fn clear(token: &str) -> Result<bool, String> {
    let mut conn = Conn::connect()?;
    clear_on(&mut conn, token)
}

// A spent cut from another application clears only while the selection is still a cut of exactly these paths.
pub fn clear_cut_on(conn: &mut Conn, wanted: &[String]) -> Result<bool, String> {
    let bound = handshake(conn)?;
    let Some(selection) = read_selection(conn, &bound)? else {
        return Ok(false);
    };
    let read = read_offer(conn, selection.offer, &selection.types).map_err(ReadFail::message)?;
    if read.op != "cut" || read.paths.is_empty() || read.paths != wanted {
        return Ok(false);
    }
    null_selection_if_current(conn, selection.offer)
}

pub fn clear_cut(wanted: &[String]) -> Result<bool, String> {
    let mut conn = Conn::connect()?;
    clear_cut_on(&mut conn, wanted)
}

// Drain queued selections before clearing; the protocol has no atomic compare-and-clear.
fn null_selection_if_current(conn: &mut Conn, verified: u32) -> Result<bool, String> {
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, READER_CALLBACK);
    conn.send(DISPLAY, DISPLAY_SYNC, &payload, &[])?;
    let mut current = Some(verified);
    loop {
        let event = conn.next_raw(ROUNDTRIP_MS)?.ok_or_else(|| "the compositor closed the connection".to_string())?;
        if let Some(failure) = check_error(&event) {
            return Err(failure);
        }
        if event.sender == READER_DEVICE && event.opcode == DEVICE_SELECTION {
            let mut at = 0;
            current = wire::get_u32(&event.body, &mut at);
        }
        if event.sender == READER_CALLBACK && event.opcode == CALLBACK_DONE {
            return if current == Some(verified) { null_selection(conn) } else { Ok(false) };
        }
    }
}

// Set no source, then one round trip so the compositor has taken it before we answer.
fn null_selection(conn: &mut Conn) -> Result<bool, String> {
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, 0);
    conn.send(READER_DEVICE, DEVICE_SET_SELECTION, &payload, &[])?;
    payload.clear();
    wire::put_u32(&mut payload, READER_CALLBACK);
    conn.send(DISPLAY, DISPLAY_SYNC, &payload, &[])?;
    loop {
        let event = conn.next_raw(ROUNDTRIP_MS)?.ok_or_else(|| "the compositor closed the connection".to_string())?;
        if let Some(failure) = check_error(&event) {
            return Err(failure);
        }
        if event.sender == READER_CALLBACK && event.opcode == CALLBACK_DONE {
            return Ok(true);
        }
    }
}

#[cfg(test)]
#[path = "control_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "clear_tests.rs"]
mod clear_tests;
