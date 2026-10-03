// Linux open-file limits use the system libc already linked by std, without a new crate.
use crate::error::io_message;
use std::os::raw::{c_int, c_ulong};
use std::sync::Once;

const RLIMIT_NOFILE: c_int = 7;
// Leave room for standard streams, listing workers and thumbnail pipes.
pub(super) const DESCRIPTOR_RESERVE: usize = 64;
pub(super) const SYMLINK_DESCRIPTORS: usize = 2;
static RAISED: Once = Once::new();

#[repr(C)]
struct Limit {
    soft: c_ulong,
    hard: c_ulong,
}
#[allow(clashing_extern_declarations)]
extern "C" {
    fn getrlimit(resource: c_int, limit: *mut Limit) -> c_int;
    fn setrlimit(resource: c_int, limit: *const Limit) -> c_int;
}
fn current() -> Result<Limit, String> {
    let mut limit = Limit { soft: 0, hard: 0 };
    if unsafe { getrlimit(RLIMIT_NOFILE, &mut limit) } != 0 {
        return Err(format!("Could not read the picker open-file limit: {}", io_message(&std::io::Error::last_os_error())));
    }
    Ok(limit)
}
pub(super) fn soft_limit() -> Result<usize, String> {
    current().map(|limit| limit.soft as usize)
}
pub(super) fn raise_soft_to_hard() {
    RAISED.call_once(|| {
        let result = current().and_then(|limit| {
            if limit.soft == limit.hard { return Ok(()); }
            let raised = Limit { soft: limit.hard, hard: limit.hard };
            if unsafe { setrlimit(RLIMIT_NOFILE, &raised) } != 0 {
                return Err(format!("Could not raise the picker open-file limit to {}: {}", limit.hard, io_message(&std::io::Error::last_os_error())));
            }
            Ok(())
        });
        if let Err(error) = result { eprintln!("flea: {}", error); }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    const CHILD_ENV: &str = "FLEA_PICKER_RAISE_LIMIT_CHILD";
    const INITIAL_SOFT: c_ulong = 80;
    const HARD_LIMIT: c_ulong = 96;

    #[test]
    fn picker_raises_soft_limit_to_hard_only_once_in_a_child() {
        if std::env::var_os(CHILD_ENV).is_none() {
            let output = std::process::Command::new(std::env::current_exe().unwrap())
                .args(["--exact", "backend::picker::limits::tests::picker_raises_soft_limit_to_hard_only_once_in_a_child", "--nocapture"])
                .env(CHILD_ENV, "1").output().unwrap();
            let report = format!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
            assert!(output.status.success() && report.contains("1 passed"), "{}", report);
            return;
        }
        let limit = Limit { soft: INITIAL_SOFT, hard: HARD_LIMIT };
        assert_eq!(unsafe { setrlimit(RLIMIT_NOFILE, &limit) }, 0);
        raise_soft_to_hard();
        let raised = current().unwrap();
        assert_eq!(raised.soft, HARD_LIMIT);
        assert_eq!(raised.hard, HARD_LIMIT);
        assert_eq!(unsafe { setrlimit(RLIMIT_NOFILE, &limit) }, 0);
        raise_soft_to_hard();
        assert_eq!(current().unwrap().soft, INITIAL_SOFT, "startup raise runs only once");
    }
}
