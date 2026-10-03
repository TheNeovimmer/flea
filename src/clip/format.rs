// The clipboard formats, one place: every offered type is built and parsed here.
use std::collections::HashSet;

pub const GNOME: &str = "x-special/gnome-copied-files";
pub const URILIST: &str = "text/uri-list";
pub const KDE_CUT: &str = "application/x-kde-cutselection";
pub const PLAIN_UTF8: &str = "text/plain;charset=utf-8";
pub const PLAIN: &str = "text/plain";
pub const UTF8_STRING: &str = "UTF8_STRING";
// Tokens encode 16 random bytes as two hex digits each.
pub(crate) const TOKEN_BYTES: usize = 16;
pub(crate) const TOKEN_HEX_LEN: usize = TOKEN_BYTES * 2;

pub const FLEA: &str = "application/x-flea-clip";

// Every type an owner offers, in the order the bytes are served; KDE only on a cut.
pub fn offered(op: &str) -> Vec<&'static str> {
    let mut out = vec![FLEA, GNOME, URILIST, PLAIN_UTF8, PLAIN, UTF8_STRING];
    if op == "cut" {
        out.push(KDE_CUT);
    }
    out
}

pub fn is_op(s: &str) -> bool {
    s == "copy" || s == "cut"
}

// A path as a file:// URI: every byte outside the unreserved set and '/' is percent-encoded.
pub fn encode_uri(path: &str) -> String {
    let mut out = String::from("file://");
    for b in path.as_bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~' | b'/') {
            out.push(*b as char);
        } else {
            out.push_str(&format!("%{:02X}", b));
        }
    }
    out
}

// Only file:// with an empty or localhost host becomes a path; anything else is refused.
pub fn decode_uri(uri: &[u8]) -> Option<String> {
    let rest = uri.strip_prefix(b"file://")?;
    let slash = rest.iter().position(|b| *b == b'/')?;
    let (host, path) = rest.split_at(slash);
    if !host.is_empty() && host != b"localhost" {
        return None;
    }
    let mut raw = Vec::with_capacity(path.len());
    let mut i = 0;
    while i < path.len() {
        if path[i] == b'%' {
            let hex = path.get(i + 1..i + 3)?;
            let byte = u8::from_str_radix(std::str::from_utf8(hex).ok()?, 16).ok()?;
            raw.push(byte);
            i += 3;
        } else {
            raw.push(path[i]);
            i += 1;
        }
    }
    // Flea's listing is lossy for these, so it cannot act on them; see AGENTS.md corners.
    if raw.contains(&0) {
        return None;
    }
    let s = String::from_utf8(raw).ok()?;
    if !s.starts_with('/') {
        return None;
    }
    if s.split('/').any(|part| part == "." || part == "..") {
        return None;
    }
    Some(s)
}

pub fn build_gnome(op: &str, paths: &[String]) -> Vec<u8> {
    let mut out = op.to_string();
    for p in paths {
        out.push('\n');
        out.push_str(&encode_uri(p));
    }
    out.into_bytes()
}

// Sample input "copy\nfile:///tmp/a\n" gives ("copy", ["/tmp/a"], 0); a first line other than copy or cut is None.
pub fn parse_gnome(bytes: &[u8]) -> Option<(String, Vec<String>, usize)> {
    let mut lines = bytes.split(|b| *b == b'\n');
    let op = match lines.next()? {
        b"copy" => "copy",
        b"cut" => "cut",
        _ => return None,
    };
    let (paths, skipped) = collect(lines.filter(|line| !line.is_empty()));
    Some((op.to_string(), paths, skipped))
}

pub fn build_urilist(paths: &[String]) -> Vec<u8> {
    let mut out = Vec::new();
    for p in paths {
        out.extend_from_slice(encode_uri(p).as_bytes());
        out.extend_from_slice(b"\r\n");
    }
    out
}

// CRLF and LF both read; '#' lines are comments and never files.
pub fn parse_urilist(bytes: &[u8]) -> (Vec<String>, usize) {
    collect(bytes.split(|b| *b == b'\n').filter_map(|line| {
        let line = line.strip_suffix(b"\r").unwrap_or(line);
        if line.is_empty() || line.starts_with(b"#") {
            return None;
        }
        Some(line)
    }))
}

