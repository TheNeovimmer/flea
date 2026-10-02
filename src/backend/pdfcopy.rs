// A PDF on a hung mount must not freeze the window: the fetch runs beside the loop under a
// deadline into a session-private cache file, and the viewer draws the local copy.
use crate::backend::opsreq::OpMsg;
use crate::json::escape;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::channel;
use std::sync::Arc;
use std::time::Duration;

// How long one fetch waits for the filesystem before the viewer says the file is not responding.
pub const PDF_COPY_WAIT: Duration = Duration::from_secs(8);
// The session-private cache beside the shared thumbnails; swept on first use, so no earlier
// process's file is ever handed to this one's viewer.
const PDF_CACHE_LEAF: &str = "flea/pdf";
static SWEPT: AtomicBool = AtomicBool::new(false);

fn cache_dir() -> PathBuf {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .filter(|p| !p.as_os_str().is_empty())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join(PDF_CACHE_LEAF)
}

// Sample input: {"c":"pdfcopy","id":3,"path":"/run/media/gm/128GB/doc.pdf"}.
pub fn pdfcopied_line(id: usize, path: &str, err: &str) -> String {
    if err.is_empty() {
        format!(r#"{{"t":"pdfcopied","id":{},"path":"{}"}}"#, id, escape(path))
    } else {
        format!(r#"{{"t":"pdfcopied","id":{},"err":"{}"}}"#, id, escape(err))
    }
}

fn dest_for(dir: &Path, id: usize, src: &Path) -> PathBuf {
    let stem = src.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| "document.pdf".to_string());
    dir.join(format!("{id}-{stem}"))
}

// The copy itself, chunk by chunk so a cancel or a deadline stops paying for bytes nobody reads.
fn copy_into(src: &Path, dst: &Path, done: &Arc<AtomicBool>) -> Result<(), String> {
    let mut reader = std::fs::File::open(src).map_err(|e| crate::error::io_message(&e))?;
    if let Some(parent) = dst.parent() {
        std::fs::create_dir_all(parent).map_err(|e| crate::error::io_message(&e))?;
    }
    let mut writer = std::fs::File::create(dst).map_err(|e| crate::error::io_message(&e))?;
    let mut buf = vec![0u8; 262144];
    loop {
        if done.load(Ordering::Relaxed) {
            let _ = std::fs::remove_file(dst);
            return Err("cancelled".to_string());
        }
        use std::io::Read;
        let n = reader.read(&mut buf).map_err(|e| crate::error::io_message(&e))?;
        if n == 0 {
            break;
        }
        use std::io::Write;
        writer.write_all(&buf[..n]).map_err(|e| crate::error::io_message(&e))?;
    }
    Ok(())
}

fn fetch(id: usize, src: PathBuf, tx: std::sync::mpsc::Sender<OpMsg>) {
    let dir = cache_dir();
    if !SWEPT.swap(true, Ordering::Relaxed) {
        let _ = std::fs::remove_dir_all(&dir);
    }
    let dst = dest_for(&dir, id, &src);
    let done = Arc::new(AtomicBool::new(false));
    let (one_tx, one_rx) = channel::<Result<(), String>>();
    let worker_done = Arc::clone(&done);
    let worker_dst = dst.clone();
    std::thread::spawn(move || {
        let result = copy_into(&src, &worker_dst, &worker_done);
        if !worker_done.load(Ordering::Relaxed) {
            let _ = one_tx.send(result);
        }
    });
    match one_rx.recv_timeout(PDF_COPY_WAIT) {
        Ok(Ok(())) => {
            let _ = tx.send(OpMsg::Meta { line: pdfcopied_line(id, &dst.to_string_lossy(), "") });
        }
        Ok(Err(msg)) => {
            let _ = std::fs::remove_file(&dst);
            let _ = tx.send(OpMsg::Meta { line: pdfcopied_line(id, "", &msg) });
        }
        Err(_) => {
            done.store(true, Ordering::Relaxed);
            let _ = tx.send(OpMsg::Meta { line: pdfcopied_line(id, "", "that file is not responding") });
        }
    }
}

pub fn spawn(id: usize, path: PathBuf, tx: std::sync::mpsc::Sender<OpMsg>) {
    std::thread::spawn(move || fetch(id, path, tx));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_local_file_is_handed_back_as_a_private_copy() {
        let d = crate::backend::testdir::TestDir::new("pdfcopy-local");
        let src = d.file("doc.pdf", "%PDF-1.4 local\n");
        let dst = d.join("copy.pdf");
        fetch_to(&src, &dst);
        assert_eq!(std::fs::read(&dst).unwrap(), b"%PDF-1.4 local\n");
        assert!(dst.starts_with(d.path()), "the copy stays inside the sandbox");
    }

    #[test]
    fn a_reply_line_names_the_copy_or_the_wait() {
        assert_eq!(pdfcopied_line(3, "/x/doc.pdf", ""), r#"{"t":"pdfcopied","id":3,"path":"/x/doc.pdf"}"#);
        assert_eq!(pdfcopied_line(3, "", "that file is not responding"), r#"{"t":"pdfcopied","id":3,"err":"that file is not responding"}"#);
    }

    #[test]
    fn a_hung_source_answers_not_responding_inside_the_wait() {
        let d = crate::backend::testdir::TestDir::new("pdfcopy-hang");
        let fifo = d.join("hung.pdf");
        make_fifo(&fifo);
        // Read-write opens a fifo without blocking, so the copy's own open succeeds and its read blocks.
        let _writer = std::fs::OpenOptions::new().read(true).write(true).open(&fifo).unwrap();
        let dst = d.join("copy.pdf");
        let done = Arc::new(AtomicBool::new(false));
        let (one_tx, one_rx) = channel::<Result<(), String>>();
        let worker_done = Arc::clone(&done);
        std::thread::spawn(move || {
            let result = copy_into(&fifo, &dst, &worker_done);
            if !worker_done.load(Ordering::Relaxed) {
                let _ = one_tx.send(result);
            }
        });
        let result = one_rx.recv_timeout(Duration::from_millis(500));
        done.store(true, Ordering::Relaxed);
        assert!(result.is_err(), "a hung read never answers inside the wait");
    }

    #[test]
    fn the_wait_is_eight_seconds() {
        assert_eq!(PDF_COPY_WAIT, Duration::from_secs(8));
    }

    // A fifo's blocking read without a writer is the hung mount in miniature; extern C in the
    // idiom src/thp.rs already uses, because std exposes no mkfifo.
    extern "C" {
        fn mkfifo(path: *const i8, mode: u32) -> i32;
    }

    fn make_fifo(path: &Path) {
        use std::os::unix::ffi::OsStrExt;
        let bytes = path.as_os_str().as_bytes();
        let mut nulled = bytes.to_vec();
        nulled.push(0);
        let code = unsafe { mkfifo(nulled.as_ptr() as *const i8, 0o600) };
        assert_eq!(code, 0, "the hung-source fixture could not be made");
    }

    // The copy without the wait, so the local test above proves bytes and not timing.
    fn fetch_to(src: &Path, dst: &Path) {
        let done = Arc::new(AtomicBool::new(false));
        copy_into(src, dst, &done).expect("a local file copies");
    }
}
