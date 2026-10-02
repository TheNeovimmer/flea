// `flea --figure-helper`: maths and diagrams through quickjs-ng, jailed; see AGENTS.md "Markdown figures".
use crate::backend::sandbox;
use crate::paths;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

// Arch's extra/quickjs-ng, the only engine the vendored bundles run under.
pub const SYSTEM_QJS: &str = "/usr/bin/qjs";
// A test hook, and only a test hook: an absolute path to a qjs binary.
pub const QJS_ENV: &str = "FLEA_QJS";
// The helper module beside the bundles it lazy-loads, and the shared
// post-processing module one directory up that both node and qjs import.
pub const HELPER_NAME: &str = "figure-helper.mjs";
pub const WORKER_NAME: &str = "FigureWorker.mjs";
// Missing sandbox or engine refuses with this, never by running unsandboxed.
pub const REFUSED: i32 = 127;

// An absolute FLEA_QJS wins; anything else is the system binary.
pub fn qjs_path() -> PathBuf {
    match std::env::var_os(QJS_ENV) {
        Some(value) if !value.is_empty() => {
            let candidate = PathBuf::from(value);
            if candidate.is_absolute() {
                return candidate;
            }
            PathBuf::from(SYSTEM_QJS)
        }
        _ => PathBuf::from(SYSTEM_QJS),
    }
}

// The UI tree's vendor/ directory, resolved the way the GUI's own root is.
pub fn vendor_dir() -> Option<PathBuf> {
    let vendor = paths::ui_dir()?.join("vendor");
    vendor.join(HELPER_NAME).is_file().then_some(vendor)
}

// True when the jail's read-only /usr already covers the binary.
fn under_usr(path: &Path) -> bool {
    path.starts_with("/usr/")
}

// The full argv: prlimit caps, the jail flags, the read-only binds, then qjs.
pub fn figure_argv(qjs: &Path, vendor: &Path) -> Vec<String> {
    let mut binds: Vec<PathBuf> = vec![vendor.to_path_buf()];
    // Sample layout: vendor is <ui>/vendor, so its parent holds js/FigureWorker.mjs.
    if let Some(ui) = vendor.parent() {
        binds.push(ui.join("js").join(WORKER_NAME));
    }
    if !under_usr(qjs) {
        binds.push(qjs.to_path_buf());
    }
    let inner = vec![
        qjs.to_string_lossy().into_owned(),
        vendor.join(HELPER_NAME).to_string_lossy().into_owned(),
    ];
    let refs: Vec<&Path> = binds.iter().map(PathBuf::as_path).collect();
    sandbox::wrap_readonly_extra(&inner, &refs)
}

// Checked in order, so a missing sandbox refuses before anything is probed.
pub fn resolve() -> Result<Vec<String>, String> {
    if !sandbox::available() {
        return Err(String::from("the figure helper needs bwrap and prlimit, and one of them is missing"));
    }
    let qjs = qjs_path();
    if !qjs.is_file() {
        return Err(format!("the figure helper needs quickjs-ng at {}, and it is missing", qjs.display()));
    }
    let Some(vendor) = vendor_dir() else {
        return Err(String::from("the figure helper is missing from the UI tree"));
    };
    Ok(figure_argv(&qjs, &vendor))
}

