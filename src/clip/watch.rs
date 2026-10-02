// The clipboard watcher: one thread holds one connection and one device, blocks in
// recv, and emits a changed line per file selection. Only selection events (never
// primary_selection) move it. A dropped connection reconnects at most once a second,
// at most 5 times; backend exit ends the thread with the process.
use super::control::{check_error, handshake, read_offer, ReadFail, MANAGER_GET_DEVICE};
use super::wire::{self, Conn};
use crate::backend::opsreq::OpMsg;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::mpsc::Sender;
use std::time::Duration;

const RETRIES: usize = 5;
const RETRY_EVERY: Duration = Duration::from_secs(1);

// What dedup compares: a repeated identical selection emits once.
type Key = (String, String, Vec<String>);

// One watcher thread per backend; the flag in State keeps clipWatch idempotent.
pub fn request_watch(replies: Sender<OpMsg>) {
    std::thread::spawn(move || watch_loop(replies, None));
}

fn watch_loop(replies: Sender<OpMsg>, socket: Option<PathBuf>) {
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
        std::thread::sleep(RETRY_EVERY);
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

// Connect, take a device, and report selections until the connection drops. Only the
// initial handshake fails as an Err; everything after the device exists is a drop.
fn connect_and_watch(replies: &Sender<OpMsg>, last: &mut Option<Key>, socket: &Option<PathBuf>) -> Result<WatchEnd, String> {
    let mut conn = match socket {
        Some(path) => Conn::connect_to(path)?,
        None => Conn::connect()?,
    };
    let bound = handshake(&mut conn)?;
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, 6);
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
        if event.sender == 6 && event.opcode == 0 {
            let mut at = 0;
            if let Some(id) = wire::get_u32(&event.body, &mut at) {
                offers.insert(id, Vec::new());
            }
        } else if event.sender == 6 && (event.opcode == 1 || event.opcode == 3) {
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
                    // The types arrive ahead of the selection naming them; an unknown
                    // offer is a compositor speaking out of order, read as nothing.
                    None => emit(replies, last, "none", &[], "", 0),
                    Some(types) => match read_offer(&mut conn, id, types) {
                        // A failed receive skips its selection, never the watch; an over-cap
                        // one is refused out loud instead of broadcast to every window.
                        Err(ReadFail::Capped(e)) => say(replies, &none_error(&e)),
                        Ok(read) => emit(replies, last, &read.op, &read.paths, &read.token, read.skipped),
                    },
                },
            }
        } else if event.opcode == 0 {
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

// Destroy every tracked offer that is no longer current, primary selections included:
// a compositor object per highlight would otherwise live for the window's lifetime.
pub(crate) fn retire_offers(conn: &mut Conn, offers: &mut HashMap<u32, Vec<String>>, current: Option<u32>) {
    let mut kept = None;
    for (id, types) in std::mem::take(offers) {
        if Some(id) == current {
            kept = Some((id, types));
        } else {
            let _ = conn.send(id, 1, &[], &[]);
        }
    }
    if let Some((id, types)) = kept {
        offers.insert(id, types);
    }
}

#[cfg(test)]
#[path = "watch_tests.rs"]
mod tests;
