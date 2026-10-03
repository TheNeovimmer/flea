// flea --clip-own: the detached owner behind one copy; it prints ready, then serves sends until cancelled.
use super::control;
use super::format;
use super::owner;
use super::wire::Conn;
use std::collections::HashMap;
use std::os::raw::{c_int, c_void};
use std::os::unix::process::CommandExt;
use std::time::Duration;

extern "C" {
    fn waitid(kind: c_int, id: u32, info: *mut c_void, options: c_int) -> c_int;
    fn setsid() -> c_int;
    fn kill(pid: c_int, sig: c_int) -> c_int;
    #[cfg(test)]
    fn waitpid(pid: c_int, status: *mut c_int, options: c_int) -> c_int;
}

const SIGTERM: c_int = 15;
const WNOHANG: c_int = 1;

// A mapped pid is alive or unreaped: the waiter removes it under this lock before reaping.
static OWNERS: std::sync::OnceLock<std::sync::Mutex<HashMap<String, u32>>> = std::sync::OnceLock::new();

fn owners() -> &'static std::sync::Mutex<HashMap<String, u32>> {
    OWNERS.get_or_init(|| std::sync::Mutex::new(HashMap::new()))
}

fn remember(token: &str, pid: u32) {
    owners().lock().unwrap_or_else(|e| e.into_inner()).insert(token.to_string(), pid);
}

fn forget(token: &str, pid: u32) {
    let mut owners = owners().lock().unwrap_or_else(|e| e.into_inner());
    if owners.get(token) == Some(&pid) {
        owners.remove(token);
    }
}

// Kills the owner this process started for the token; a stale or foreign token answers false and signals nothing.
pub fn withdraw(token: &str) -> bool {
    let mut owned = owners().lock().unwrap_or_else(|e| e.into_inner());
    let Some(&pid) = owned.get(token) else { return false; };
    // The lock keeps the pid unreaped while checking its exit and signalling only a live owner.
    if !owner_live(pid) {
        return false;
    }
    if unsafe { kill(pid as c_int, SIGTERM) } != 0 {
        owned.remove(token);
        return false;
    }
    true
}

// stdin is a pipe the parent writes, yet no read runs past this cap.
const STDIN_CHUNK: usize = 64 * 1024;
const STDIN_CAP: u64 = 64 * 1024 * 1024;

pub fn read_capped_stdin() -> Result<Vec<u8>, String> {
    use std::io::Read;
    let mut out = Vec::new();
    let mut stdin = std::io::stdin().lock();
    let mut chunk = [0u8; STDIN_CHUNK];
    loop {
        match stdin.read(&mut chunk) {
            Ok(0) => return Ok(out),
            Ok(n) => {
                out.extend_from_slice(&chunk[..n]);
                if out.len() as u64 > STDIN_CAP {
                    return Err("the clipboard payload passed its 64 MiB cap".to_string());
                }
            }
            Err(e) => return Err(format!("the clipboard paths could not be read ({})", e)),
        }
    }
}

pub fn run() -> i32 {
    match run_inner() {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("flea: {}", e);
            2
        }
    }
}

fn run_inner() -> Result<(), String> {
    let payload = read_capped_stdin()?;
    let (op, token, paths) = split_payload(&payload)?;
    let mut conn = Conn::connect()?;
    let bound = control::handshake(&mut conn)?;
    let mut owner = owner::own_on(conn, &bound, &op, &paths, &token)?;
    println!("ready");
    use std::io::Write;
    std::io::stdout().flush().map_err(|e| format!("the ready line could not be written ({})", e))?;
    // From here no pipe of the parent is held open, as wl-copy leaves none either.
    owner::detach_stdio();
    owner::serve_owner(&mut owner)?;
    Ok(())
}

// Sample input: "copy\0ab12...(32 hex)\0/tmp/a\0/tmp/b\0" gives ("copy", the token, ["/tmp/a", "/tmp/b"]).
fn split_payload(payload: &[u8]) -> Result<(String, String, Vec<String>), String> {
    let mut parts: Vec<&[u8]> = payload.split(|b| *b == 0).collect();
    if parts.last() == Some(&b"".as_slice()) {
        parts.pop();
    }
    let [op, token, paths @ ..] = parts.as_slice() else {
        return Err("the clipboard payload names no operation".to_string());
    };
    let op = std::str::from_utf8(op).map_err(|_| "the clipboard operation is not text".to_string())?;
    if !format::is_op(op) {
        return Err("the clipboard operation is copy or cut".to_string());
    }
    let token = std::str::from_utf8(token).map_err(|_| "the clipboard token is not text".to_string())?;
    if token.len() != format::TOKEN_HEX_LEN || !token.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("the clipboard token is 32 hex chars".to_string());
    }
    let mut out = Vec::with_capacity(paths.len());
    for p in paths {
        out.push(std::str::from_utf8(p).map_err(|_| "a clipboard path is not text".to_string())?.to_string());
    }
    format::validate_clip_paths(&out)?;
    if out.is_empty() {
        return Err("the clipboard names no path".to_string());
    }
    Ok((op.to_string(), token.to_string(), out))
}

