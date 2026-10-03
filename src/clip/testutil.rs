// Fake compositors wait for a connection only until their test's hang guard expires.
use std::io::{self, ErrorKind};
use std::os::fd::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::time::{Duration, Instant};

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

extern "C" {
    fn poll(fds: *mut PollFd, nfds: usize, timeout: i32) -> i32;
}

const POLLIN: i16 = 1;

pub(crate) fn accept(listener: &UnixListener, watchdog: Duration) -> io::Result<UnixStream> {
    listener.set_nonblocking(true)?;
    let started = Instant::now();
    loop {
        match listener.accept() {
            Ok((stream, _)) => return Ok(stream),
            Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::Interrupted) => {}
            Err(e) => return Err(e),
        }
        let remaining = watchdog.saturating_sub(started.elapsed());
        if remaining.is_zero() {
            return Err(io::Error::new(ErrorKind::TimedOut, "the fake compositor received no connection within the test watchdog"));
        }
        let mut fd = PollFd { fd: listener.as_raw_fd(), events: POLLIN, revents: 0 };
        let timeout = remaining.as_millis().clamp(1, i32::MAX as u128) as i32;
        if unsafe { poll(&mut fd, 1, timeout) } < 0 {
            let error = io::Error::last_os_error();
            if error.kind() != ErrorKind::Interrupted {
                return Err(error);
            }
        }
    }
}
