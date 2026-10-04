// The directories the columns view peeks at, watched so a neighbour column follows an outside change; see docs/protocol.md "changed".
use crate::backend::events::Event;
use crate::backend::watch::{pump, Watch};
use std::collections::VecDeque;
use std::ffi::c_int;
use std::path::{Path, PathBuf};
use std::sync::mpsc::Sender;
use std::thread;

// Parent, grandparent, great-grandparent and the child column, plus room for one navigation's leftovers.
const PEEK_WATCH_CAP: usize = 8;

extern "C" {
    fn inotify_init1(flags: c_int) -> c_int;
    fn inotify_rm_watch(fd: c_int, wd: c_int) -> c_int;
}
// IN_CLOEXEC is O_CLOEXEC, so no thumbnailer child inherits this descriptor.
const IN_CLOEXEC: c_int = 0x0008_0000;

// Its own inotify descriptor, so a descriptor removed here can never be the listed directory's own watch.
pub struct PeekWatch {
    fd: c_int,
    held: VecDeque<(c_int, PathBuf)>,
}

impl PeekWatch {
    // A box with no inotify keeps its neighbour columns as live as before, and the listed folder already said so once.
    pub fn start(tx: Sender<Event>) -> PeekWatch {
        let fd = unsafe { inotify_init1(IN_CLOEXEC) };
        if fd >= 0 {
            thread::spawn(move || pump(fd, tx, true));
        }
        PeekWatch { fd, held: VecDeque::new() }
    }

    // The peek worker arms with this descriptor, so a dead mount never blocks the loop.
    pub fn raw_fd(&self) -> c_int {
        self.fd
    }

    // A path armed twice answers the descriptor it already had, so it is held once; the oldest goes past the cap.
    pub fn register(&mut self, wd: c_int, path: PathBuf) {
        if wd < 0 || self.held.iter().any(|(held, _)| *held == wd) {
            return;
        }
        self.held.push_back((wd, path));
        while self.held.len() > PEEK_WATCH_CAP {
            if let Some((old, _)) = self.held.pop_front() {
                unsafe { inotify_rm_watch(self.fd, old) };
            }
        }
    }

    // A removed watch's own late IN_IGNORED names a descriptor nobody holds, so it answers nothing.
    pub fn path_of(&self, wd: c_int) -> Option<&Path> {
        self.held.iter().find(|(held, _)| *held == wd).map(|(_, path)| path.as_path())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;
    use std::sync::mpsc::channel;
    use std::time::Duration;

    // Bounds the wait for a kernel event; the test asserts what arrived, never how long it took.
    const EVENT_WAIT: Duration = Duration::from_secs(10);

    #[test]
    fn an_outside_create_in_a_peeked_directory_names_that_directory() {
        let d = TestDir::new("peekwatchcreate");
        let peeked = d.dir("peeked");
        let (tx, rx) = channel();
        let mut watch = PeekWatch::start(tx);
        let wd = Watch::add_raw(watch.raw_fd(), &peeked);
        assert!(wd >= 0, "a local directory can be watched");
        watch.register(wd, peeked.clone());
        std::fs::write(peeked.join("new.txt"), "x").unwrap();
        let Event::PeekChanged(seen) = rx.recv_timeout(EVENT_WAIT).expect("a create answers an event") else { panic!("not a peek event") };
        assert_eq!(watch.path_of(seen), Some(peeked.as_path()));
    }

    #[test]
    fn the_same_directory_armed_twice_is_held_once() {
        let d = TestDir::new("peekwatchtwice");
        let peeked = d.dir("peeked");
        let (tx, _rx) = channel();
        let mut watch = PeekWatch::start(tx);
        let (first, second) = (Watch::add_raw(watch.raw_fd(), &peeked), Watch::add_raw(watch.raw_fd(), &peeked));
        assert_eq!(first, second, "inotify answers the descriptor it already holds");
        watch.register(first, peeked.clone());
        watch.register(second, peeked.clone());
        assert_eq!(watch.held.len(), 1);
    }

    #[test]
    fn the_oldest_directory_is_unwatched_past_the_cap() {
        let d = TestDir::new("peekwatchcap");
        let (tx, _rx) = channel();
        let mut watch = PeekWatch::start(tx);
        let mut armed = Vec::new();
        for n in 0..=PEEK_WATCH_CAP {
            let dir = d.dir(&format!("d{n}"));
            let wd = Watch::add_raw(watch.raw_fd(), &dir);
            watch.register(wd, dir.clone());
            armed.push((wd, dir));
        }
        assert_eq!(watch.held.len(), PEEK_WATCH_CAP);
        assert_eq!(watch.path_of(armed[0].0), None, "the oldest watch was dropped");
        assert_eq!(watch.path_of(armed[PEEK_WATCH_CAP].0), Some(armed[PEEK_WATCH_CAP].1.as_path()));
    }

    #[test]
    fn no_descriptor_is_held() {
        let (tx, _rx) = channel();
        let mut watch = PeekWatch::start(tx);
        watch.register(-1, PathBuf::from("/nowhere"));
        assert_eq!(watch.held.len(), 0);
    }
}