pub fn run() -> i32 {
    match resolve() {
        Ok(argv) => {
            let mut cmd = Command::new(&argv[0]);
            cmd.args(&argv[1..]);
            // Exec replaces us, so the caller's stdin and stdout pipes reach qjs direct.
            let _ = cmd.exec();
            eprintln!("flea: the figure helper could not be started");
            REFUSED
        }
        Err(message) => {
            eprintln!("flea: {}", message);
            REFUSED
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Both cases sit in one test because FLEA_QJS is process wide and cargo runs tests in threads.
    #[test]
    fn the_hook_rules_the_engine_path_and_a_missing_engine_is_refused() {
        assert_eq!(qjs_path(), PathBuf::from(SYSTEM_QJS));
        std::env::set_var(QJS_ENV, "/tmp/flea-qjs-for-this-test");
        assert_eq!(qjs_path(), PathBuf::from("/tmp/flea-qjs-for-this-test"));
        std::env::set_var(QJS_ENV, "relative/qjs");
        assert_eq!(qjs_path(), PathBuf::from(SYSTEM_QJS));
        std::env::set_var(QJS_ENV, "");
        assert_eq!(qjs_path(), PathBuf::from(SYSTEM_QJS));
        // A UI tree of its own, so the only thing missing is the engine itself.
        let dir = crate::backend::testdir::TestDir::new("figure-qjs-missing");
        let boot = dir.path().join("boot");
        std::fs::create_dir(&boot).expect("test ui boot dir");
        std::fs::write(boot.join("shell.qml"), "//@ pragma ShellId flea\n").expect("test ui entry");
        let vendor = dir.path().join("vendor");
        std::fs::create_dir(&vendor).expect("test ui vendor dir");
        std::fs::write(vendor.join(HELPER_NAME), "// helper\n").expect("test helper file");
        std::env::set_var("FLEA_UI", dir.path());
        std::env::set_var(QJS_ENV, "/nonexistent-figure-qjs-for-this-test");
        let err = resolve().expect_err("a missing qjs must refuse");
        // Sample messages: "needs bwrap and prlimit" without a sandbox, "needs quickjs-ng" with one.
        if sandbox::available() {
            assert!(err.contains("quickjs-ng"), "a missing engine must be named: {err}");
        } else {
            assert!(err.contains("bwrap"), "without a sandbox the jail is refused first: {err}");
        }
        std::env::remove_var(QJS_ENV);
        std::env::remove_var("FLEA_UI");
    }

    #[test]
    fn only_a_usr_binary_is_already_covered_by_the_read_only_usr_bind() {
        assert!(under_usr(Path::new("/usr/bin/qjs")));
        assert!(!under_usr(Path::new("/home/gm/.superpowers/tools/qjs")));
    }

    // Sample layout: vendor /ui/vendor with the worker at /ui/js/FigureWorker.mjs.
    fn argv_for(qjs: &str) -> Vec<String> {
        figure_argv(Path::new(qjs), Path::new("/ui/vendor"))
    }

    #[test]
    fn the_argv_carries_the_caps_the_flags_both_binds_and_qjs_last() {
        let got = argv_for("/usr/bin/qjs");
        let joined = got.join(" ");
        assert_eq!(got[0], "prlimit");
        assert!(got.iter().any(|a| a == "--cpu=30"), "the runaway bound: {joined}");
        assert!(got.iter().any(|a| a == "--as=2147483648"), "the address-space cap: {joined}");
        assert!(got.iter().any(|a| a == "--unshare-all"), "the namespace flags: {joined}");
        assert!(got.iter().any(|a| a == "--clearenv"), "no inherited environment: {joined}");
        assert!(joined.contains("--ro-bind /usr /usr"), "system libraries stay visible: {joined}");
        assert!(joined.contains("--ro-bind /ui/vendor /ui/vendor"), "the bundles: {joined}");
        assert!(joined.contains("--ro-bind /ui/js/FigureWorker.mjs /ui/js/FigureWorker.mjs"), "the shared post-processing: {joined}");
        assert!(!joined.contains("--bind "), "nothing writable: {joined}");
        assert!(!got.iter().any(|a| a.contains("FLEA_QJS")), "the hook never reaches argv: {joined}");
        let tail = &got[got.len() - 2..];
        assert_eq!(tail, ["/usr/bin/qjs", "/ui/vendor/figure-helper.mjs"]);
    }

    #[test]
    fn a_hook_outside_usr_is_bound_read_only_beside_the_vendor_tree() {
        let got = argv_for("/home/gm/.superpowers/tools/qjs");
        let joined = got.join(" ");
        assert!(joined.contains("--ro-bind /home/gm/.superpowers/tools/qjs /home/gm/.superpowers/tools/qjs"), "{joined}");
        assert!(joined.contains("--ro-bind /ui/vendor /ui/vendor"), "{joined}");
    }

}