// One copy's owner, detached into its own session; the copy outlives the window that made it.
pub fn spawn_owner(op: &str, paths: &[String]) -> Result<String, String> {
    if !format::is_op(op) {
        return Err("the clipboard operation is copy or cut".to_string());
    }
    format::validate_clip_paths(paths)?;
    if paths.is_empty() {
        return Err("the clipboard names no path".to_string());
    }
    let exe = std::env::current_exe().map_err(|e| format!("the clipboard owner could not start ({})", e))?;
    spawn_owner_with(&exe, op, paths, |rx| rx.recv_timeout(OWNER_READY_WAIT))
}

const OWNER_READY_WAIT: Duration = Duration::from_secs(2);
// The owner's first stdout line: whether the read finished, and what it held.
type Ready = (bool, String);

// The program and the ready wait are parameters so a test starts a real child and ends its wait at once.
pub(crate) fn spawn_owner_with(
    exe: &std::path::Path, op: &str, paths: &[String],
    ready: impl FnOnce(&std::sync::mpsc::Receiver<Ready>) -> Result<Ready, std::sync::mpsc::RecvTimeoutError>,
) -> Result<String, String> {
    let token = format::make_token()?;
    let mut child = unsafe {
        std::process::Command::new(exe)
        .arg("--clip-own")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .pre_exec(|| {
            if setsid() < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        })
        .spawn()
    }
    .map_err(|e| format!("the clipboard owner could not start ({})", e))?;
    // Every exit after a spawn kills then reaps the child once, so no path leaves a zombie.
    let abandon = |mut child: std::process::Child| {
        let _ = child.kill();
        let _ = child.wait();
    };
    let mut payload = format!("{}\0{}\0", op, token).into_bytes();
    for p in paths {
        payload.extend_from_slice(p.as_bytes());
        payload.push(0);
    }
    use std::io::Write;
    let mut stdin = match child.stdin.take() {
        Some(stdin) => stdin,
        None => {
            abandon(child);
            return Err("the clipboard owner could not start (no stdin)".to_string());
        }
    };
    if stdin.write_all(&payload).is_err() {
        abandon(child);
        return Err("the clipboard owner could not start (no payload)".to_string());
    }
    drop(stdin);
    let stdout = match child.stdout.take() {
        Some(stdout) => stdout,
        None => {
            abandon(child);
            return Err("the clipboard owner could not start (no stdout)".to_string());
        }
    };
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        use std::io::BufRead;
        let mut line = String::new();
        let done = std::io::BufReader::new(stdout).read_line(&mut line).is_ok();
        let _ = tx.send((done, line));
    });
    match ready(&rx) {
        Ok((true, line)) if line.trim_end() == "ready" => {}
        _ => {
            let stderr = child.stderr.take();
            abandon(child);
            let error = stderr.and_then(|stderr| {
                use std::io::BufRead;
                let mut line = String::new();
                std::io::BufReader::new(stderr).read_line(&mut line).ok()?;
                // Sample input: "flea: no clipboard protocol: neither data-control manager is offered\n".
                let line = line.trim_end();
                let error = line.strip_prefix("flea: ").unwrap_or(line);
                (!error.is_empty()).then(|| error.to_string())
            });
            return Err(error.unwrap_or_else(|| "the clipboard owner did not answer".to_string()));
        }
    }
    let pid = child.id();
    remember(&token, pid);
    // A thread reaps the owner after it runs until replaced, so the caller never waits on it.
    let remembered = token.clone();
    std::thread::spawn(move || {
        reap_owner(child, &remembered, || {});
    });
    Ok(token)
}

// waitid with WNOWAIT sees an exit without reaping it, so the pid stays unrecyclable until forget.
const P_PID: c_int = 1;
const WEXITED: c_int = 4;
const WNOWAIT: c_int = 0x01000000;
const EINTR: i32 = 4;
const SIGINFO_WORDS: usize = 16;

fn owner_live(pid: u32) -> bool {
    loop {
        let mut info = [0u64; SIGINFO_WORDS];
        let result = unsafe { waitid(P_PID, pid, info.as_mut_ptr().cast(), WEXITED | WNOHANG | WNOWAIT) };
        if result == 0 {
            // Linux clears si_signo at the start of siginfo when no exit is available.
            return info[0] == 0;
        }
        if std::io::Error::last_os_error().raw_os_error() != Some(EINTR) {
            return false;
        }
    }
}

fn wait_for_exit(pid: u32) {
    let mut info = [0u64; SIGINFO_WORDS];
    loop {
        if unsafe { waitid(P_PID, pid, info.as_mut_ptr().cast(), WEXITED | WNOWAIT) } == 0 {
            return;
        }
        if std::io::Error::last_os_error().raw_os_error() != Some(EINTR) {
            return;
        }
    }
}

fn reap_owner(mut child: std::process::Child, token: &str, after_exit: impl FnOnce()) {
    let pid = child.id();
    wait_for_exit(pid);
    after_exit();
    forget(token, pid);
    let _ = child.wait();
}

#[cfg(test)]
#[path = "own_tests.rs"]
mod tests;
