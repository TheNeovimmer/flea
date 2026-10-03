// `flea --figure-helper`: maths and diagrams through quickjs-ng, jailed; see AGENTS.md "Markdown figures".
use crate::backend::sandbox;
use crate::paths;
use std::ffi::OsString;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

// Arch's extra/quickjs-ng, the only engine the vendored bundles run under.
pub const SYSTEM_QJS: &str = "/usr/bin/qjs";
// A test hook, and only a test hook: an absolute path to a qjs binary.
pub const QJS_ENV: &str = "FLEA_QJS";
// The helper lazy-loads vendor bundles and imports the shared post-processing module from the UI js directory.
pub const HELPER_NAME: &str = "figure-helper.mjs";
pub const WORKER_NAME: &str = "FigureWorker.mjs";
// Missing sandbox or engine refuses with this, never by running unsandboxed.
pub const REFUSED: i32 = 127;

// An absolute hook wins; anything else is the system binary.
pub fn qjs_from(value: Option<OsString>) -> PathBuf {
    match value {
        Some(raw) if !raw.is_empty() => {
            let candidate = PathBuf::from(raw);
            if candidate.is_absolute() {
                return candidate;
            }
            PathBuf::from(SYSTEM_QJS)
        }
        _ => PathBuf::from(SYSTEM_QJS),
    }
}

// The thin env-reading wrapper run() calls through resolve().
pub fn qjs_path() -> PathBuf {
    qjs_from(std::env::var_os(QJS_ENV))
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
pub fn resolve_with(sandbox_ok: bool, qjs: &Path, ui: Option<&Path>) -> Result<Vec<String>, String> {
    if !sandbox_ok {
        return Err(String::from("the figure helper needs bwrap and prlimit, and one of them is missing"));
    }
    if !qjs.is_file() {
        return Err(format!("the figure helper needs quickjs-ng at {}, and it is missing", qjs.display()));
    }
    let Some(root) = ui else {
        return Err(String::from("the figure helper is missing from the UI tree"));
    };
    let vendor = root.join("vendor");
    let helper = vendor.join(HELPER_NAME);
    if !helper.is_file() {
        return Err(format!("the figure helper is missing at {}", helper.display()));
    }
    let worker = root.join("js").join(WORKER_NAME);
    if !worker.is_file() {
        return Err(format!("the figure worker module is missing at {}", worker.display()));
    }
    Ok(figure_argv(qjs, &vendor))
}

// The thin env-reading wrapper run() calls.
pub fn resolve() -> Result<Vec<String>, String> {
    resolve_with(sandbox::available(), &qjs_path(), paths::ui_dir().as_deref())
}

pub fn run() -> i32 {
    match resolve() {
        Ok(argv) => {
            let mut cmd = Command::new(&argv[0]);
            cmd.args(&argv[1..]);
            // Exec replaces us, so the caller's stdin and stdout pipes reach qjs direct.
            let error = cmd.exec();
            eprintln!("flea: the figure helper could not start {}: {}", argv[0], error);
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

    #[test]
    fn an_absolute_hook_wins_and_anything_else_is_the_system_binary() {
        assert_eq!(qjs_from(None), PathBuf::from(SYSTEM_QJS));
        assert_eq!(qjs_from(Some(OsString::from(""))), PathBuf::from(SYSTEM_QJS));
        assert_eq!(qjs_from(Some(OsString::from("relative/qjs"))), PathBuf::from(SYSTEM_QJS));
        assert_eq!(
            qjs_from(Some(OsString::from("/tmp/flea-qjs-for-this-test"))),
            PathBuf::from("/tmp/flea-qjs-for-this-test")
        );
    }

    // A UI tree of its own, so the test names exactly what is missing.
    fn ui_tree(name: &str, with_helper: bool) -> crate::backend::testdir::TestDir {
        let dir = crate::backend::testdir::TestDir::new(name);
        let vendor = dir.path().join("vendor");
        std::fs::create_dir(&vendor).expect("test ui vendor dir");
        if with_helper {
            std::fs::write(vendor.join(HELPER_NAME), "// helper\n").expect("test helper file");
        }
        dir
    }

    #[test]
    fn a_missing_sandbox_is_refused_before_anything_is_probed() {
        let dir = ui_tree("figure-no-sandbox", true);
        let err = resolve_with(false, Path::new("/nonexistent-figure-qjs-for-this-test"), Some(dir.path()))
            .expect_err("without a sandbox the jail is refused first");
        // Sample refusal: "the figure helper needs bwrap and prlimit, and one of them is missing".
        assert!(err.contains("bwrap"), "the jail is refused first: {err}");
    }

    #[test]
    fn a_missing_engine_is_refused_without_running_anything_unsandboxed() {
        let dir = ui_tree("figure-qjs-missing", true);
        let err = resolve_with(true, Path::new("/nonexistent-figure-qjs-for-this-test"), Some(dir.path()))
            .expect_err("a missing qjs must refuse");
        assert!(err.contains("quickjs-ng"), "a missing engine must be named: {err}");
    }

    #[test]
    fn a_missing_helper_file_is_refused() {
        let dir = ui_tree("figure-helper-missing", false);
        // An existing file stands in for the engine, so only the helper is missing.
        std::fs::write(dir.path().join("qjs"), "#!/bin/sh\n").expect("test engine file");
        let err = resolve_with(true, &dir.path().join("qjs"), Some(dir.path()))
            .expect_err("a missing helper file must refuse");
        assert_eq!(err, format!("the figure helper is missing at {}", dir.path().join("vendor").join(HELPER_NAME).display()));
    }

    #[test]
    fn a_missing_worker_file_is_refused_before_starting_the_helper() {
        let dir = ui_tree("figure-worker-missing", true);
        let err = resolve_with(true, Path::new("/bin/true"), Some(dir.path()))
            .expect_err("a missing worker file must refuse");
        assert_eq!(err, format!("the figure worker module is missing at {}", dir.path().join("js").join(WORKER_NAME).display()));
    }

    #[test]
    fn a_missing_ui_tree_is_refused() {
        let err = resolve_with(true, Path::new("/bin/true"), None).expect_err("no UI tree must refuse");
        assert!(err.contains("UI tree"), "a missing UI tree must be named: {err}");
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
