// The clipboard watcher: one thread, one device, a changed line per file selection; primary_selection never moves it.
use super::control::{check_error, handshake, read_offer, ReadFail};
use super::wire::{self, Conn};
use super::protocol::*;
use crate::backend::opsreq::OpMsg;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};
use std::time::Duration;

// A dropped connection reconnects at most RETRIES times, RETRY_EVERY apart.
const RETRIES: usize = 5;
const RETRY_EVERY: Duration = Duration::from_secs(1);

// What dedup compares: a repeated identical selection emits once.
type Key = (String, String, Vec<String>);

#[derive(Default)]
pub(crate) struct Reported {
    last: Option<Key>,
    generation: u64,
    event_sequence: u64,
}

pub(crate) type Shared = Arc<Mutex<Reported>>;

pub(crate) fn shared() -> Shared {
    Arc::new(Mutex::new(Reported::default()))
}

// One watcher thread per backend; the flag in State keeps clipWatch idempotent.
pub(crate) fn request_watch(replies: Sender<OpMsg>, state: Shared) {
    std::thread::spawn(move || watch_loop(replies, state, None, RETRY_EVERY));
}

// The retry delay is a parameter so a test reconnects at once instead of waiting a second.
fn watch_loop(replies: Sender<OpMsg>, state: Shared, socket: Option<PathBuf>, retry_every: Duration) {
    // The first connection never retries: no compositor or no manager is one line and the end.
    let mut cause = match connect_and_watch(&replies, &state, &socket) {
        Ok(WatchEnd::Dropped(cause)) => cause,
        Err(e) => {
            emit_error(&replies, &state, &e);
            return;
        }
    };
    for _ in 0..RETRIES {
        std::thread::sleep(retry_every);
        cause = match connect_and_watch(&replies, &state, &socket) {
            Ok(WatchEnd::Dropped(cause)) | Err(cause) => cause,
        };
    }
    emit_error(&replies, &state, &format!("the clipboard connection was lost: {}", cause));
}

fn say(replies: &Sender<OpMsg>, line: &str) {
    let _ = replies.send(OpMsg::Meta { line: line.to_string() });
}

fn none_error(e: &str) -> String {
    format!(r#"{{"t":"clip","op":"changed","clip":"none","paths":[],"token":"","skipped":0,"error":"{}"}}"#,
        crate::json::escape(e))
}

