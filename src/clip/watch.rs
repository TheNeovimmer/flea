// The clipboard watcher: one thread, one device, a changed line per file selection; primary_selection never moves it.
use super::control::{check_error, handshake, read_offer, ReadFail};
use super::wire::{self, Conn};
use super::protocol::*;
use crate::backend::opsreq::OpMsg;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::mpsc::Sender;
use std::time::Duration;

// A dropped connection reconnects at most RETRIES times, RETRY_EVERY apart.
const RETRIES: usize = 5;
const RETRY_EVERY: Duration = Duration::from_secs(1);

// What dedup compares: a repeated identical selection emits once.
type Key = (String, String, Vec<String>);

// One watcher thread per backend; the flag in State keeps clipWatch idempotent.
pub fn request_watch(replies: Sender<OpMsg>) {
    std::thread::spawn(move || watch_loop(replies, None, RETRY_EVERY));
}

// The retry delay is a parameter so a test reconnects at once instead of waiting a second.
fn watch_loop(replies: Sender<OpMsg>, socket: Option<PathBuf>, retry_every: Duration) {
    let mut last: Option<Key> = None;
    // The first connection never retries: no compositor or no manager is one line and the end.
    match connect_and_watch(&replies, &mut last, &socket) {
        Ok(WatchEnd::Dropped) => {}
        Err(e) => {
            say(&replies, &none_error(&e));
            return;
        }
    }
    for _ in 0..RETRIES {
        std::thread::sleep(retry_every);
        match connect_and_watch(&replies, &mut last, &socket) {
            Ok(WatchEnd::Dropped) => {}
            Err(_) => {}
        }
    }
    say(&replies, &none_error("the clipboard connection was lost"));
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
    Dropped,
}

// Reports selections until the connection drops; only the initial handshake is an Err.
fn connect_and_watch(replies: &Sender<OpMsg>, last: &mut Option<Key>, socket: &Option<PathBuf>) -> Result<WatchEnd, String> {
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
    loop {
        let event = match conn.next_raw(super::owner::WAIT_FOREVER) {
            Ok(Some(event)) => event,
            Ok(None) | Err(_) => return Ok(WatchEnd::Dropped),
        };
        if check_error(&event).is_some() {
            return Ok(WatchEnd::Dropped);
        }
        if event.sender == READER_DEVICE && event.opcode == DEVICE_DATA_OFFER {
            let mut at = 0;
            if let Some(id) = wire::get_u32(&event.body, &mut at) {
                offers.insert(id, Vec::new());
            }
        } else if event.sender == READER_DEVICE && event.opcode == DEVICE_SELECTION {
            let mut at = 0;
            let current = match wire::get_u32(&event.body, &mut at) {
                Some(id) if id != 0 => Some(id),
                _ => None,
            };
            // Every highlight would otherwise leak one entry per window for its lifetime.
            retire_offers(&mut conn, &mut offers, current);
            match current {
                None => emit(replies, last, "none", &[], "", 0),
                Some(id) => match offers.get(&id) {
                    // An offer the selection names before its types is out of order, read as nothing.
                    None => emit(replies, last, "none", &[], "", 0),
                    Some(types) => match read_offer(&mut conn, id, types) {
                        // An over-cap selection is refused out loud, never broadcast to every window.
                        Err(ReadFail::Capped(e)) => say(replies, &none_error(&e)),
                        Ok(read) => emit(replies, last, &read.op, &read.paths, &read.token, read.skipped),
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

fn emit(replies: &Sender<OpMsg>, last: &mut Option<Key>, op: &str, paths: &[String], token: &str, skipped: usize) {
    let key = (op.to_string(), token.to_string(), paths.to_vec());
    if last.as_ref() == Some(&key) {
        return;
    }
    *last = Some(key);
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
