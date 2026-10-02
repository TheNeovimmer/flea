// flea --clip-own: the detached owner behind one clipboard copy. It reads one
// <op> NUL <token> NUL <path> NUL ... payload on stdin, offers every clipboard type,
// prints ready and lets go of its parent's pipes, then serves sends until it is
// cancelled or the connection ends. Started detached, so the copy outlives its window.
use super::control;
use super::format;
use super::owner;
use super::wire::Conn;
use std::collections::HashMap;
use std::os::raw::c_int;
use std::os::unix::process::CommandExt;
use std::time::Duration;

extern "C" {
    fn setsid() -> c_int;
    fn kill(pid: c_int, sig: c_int) -> c_int;
    fn waitpid(pid: c_int, status: *mut c_int, options: c_int) -> c_int;
}

const SIGTERM: c_int = 15;
const WNOHANG: c_int = 1;

// Owners this process started that may still hold the clipboard, by token. The waiter
// removes each entry on reap, and withdraw reaps before killing, so a pid here is never
// a recycled one.
static OWNERS: std::sync::OnceLock<std::sync::Mutex<HashMap<String, u32>>> = std::sync::OnceLock::new();

fn owners() -> &'static std::sync::Mutex<HashMap<String, u32>> {
    OWNERS.get_or_init(|| std::sync::Mutex::new(HashMap::new()))
}

fn remember(token: &str, pid: u32) {
    if let Ok(mut owners) = owners().lock() {
        owners.insert(token.to_string(), pid);
    }
}

fn forget(token: &str, pid: u32) {
    if let Ok(mut owners) = owners().lock() {
        if owners.get(token) == Some(&pid) {
            owners.remove(token);
        }
    }
}

// Withdrawing our own copy kills the owner holding it: the compositor drops a
// disconnected client's sources, so it clears only if it still holds that source and a
// newer copy is never wiped. A token this process did not spawn is stale here;
// cross-window spends use the cut form instead.
pub fn withdraw(token: &str) -> bool {
    let pid = match owners().lock().map(|owners| owners.get(token).copied()) {
        Ok(Some(pid)) => pid as c_int,
        _ => return false,
    };
    // Reap first: an owner that already exited (cancelled by a newer copy) is stale,
    // and reaping here keeps its pid from ever being recycled under us.
    let mut status = 0;
    if unsafe { waitpid(pid, &mut status, WNOHANG) } == pid {
        forget(token, pid as u32);
        return false;
    }
    if unsafe { kill(pid, SIGTERM) } != 0 {
        forget(token, pid as u32);
        return false;
    }
    true
}

// stdin is a pipe the parent writes, never a device; still, no read here runs past this.
const STDIN_CAP: u64 = 64 * 1024 * 1024;

pub fn read_capped_stdin() -> Result<Vec<u8>, String> {
    use std::io::Read;
    let mut out = Vec::new();
    let mut stdin = std::io::stdin().lock();
    let mut chunk = [0u8; 65536];
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
    if token.len() != 32 || !token.bytes().all(|b| b.is_ascii_hexdigit()) {
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
    let token = format::make_token()?;
    let exe = std::env::current_exe().map_err(|e| format!("the clipboard owner could not start ({})", e))?;
    let mut child = unsafe {
        std::process::Command::new(exe)
        .arg("--clip-own")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .pre_exec(|| {
            if setsid() < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        })
        .spawn()
    }
    .map_err(|e| format!("the clipboard owner could not start ({})", e))?;
    // Every exit after a spawn waits exactly once: what will not answer is killed
    // first, then reaped, so no path here leaves a zombie behind.
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
    match rx.recv_timeout(Duration::from_secs(2)) {
        Ok((true, line)) if line.trim_end() == "ready" => {}
        _ => {
            abandon(child);
            return Err("the clipboard owner did not answer".to_string());
        }
    }
    let pid = child.id();
    remember(&token, pid);
    // Reaping is a thread's job, never the caller's wait: the owner runs until it is replaced.
    let remembered = token.clone();
    std::thread::spawn(move || {
        let _ = child.wait();
        forget(&remembered, pid);
    });
    Ok(token)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;

    // Our own zombie children, by pid: unreaped exits the waiter never saw.
    fn zombie_children() -> Vec<u32> {
        let me = std::process::id().to_string();
        let mut out = Vec::new();
        for entry in std::fs::read_dir("/proc").into_iter().flatten().flatten() {
            let Ok(pid) = entry.file_name().to_string_lossy().parse::<u32>() else { continue };
            let Ok(stat) = std::fs::read_to_string(entry.path().join("stat")) else { continue };
            let Some(after) = stat.rfind(')').and_then(|i| stat.get(i + 2..)) else { continue };
            let mut fields = after.split_whitespace();
            if fields.next() == Some("Z") && fields.next() == Some(me.as_str()) {
                out.push(pid);
            }
        }
        out
    }

    #[test]
    fn a_failed_owner_start_leaves_no_zombie_child() {
        let _held = crate::clip::ENV_GUARD.lock().unwrap_or_else(|e| e.into_inner());
        let before = zombie_children();
        // No compositor answers, so the start fails on its 2 s ready wait.
        let dir = TestDir::new("clip-owner-fail");
        let sock = dir.join("none");
        let old = std::env::var_os("WAYLAND_DISPLAY");
        std::env::set_var("WAYLAND_DISPLAY", &sock);
        let failed = spawn_owner("copy", &["/tmp/a.txt".to_string()]);
        match old {
            Some(v) => std::env::set_var("WAYLAND_DISPLAY", v),
            None => std::env::remove_var("WAYLAND_DISPLAY"),
        }
        assert!(failed.is_err());
        // A leaked waiter would still be holding its exit; half a second is ample.
        std::thread::sleep(std::time::Duration::from_millis(500));
        let new: Vec<u32> = zombie_children().into_iter().filter(|p| !before.contains(p)).collect();
        assert!(new.is_empty(), "zombie children left behind: {:?}", new);
    }

    #[test]
    fn withdraw_kills_only_what_this_process_owns() {
        assert!(!withdraw("no-such-token"));
        let mut child = std::process::Command::new("/bin/sleep")
            .arg("30")
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .expect("a sleeper");
        let pid = child.id();
        remember("test-token", pid);
        assert!(withdraw("test-token"));
        let _ = child.wait();
        // Reaped now; a second withdraw finds nothing to kill.
        assert!(!withdraw("test-token"));
    }
}
