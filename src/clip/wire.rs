// The Wayland wire: framing, strings and a connection holding queued descriptors.
// Header word 1 is the object id; word 2 is (size << 16) | opcode, size with the header.
use crate::backend::fdpass;
use std::collections::VecDeque;
use std::os::fd::{AsRawFd, OwnedFd, RawFd};
use std::os::raw::c_int;
use std::path::PathBuf;

// The two clipboard managers, tried in this order; see control.rs for the version choice.
pub const EXT_MANAGER: &str = "ext_data_control_manager_v1";
pub const ZWLR_MANAGER: &str = "zwlr_data_control_manager_v1";

// Where the compositor listens: $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY, or WAYLAND_DISPLAY as is.
pub fn socket_path() -> Result<PathBuf, String> {
    let display = std::env::var_os("WAYLAND_DISPLAY")
        .ok_or_else(|| "WAYLAND_DISPLAY is not set, so there is no clipboard to use".to_string())?;
    let display = PathBuf::from(display);
    if display.is_absolute() {
        return Ok(display);
    }
    let dir = std::env::var_os("XDG_RUNTIME_DIR")
        .ok_or_else(|| "XDG_RUNTIME_DIR is not set, so the display socket cannot be found".to_string())?;
    Ok(PathBuf::from(dir).join(display))
}

pub fn put_u32(out: &mut Vec<u8>, v: u32) {
    out.extend_from_slice(&v.to_ne_bytes());
}

// A string is its length with the NUL, the bytes, the NUL, then zero padding to 4.
pub fn put_string(out: &mut Vec<u8>, s: &str) {
    put_u32(out, (s.len() + 1) as u32);
    out.extend_from_slice(s.as_bytes());
    out.push(0);
    while out.len() % 4 != 0 {
        out.push(0);
    }
}

// A null string is a zero length and no bytes at all.
#[cfg_attr(not(test), allow(dead_code))]
pub fn put_null_string(out: &mut Vec<u8>) {
    put_u32(out, 0);
}

// One request: the 8-byte header ahead of the payload, host byte order.
pub fn request(obj: u32, opcode: u16, payload: &[u8]) -> Vec<u8> {
    let size = (8 + payload.len()) as u32;
    let mut out = Vec::with_capacity(8 + payload.len());
    put_u32(&mut out, obj);
    put_u32(&mut out, (size << 16) | opcode as u32);
    out.extend_from_slice(payload);
    out
}

pub fn get_u32(body: &[u8], at: &mut usize) -> Option<u32> {
    let end = (*at).checked_add(4)?;
    let word: [u8; 4] = body.get(*at..end)?.try_into().ok()?;
    *at = end;
    Some(u32::from_ne_bytes(word))
}

// None on truncation or a missing terminator; a null string reads as empty.
pub fn get_string(body: &[u8], at: &mut usize) -> Option<String> {
    let len = get_u32(body, at)? as usize;
    if len == 0 {
        return Some(String::new());
    }
    let end = (*at).checked_add(len)?;
    let bytes = body.get(*at..end)?;
    if bytes.last() != Some(&0) {
        return None;
    }
    *at = end + (4 - (len % 4)) % 4;
    Some(String::from_utf8_lossy(&bytes[..len - 1]).into_owned())
}

// The largest message this client accepts; a lying size would otherwise grow the
// buffer without bound waiting for bytes that never arrive.
pub const MAX_MESSAGE: usize = 64 * 1024 * 1024;

// One decoded event: who sent it, which one it is, and the body after the header.
pub struct RawEvent {
    pub sender: u32,
    pub opcode: u16,
    pub body: Vec<u8>,
}

#[repr(C)]
struct PollFd {
    fd: c_int,
    events: i16,
    revents: i16,
}

const POLLIN: i16 = 1;

extern "C" {
    fn poll(fds: *mut PollFd, nfds: usize, timeout: c_int) -> c_int;
}