// The absolute paths, one a line, the form ui/js/Drag.js offers beside its uri-list.
pub fn build_plain(paths: &[String]) -> Vec<u8> {
    paths.join("\n").into_bytes()
}

pub fn build_kde_cut() -> Vec<u8> {
    b"1".to_vec()
}

pub fn parse_kde_cut(bytes: &[u8]) -> bool {
    let s = String::from_utf8_lossy(bytes);
    s.trim_matches(|c: char| c == '\0' || c.is_whitespace()) == "1"
}

pub fn build_flea(op: &str, token: &str) -> Vec<u8> {
    format!("{} {} {}", op, token, std::process::id()).into_bytes()
}

// The token is 32 hex chars; anything else is another owner's bytes, not a refusal.
// Sample inputs "copy ab12cd34ab12cd34ab12cd34ab12cd34" and "copy ab12cd34ab12cd34ab12cd34ab12cd34 1234" yield the same operation and token.
pub fn parse_flea(bytes: &[u8]) -> Option<(String, String)> {
    let s = std::str::from_utf8(bytes).ok()?;
    let s = s.trim_matches(|c: char| c == '\0' || c.is_whitespace());
    let (op, rest) = s.split_once(' ')?;
    let token = rest.split_once(' ').map_or(rest, |(token, _)| token);
    if !is_op(op) || token.len() != TOKEN_HEX_LEN || !token.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    Some((op.to_string(), token.to_string()))
}

// Sample input "copy ab12cd34ab12cd34ab12cd34ab12cd34 1234" yields Some(1234).
pub(crate) fn flea_pid(bytes: &[u8]) -> Option<u32> {
    parse_flea(bytes)?;
    let s = std::str::from_utf8(bytes).ok()?.trim_matches(|c: char| c == '\0' || c.is_whitespace());
    let (_, rest) = s.split_once(' ')?;
    let (_, pid) = rest.split_once(' ')?;
    let pid: u32 = pid.parse().ok()?;
    (pid > 0 && pid <= i32::MAX as u32).then_some(pid)
}

// Shared by both list shapes: refused URIs count as skipped, never fail the read.
fn collect<'a>(lines: impl Iterator<Item = &'a [u8]>) -> (Vec<String>, usize) {
    let mut paths = Vec::new();
    let mut seen = HashSet::new();
    let mut skipped = 0;
    for line in lines {
        match decode_uri(line) {
            Some(p) if seen.insert(p.clone()) => paths.push(p),
            _ => skipped += 1,
        }
    }
    (paths, skipped)
}

// 32 hex chars from the kernel via read_exact, since /dev/urandom never reaches EOF (a read to the end took 21 GB).
pub fn make_token() -> Result<String, String> {
    use std::io::Read;
    let mut bytes = [0u8; TOKEN_BYTES];
    std::fs::File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut bytes))
        .map_err(|e| format!("a clipboard token could not be made ({})", e))?;
    Ok(bytes.iter().map(|b| format!("{:02x}", b)).collect())
}

// Past 100000 paths a payload is hostile, never a selection, so it is refused rather than broadcast.
pub const MAX_CLIP_PATHS: usize = 100_000;

pub fn check_path_cap(paths: &[String]) -> Result<(), String> {
    if paths.len() > MAX_CLIP_PATHS {
        return Err(format!("the selection holds {} paths, past the {} cap", paths.len(), MAX_CLIP_PATHS));
    }
    Ok(())
}

// What clipSet and the CLI accept: absolute, no NUL, no parent component.
pub fn validate_clip_paths(paths: &[String]) -> Result<(), String> {
    check_path_cap(paths)?;
    for p in paths {
        if p.contains('\0') {
            return Err(format!("{} holds a NUL byte", p));
        }
        if !p.starts_with('/') {
            return Err(format!("{} is not an absolute path", p));
        }
        if p.split('/').any(|part| part == "..") {
            return Err(format!("{} climbs out of its directory", p));
        }
    }
    Ok(())
}

#[cfg(test)]
#[path = "format_tests.rs"]
mod tests;