// Changed lines carry no ok field: the selection is what it is, and an error rides beside none.
fn changed(op: &str, paths: &[String], token: &str, skipped: usize) -> String {
    let mut out = format!(r#"{{"t":"clip","op":"changed","clip":"{}","paths":["#, crate::json::escape(op));
    for (i, p) in paths.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push('"');
        out.push_str(&crate::json::escape(p));
        out.push('"');
    }
    out.push_str(&format!(r#"],"token":"{}","skipped":{}}}"#, crate::json::escape(token), skipped));
    out
}

enum WatchEnd {
    Dropped(String),
}

// Reports selections until the connection drops; only the initial handshake is an Err.
fn connect_and_watch(replies: &Sender<OpMsg>, state: &Shared, socket: &Option<PathBuf>) -> Result<WatchEnd, String> {
    let mut conn = match socket {
        Some(path) => Conn::connect_to(path)?,
        None => Conn::connect()?,
    };
    let bound = handshake(&mut conn)?;
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, READER_DEVICE);
    wire::put_u32(&mut payload, bound.seat);
    conn.send(bound.manager, MANAGER_GET_DEVICE, &payload, &[])?;
    let mut offers: HashMap<u32, Vec<String>> = HashMap::new();
    let mut ended = super::end::OwnerEnd::new(replies.clone(), state.clone(), socket.clone());
    loop {
        let event = match conn.next_raw(super::owner::WAIT_FOREVER) {
            Ok(Some(event)) => event,
            Ok(None) => return Ok(WatchEnd::Dropped("the compositor closed the connection".to_string())),
            Err(e) => return Ok(WatchEnd::Dropped(e)),
        };
        if let Some(e) = check_error(&event) {
            return Ok(WatchEnd::Dropped(e));
        }
        if event.sender == READER_DEVICE && event.opcode == DEVICE_DATA_OFFER {
            let mut at = 0;
            if let Some(id) = wire::get_u32(&event.body, &mut at) {
                offers.insert(id, Vec::new());
            }
        } else if event.sender == READER_DEVICE && event.opcode == DEVICE_SELECTION {
            let generation = {
                let mut reported = state.lock().unwrap_or_else(|e| e.into_inner());
                reported.event_sequence += 1;
                reported.generation
            };
            let mut at = 0;
            let current = match wire::get_u32(&event.body, &mut at) {
                Some(id) if id != 0 => Some(id),
                _ => None,
            };
            // Every highlight would otherwise leak one entry per window for its lifetime.
            retire_offers(&mut conn, &mut offers, current);
            match current {
                None => {
                    ended.track(None, "");
                    emit(replies, state, "none", &[], "", 0);
                },
                Some(id) => match offers.get(&id) {
                    // An offer the selection names before its types is out of order, read as nothing.
                    None => {
                        ended.track(None, "");
                        emit(replies, state, "none", &[], "", 0);
                    },
                    Some(types) => {
                        let read = read_offer(&mut conn, id, types);
                        let mut reported = state.lock().unwrap_or_else(|e| e.into_inner());
                        // Only an exit read begun after this event can report and invalidate its bytes.
                        if reported.generation != generation { continue; }
                        match read {
                            // An over-cap selection is refused out loud, never broadcast to every window.
                            Err(ReadFail::Capped(e)) => {
                                ended.track(None, "");
                                emit_error_locked(replies, &mut reported, &e);
                            }
                            Ok(read) => {
                                if !ended.tracks(&read.token) {
                                    ended.track(read.owner_pid, &read.token);
                                }
                                emit_locked(replies, &mut reported, &read.op, &read.paths, &read.token, read.skipped);
                            }
                        }
                    },
                },
            }
        } else if event.sender == READER_DEVICE && event.opcode == DEVICE_PRIMARY_SELECTION {
            let mut at = 0;
            if let Some(id) = wire::get_u32(&event.body, &mut at) {
                if offers.remove(&id).is_some() {
                    let _ = conn.send(id, OFFER_DESTROY, &[], &[]);
                }
            }
        } else if event.opcode == OFFER_TYPE {
            if let Some(types) = offers.get_mut(&event.sender) {
                let mut at = 0;
                if let Some(mime) = wire::get_string(&event.body, &mut at) {
                    types.push(mime);
                }
            }
        }
    }
}

// Token and event guards share the emitter lock, so newer selections win before their bytes arrive.
pub(super) fn reread(replies: &Sender<OpMsg>, state: &Shared, token: &str,
    read: impl FnOnce() -> Result<super::control::OfferFiles, String>,
    cancelled: impl Fn() -> bool, track: impl FnOnce(&super::control::OfferFiles)) -> bool {
    let current = |state: &Reported| state.last.as_ref().map(|key| key.1.as_str()) == Some(token);
    let event_sequence = {
        let state = state.lock().unwrap_or_else(|e| e.into_inner());
        if cancelled() || !current(&state) { return false; }
        state.event_sequence
    };
    let Ok(read) = read() else { return false; };
    let mut state = state.lock().unwrap_or_else(|e| e.into_inner());
    if cancelled() || !current(&state) || state.event_sequence != event_sequence { return false; }
    if read.token == token { return true; }
    let key = (read.op.clone(), read.token.clone(), read.paths.clone());
    if state.last.as_ref() != Some(&key) {
        track(&read);
        emit_locked(replies, &mut state, &read.op, &read.paths, &read.token, read.skipped);
    }
    true
}

fn emit_error(replies: &Sender<OpMsg>, state: &Shared, error: &str) {
    let mut state = state.lock().unwrap_or_else(|e| e.into_inner());
    emit_error_locked(replies, &mut state, error);
}

fn emit_error_locked(replies: &Sender<OpMsg>, state: &mut Reported, error: &str) {
    state.generation += 1;
    state.last = None;
    say(replies, &none_error(error));
}

fn emit(replies: &Sender<OpMsg>, state: &Shared, op: &str, paths: &[String], token: &str, skipped: usize) {
    let mut state = state.lock().unwrap_or_else(|e| e.into_inner());
    emit_locked(replies, &mut state, op, paths, token, skipped);
}

fn emit_locked(replies: &Sender<OpMsg>, state: &mut Reported, op: &str, paths: &[String], token: &str, skipped: usize) {
    let key = (op.to_string(), token.to_string(), paths.to_vec());
    if state.last.as_ref() == Some(&key) {
        return;
    }
    state.generation += 1;
    state.last = Some(key);
    say(replies, &changed(op, paths, token, skipped));
}

// Destroys every tracked offer that is no longer current, or each highlight's object would live for the window.
pub(crate) fn retire_offers(conn: &mut Conn, offers: &mut HashMap<u32, Vec<String>>, current: Option<u32>) {
    let mut kept = None;
    for (id, types) in std::mem::take(offers) {
        if Some(id) == current {
            kept = Some((id, types));
        } else {
            let _ = conn.send(id, OFFER_DESTROY, &[], &[]);
        }
    }
    if let Some((id, types)) = kept {
        offers.insert(id, types);
    }
}

#[cfg(test)]
#[path = "watch_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "watch_owner_tests.rs"]
mod owner_tests;
