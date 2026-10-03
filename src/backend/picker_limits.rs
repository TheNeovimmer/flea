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
    use std::io::{BufRead, Read, Write};
    use std::process::{Command, Stdio};
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

    #[test]
    fn non_picker_backend_keeps_soft_limit_after_a_listing_in_a_child() {
        const LIST_CHILD_ENV: &str = "FLEA_NON_PICKER_LIMIT_CHILD";
        if std::env::var_os(LIST_CHILD_ENV).is_some() {
            let limit = Limit { soft: INITIAL_SOFT, hard: HARD_LIMIT };
            assert_eq!(unsafe { setrlimit(RLIMIT_NOFILE, &limit) }, 0);
            assert_eq!(crate::backend::run::run(), 0);
            assert_eq!(current().unwrap().soft, INITIAL_SOFT, "non-picker backend must keep its soft limit after listing");
            return;
        }
        let directory = std::env::current_dir().unwrap().join("src/backend");
        let mut child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "backend::picker::limits::tests::non_picker_backend_keeps_soft_limit_after_a_listing_in_a_child", "--nocapture"])
            .env(LIST_CHILD_ENV, "1")
            .env("XDG_CACHE_HOME", std::env::temp_dir())
            .env_remove(crate::prefetch::LIST_ENV)
            .env_remove("FLEA_UNDO_DIR")
            .env_remove("XDG_RUNTIME_DIR")
            .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped())
            .spawn().unwrap();
        let mut input = child.stdin.take().unwrap();
        writeln!(input, r#"{{"c":"list","path":"{}"}}"#, crate::json::escape(&directory.to_string_lossy())).unwrap();
        let mut output = std::io::BufReader::new(child.stdout.take().unwrap());
        let mut report = String::new();
        let mut listed = false;
        loop {
            let mut line = String::new();
            if output.read_line(&mut line).unwrap() == 0 { break; }
            // Sample reply: {"t":"rows","start":0,"rows":[...]}, following the handled listing.
            listed = line.contains(r#""t":"rows""#);
            report.push_str(&line);
            if listed { break; }
        }
        if listed { writeln!(input, r#"{{"c":"quit"}}"#).unwrap(); }
        drop(input);
        output.read_to_string(&mut report).unwrap();
        let result = child.wait_with_output().unwrap();
        report.push_str(&String::from_utf8_lossy(&result.stderr));
        assert!(listed && result.status.success() && report.contains("1 passed"), "{}", report);
    }

    #[test]
    fn picker_budget_uses_the_hard_limit_in_a_child() {
        const BUDGET_CHILD_ENV: &str = "FLEA_PICKER_HARD_BUDGET_CHILD";
        if std::env::var_os(BUDGET_CHILD_ENV).is_none() {
            let output = Command::new(std::env::current_exe().unwrap())
                .args(["--exact", "backend::picker::limits::tests::picker_budget_uses_the_hard_limit_in_a_child", "--nocapture"])
                .env(BUDGET_CHILD_ENV, "1").output().unwrap();
            let report = format!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
            assert!(output.status.success() && report.contains("1 passed"), "{}", report);
            return;
        }
        let limit = Limit { soft: INITIAL_SOFT, hard: HARD_LIMIT };
        assert_eq!(unsafe { setrlimit(RLIMIT_NOFILE, &limit) }, 0);
        let budget = HARD_LIMIT as usize - DESCRIPTOR_RESERVE;
        let paths: Vec<_> = std::fs::read_dir(std::env::current_dir().unwrap().join("src/backend")).unwrap()
            .map(|entry| entry.unwrap().path()).filter(|path| path.is_file()).take(budget + 1).collect();
        assert_eq!(paths.len(), budget + 1, "read-only source files supply both sides of the budget boundary");
        let state = super::super::State::default();
        let soft_budget = INITIAL_SOFT as usize - DESCRIPTOR_RESERVE;
        let within_hard = state.check_budget(&paths[..soft_budget + 1], false);
        assert!(within_hard.is_ok(), "picker budget must use the hard limit: {:?}", within_hard);
        assert_eq!(current().unwrap().soft, HARD_LIMIT);
        let error = state.check_budget(&paths, false).unwrap_err();
        assert!(error.contains(&format!("selection limit of {} (open-file limit {}", budget, HARD_LIMIT)), "{}", error);
    }
}
