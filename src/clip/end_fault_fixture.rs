// Fault doubles include the production waiter without changing its syscall or spawn branches.
#![allow(dead_code)]
use std::sync::atomic::{AtomicUsize, Ordering};

static ENABLED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
static EVENT_CALLS: AtomicUsize = AtomicUsize::new(0);
static POLL_CALLS: AtomicUsize = AtomicUsize::new(0);
static SPAWN_CALLS: AtomicUsize = AtomicUsize::new(0);
const ESRCH: i32 = 3;
const EINTR: i32 = 4;
const EIO: i32 = 5;
const EAGAIN: i32 = 11;
const EMFILE: i32 = 24;
const FAILED: i32 = -1;
const FAKE_PID: u32 = 1234;
const START_ATTEMPTS: usize = 2;

extern "C" {
    fn __errno_location() -> *mut i32;
}

fn mode() -> String {
    std::env::args().nth(1).unwrap()
}

fn fail(error: i32) -> i32 {
    unsafe { *__errno_location() = error; }
    FAILED
}

#[no_mangle]
extern "C" fn pidfd_open(_pid: i32, _flags: u32) -> i32 {
    fail(ESRCH)
}

#[no_mangle]
extern "C" fn eventfd(_value: u32, _flags: i32) -> i32 {
    EVENT_CALLS.fetch_add(1, Ordering::SeqCst);
    if mode() == "eventfd" {
        return fail(EMFILE);
    }
    use std::os::fd::IntoRawFd;
    std::fs::OpenOptions::new().read(true).write(true).open("/dev/null").unwrap().into_raw_fd()
}

#[no_mangle]
extern "C" fn poll(_fds: *mut std::ffi::c_void, _count: usize, _timeout: i32) -> i32 {
    if !ENABLED.load(Ordering::SeqCst) {
        return 0;
    }
    let previous = POLL_CALLS.fetch_add(1, Ordering::SeqCst);
    if mode() == "interrupted" && previous == 0 {
        return fail(EINTR);
    }
    fail(EIO)
}

mod fault_std {
    pub use std::*;

    pub mod thread {
        pub use std::thread::JoinHandle;

        pub struct Builder(std::thread::Builder);

        impl Builder {
            pub fn new() -> Self {
                Self(std::thread::Builder::new())
            }

            pub fn name(self, name: String) -> Self {
                Self(self.0.name(name))
            }

            pub fn spawn<F, T>(self, run: F) -> std::io::Result<JoinHandle<T>>
            where F: FnOnce() -> T + Send + 'static, T: Send + 'static {
                crate::SPAWN_CALLS.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                if crate::mode() == "spawn" {
                    return Err(std::io::Error::from_raw_os_error(crate::EAGAIN));
                }
                self.0.spawn(run)
            }
        }
    }
}

mod backend {
    pub mod opsreq {
        pub struct OpMsg;
    }
}

mod clip {
    pub mod wire {
        pub struct Conn;

        impl Conn {
            pub fn connect() -> Result<Self, String> {
                Err("unused connection".into())
            }

            pub fn connect_to(_path: &std::path::Path) -> Result<Self, String> {
                Self::connect()
            }
        }
    }

    pub mod control {
        pub struct OfferFiles {
            pub owner_pid: Option<u32>,
            pub token: String,
        }

        pub fn get_files_on(_conn: &mut super::wire::Conn) -> Result<OfferFiles, String> {
            Err("unused read".into())
        }
    }

    pub mod watch {
        pub type Shared = std::sync::Arc<std::sync::Mutex<()>>;

        pub fn reread(_replies: &std::sync::mpsc::Sender<crate::backend::opsreq::OpMsg>, _state: &Shared, _token: &str,
            _read: impl FnOnce() -> Result<super::control::OfferFiles, String>,
            _cancelled: impl Fn() -> bool, _track: impl FnOnce(&super::control::OfferFiles)) -> bool {
            panic!("a failed waiter cannot read a selection")
        }
    }

    mod end {
        use crate::fault_std as std;
        include!("end.rs");

        pub fn probe() {
            let (tx, rx) = std::sync::mpsc::channel();
            let mut end = OwnerEnd::new(tx, Arc::new(Mutex::new(())), None);
            for _ in 0..crate::START_ATTEMPTS {
                end.track(Some(crate::FAKE_PID), "sample-token");
            }
            let worker_started = end.worker.is_some();
            if let Some(worker) = end.worker.take() {
                worker.join().unwrap();
            }
            assert!(rx.try_recv().is_err(), "diagnostics stay off the clipboard reply stream");
            println!("{}: eventfd_calls={} spawn_calls={} poll_calls={} wake={} worker_started={}", crate::mode(),
                crate::EVENT_CALLS.load(Ordering::SeqCst), crate::SPAWN_CALLS.load(Ordering::SeqCst),
                crate::POLL_CALLS.load(Ordering::SeqCst), end.wake.is_some(), worker_started);
        }
    }

    pub fn probe() {
        end::probe();
    }
}

fn main() {
    ENABLED.store(true, Ordering::SeqCst);
    clip::probe();
}
