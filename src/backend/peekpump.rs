// The thread that turns the columns' peek watch descriptor into events, and ends when its owner says so.
use crate::backend::events::Event;
use crate::backend::inotifyburst::each_event;
use crate::backend::watch::{classify_burst, BUF, COALESCE, IN_IGNORED, IN_UNMOUNT};
use std::ffi::{c_int, c_void};
use std::io;
use std::sync::mpsc::Sender;

// poll(2) struct pollfd, whose three fields are int, short, short in that order.
#[repr(C)]
struct PollFd {
    fd: c_int,
    events: i16,
    revents: i16,
}
// poll(2) POLLIN, and a negative descriptor is skipped, which is how a pause waits on the stop descriptor alone.
const POLLIN: i16 = 1;
// poll(2) fails with EINTR when a signal lands mid-wait, which is a retry.
const EINTR: i32 = 4;
// Two descriptors: the watch's own and the owner's stop.
const POLL_BOTH: usize = 2;
// Forever, for a wait that only an event or a stop ends.
const POLL_FOREVER: c_int = -1;
// A descriptor poll skips, so a pause listens to the stop descriptor alone.
const SKIPPED: c_int = -1;

extern "C" {
    fn poll(fds: *mut PollFd, nfds: usize, timeout: c_int) -> c_int;
    fn read(fd: c_int, buf: *mut c_void, count: usize) -> isize;
}

// What a wait ended for: the watch has events, its owner asked it to stop, or the pause ran out.
#[derive(PartialEq)]
enum Wake {
    Ready,
    Stop,
    Timeout,
}

fn wait(fd: c_int, stop: c_int, timeout_ms: c_int) -> Wake {
    let mut fds = [PollFd { fd, events: POLLIN, revents: 0 }, PollFd { fd: stop, events: POLLIN, revents: 0 }];
    loop {
        let n = unsafe { poll(fds.as_mut_ptr(), POLL_BOTH, timeout_ms) };
        if n < 0 && io::Error::last_os_error().raw_os_error() == Some(EINTR) {
            continue;
        }
        // Anything but a quiet stop descriptor ends the pump, a failed poll included.
        return if n == 0 { Wake::Timeout } else if n < 0 || fds[1].revents != 0 { Wake::Stop } else { Wake::Ready };
    }
}

// Sample input: IN_CREATE on wd 3, IN_IGNORED on wd 7 twice and IN_UNMOUNT on wd 8 answers [7, 8], the watches the kernel dropped.
fn dropped_in(buf: &[u8]) -> Vec<i32> {
    let mut dropped: Vec<i32> = Vec::new();
    each_event(buf, |wd, mask| {
        if mask & (IN_IGNORED | IN_UNMOUNT) != 0 && !dropped.contains(&wd) {
            dropped.push(wd);
        }
    });
    dropped
}

// A burst names each changed directory once, then each one the kernel dropped, so a column re-asks before its watch is forgotten.
pub(crate) fn pump(fd: c_int, tx: Sender<Event>, stop: c_int) {
    let mut buf = [0u8; BUF];
    while wait(fd, stop, POLL_FOREVER) == Wake::Ready {
        let n = unsafe { read(fd, buf.as_mut_ptr() as *mut c_void, BUF) };
        if n < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
            continue;
        }
        if n <= 0 {
            return;
        }
        let burst = &buf[..n as usize];
        let (changed, _unmounted) = classify_burst(burst);
        let events = changed.into_iter().map(Event::PeekChanged).chain(dropped_in(burst).into_iter().map(Event::PeekGone));
        for event in events {
            if tx.send(event).is_err() {
                return;
            }
        }
        // One burst says one thing to a client that re-asks it all, so the pause also ends the moment its owner stops it.
        if wait(SKIPPED, stop, COALESCE.as_millis() as c_int) == Wake::Stop {
            return;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Sample input: wd 3 IN_CREATE, wd 7 IN_IGNORED twice, wd 8 IN_UNMOUNT, each with no name.
    #[test]
    fn a_burst_names_each_watch_the_kernel_dropped_once() {
        let mut buf = Vec::new();
        for (wd, mask) in [(3i32, 0x100u32), (7, IN_IGNORED), (7, IN_IGNORED), (8, IN_UNMOUNT)] {
            buf.extend_from_slice(&wd.to_ne_bytes());
            buf.extend_from_slice(&mask.to_ne_bytes());
            buf.extend_from_slice(&[0u8; 8]);
        }
        assert_eq!(dropped_in(&buf), vec![7, 8]);
    }
}