// A connection: the socket, unread bytes, and descriptors waiting for their event.
// A body and its descriptor can arrive in either order, so the two queue apart.
pub struct Conn {
    sock: OwnedFd,
    buf: Vec<u8>,
    fds: VecDeque<OwnedFd>,
}

impl Conn {
    pub fn connect() -> Result<Conn, String> {
        Self::connect_to(&socket_path()?)
    }

    pub fn connect_to(path: &std::path::Path) -> Result<Conn, String> {
        let addr = std::os::unix::net::SocketAddr::from_pathname(path)
            .map_err(|e| format!("the display socket {} cannot be used ({})", path.display(), e))?;
        let sock = std::os::unix::net::UnixStream::connect_addr(&addr)
            .map_err(|e| format!("the compositor at {} did not answer ({})", path.display(), e))?;
        Ok(Conn { sock: OwnedFd::from(sock), buf: Vec::new(), fds: VecDeque::new() })
    }

    // A test seam: a connection over an already open socket, never the display.
    #[cfg(test)]
    pub fn over(sock: OwnedFd) -> Conn {
        Conn { sock, buf: Vec::new(), fds: VecDeque::new() }
    }

    pub fn send(&mut self, obj: u32, opcode: u16, payload: &[u8], fds: &[RawFd]) -> Result<(), String> {
        let bytes = request(obj, opcode, payload);
        fdpass::send_stream(self.sock.as_raw_fd(), &bytes, fds)
            .map_err(|e| format!("a clipboard request could not be sent ({})", e))
    }

    fn readable(&mut self, timeout_ms: u32) -> Result<bool, String> {
        let mut p = PollFd { fd: self.sock.as_raw_fd(), events: POLLIN, revents: 0 };
        let n = unsafe { poll(&mut p, 1, timeout_ms as c_int) };
        if n < 0 {
            return Err(format!("waiting for the compositor failed ({})", std::io::Error::last_os_error()));
        }
        Ok(n > 0)
    }

    fn fill(&mut self, timeout_ms: u32) -> Result<bool, String> {
        if !self.readable(timeout_ms)? {
            return Ok(false);
        }
        match fdpass::recv_stream(self.sock.as_raw_fd())
            .map_err(|e| format!("a clipboard reply could not be read ({})", e))?
        {
            None => Ok(false),
            Some((bytes, fds)) => {
                self.buf.extend_from_slice(&bytes);
                self.fds.extend(fds);
                Ok(true)
            }
        }
    }

    // The next event, skipping nothing: unknown ones are skipped by size by the caller.
    pub fn next_raw(&mut self, timeout_ms: u32) -> Result<Option<RawEvent>, String> {
        loop {
            if self.buf.len() >= 8 {
                let sender = u32::from_ne_bytes(self.buf[0..4].try_into().unwrap());
                let word = u32::from_ne_bytes(self.buf[4..8].try_into().unwrap());
                let size = (word >> 16) as usize;
                let opcode = (word & 0xffff) as u16;
                if !(8..=MAX_MESSAGE).contains(&size) {
                    return Err("the compositor sent a message this client will not hold".to_string());
                }
                if self.buf.len() >= size {
                    let body = self.buf[8..size].to_vec();
                    self.buf.drain(..size);
                    return Ok(Some(RawEvent { sender, opcode, body }));
                }
            }
            if !self.fill(timeout_ms)? {
                if self.buf.is_empty() {
                    return Ok(None);
                }
                return Err("the compositor closed the connection mid-message".to_string());
            }
        }
    }

    // A descriptor whose body already arrived, waiting for its own recvmsg to land.
    pub fn take_fd(&mut self, timeout_ms: u32) -> Result<Option<OwnedFd>, String> {
        loop {
            if let Some(fd) = self.fds.pop_front() {
                return Ok(Some(fd));
            }
            if !self.fill(timeout_ms)? {
                return Ok(None);
            }
        }
    }
}

#[cfg(test)]
#[path = "wire_tests.rs"]
mod tests;
