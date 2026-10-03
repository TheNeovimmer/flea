// Pure argv fixtures and isolated fault doubles pin the production owner-end branches.
use super::owner_args;
use std::process::Command;

const FAULT_WATCHDOG_SECONDS: u32 = 15;
const EMFILE: i32 = 24;
const EAGAIN: i32 = 11;
const EIO: i32 = 5;

#[test]
fn only_the_production_owner_argument_pair_is_an_owner() {
    let fixtures: &[(&[u8], bool)] = &[
        (b"/usr/bin/flea\0--clip-own", true),
        (b"/usr/bin/flea\0--clip-own\0extra", false),
        (b"/usr/bin/flea\0--backend", false),
        (b"", false),
    ];
    for (command, expected) in fixtures {
        // Sample input: /usr/bin/flea\0--clip-own, after removing procfs's terminal NUL.
        let arguments: Vec<_> = command.split(|byte| *byte == 0).collect();
        assert_eq!(owner_args(&arguments), *expected, "owner argv fixture {:?}", command);
    }
}

fn check_fault(mode: &str, component: &str, error: i32, counts: &str) {
    let root = std::env::temp_dir().join(format!("flea-clip-end-faults-{}-{}", std::process::id(), mode));
    std::fs::create_dir(&root).unwrap();
    let program = root.join("faults");
    let source = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src/clip/end_fault_fixture.rs");
    let compiler = std::env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
    let compiled = Command::new("timeout").arg(FAULT_WATCHDOG_SECONDS.to_string()).arg(compiler)
        .arg("--edition=2021").arg(source).arg("-o").arg(&program).output().unwrap();
    assert!(compiled.status.success(), "{}", String::from_utf8_lossy(&compiled.stderr));
    let result = Command::new("timeout").arg(FAULT_WATCHDOG_SECONDS.to_string()).arg(&program).arg(mode).output().unwrap();
    std::fs::remove_dir_all(root).unwrap();
    assert!(result.status.success(), "{}", String::from_utf8_lossy(&result.stderr));
    assert_eq!(String::from_utf8(result.stdout).unwrap(), format!("{}: {}\n", mode, counts));
    assert_eq!(String::from_utf8(result.stderr).unwrap(),
        format!("flea: clipboard owner-end {} failed: {}\n", component, std::io::Error::from_raw_os_error(error)),
        "the failed component must emit one diagnostic with its OS error");
}

#[test]
fn eventfd_failure_reports_once_across_retries() {
    check_fault("eventfd", "eventfd", EMFILE,
        "eventfd_calls=2 spawn_calls=0 poll_calls=0 wake=false worker_started=false");
}

#[test]
fn thread_spawn_failure_reports_once_across_retries() {
    check_fault("spawn", "thread spawn", EAGAIN,
        "eventfd_calls=2 spawn_calls=2 poll_calls=0 wake=false worker_started=false");
}

#[test]
fn terminal_poll_error_reports_once() {
    check_fault("poll", "poll", EIO,
        "eventfd_calls=1 spawn_calls=1 poll_calls=1 wake=true worker_started=true");
}

#[test]
fn interrupted_poll_retries_without_a_diagnostic() {
    check_fault("interrupted", "poll", EIO,
        "eventfd_calls=1 spawn_calls=1 poll_calls=2 wake=true worker_started=true");
}
