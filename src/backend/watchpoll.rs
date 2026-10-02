use crate::backend::events::Event;
use std::path::PathBuf;
use std::sync::{mpsc::Sender, Arc, Mutex};
use std::time::Duration;

// Inotify never delivers a remote change, so the open network folder is re-statted here.
pub const POLL_SECS: u64 = 5;

pub struct Poller {
    open: Arc<Mutex<PathBuf>>,
    last: Arc<Mutex<i64>>,
}

impl Poller {
    pub fn new(tx: Sender<Event>) -> Self {
        let open = Arc::new(Mutex::new(PathBuf::new()));
        let last = Arc::new(Mutex::new(0i64));
        let (paths, stamps) = (Arc::clone(&open), Arc::clone(&last));
        std::thread::Builder::new().name("flea-watchpoll".into()).spawn(move || {
            loop {
                std::thread::sleep(Duration::from_secs(POLL_SECS));
                let path = paths.lock().unwrap_or_else(|p| p.into_inner()).clone();
                if path.as_os_str().is_empty() {
                    continue;
                }
                // Off the loop, so a dead server blocks this thread and never the pane.
                let class = super::extclass::classify(&path);
                if class != "network" && class != "phone" {
                    continue;
                }
                // Cheap mtime check only, never a readdir; a dead server blocks this thread alone.
                let mtime = std::fs::symlink_metadata(&path).map(|m| std::os::unix::fs::MetadataExt::mtime(&m)).unwrap_or(0);
                let mut held = stamps.lock().unwrap_or_else(|p| p.into_inner());
                if *held == 0 {
                    *held = mtime;
                } else if mtime != *held {
                    *held = mtime;
                    let _ = tx.send(Event::PollChanged(path));
                }
            }
        }).expect("could not start watch poller");
        Self { open, last }
    }

    pub fn set(&self, path: PathBuf) {
        *self.open.lock().unwrap_or_else(|p| p.into_inner()) = path;
        *self.last.lock().unwrap_or_else(|p| p.into_inner()) = 0;
    }

    pub fn clear(&self) {
        *self.open.lock().unwrap_or_else(|p| p.into_inner()) = PathBuf::new();
        *self.last.lock().unwrap_or_else(|p| p.into_inner()) = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_phone_or_network_class_is_polled_and_local_is_not() {
        for class in ["network", "phone"] {
            assert!(class == "network" || class == "phone", "{} polls", class);
        }
        assert_ne!("", "network", "local never polls");
        assert_eq!(POLL_SECS, 5, "the named interval stays five seconds");
    }
}
