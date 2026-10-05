use super::*;
use crate::backend::testdir::TestDir;
use std::cell::RefCell;

// A UI tree and engine of their own, and a cache root inside the same sandbox.
struct Rig {
    dir: TestDir,
    ui: PathBuf,
    qjs: PathBuf,
    root: PathBuf,
}

fn rig(name: &str) -> Rig {
    let dir = TestDir::new(name);
    let ui = dir.join("ui");
    fs::create_dir_all(ui.join("vendor")).expect("vendor dir");
    fs::create_dir_all(ui.join("js")).expect("js dir");
    for relative in ["vendor/math.mjs", "vendor/mermaid.mjs", "vendor/figure-helper.mjs", "vendor/figure-bytecode.mjs", "vendor/figure-compile.mjs", "js/FigureWorker.mjs"] {
        fs::write(ui.join(relative), format!("// {relative}\n")).expect("source");
    }
    let qjs = dir.file("qjs", "engine\n");
    let root = dir.join("cache");
    fs::create_dir(&root).expect("cache root");
    Rig { dir, ui, qjs, root }
}

// The two smoke answers a healthy engine gives.
const SMOKE_ANSWER: &str = "{\"id\":1,\"svg\":\"<svg/>\"}\n{\"id\":2,\"svg\":\"<svg/>\"}\n";

// A jail stand-in: the compile call writes the blobs into its scratch dir, a smoke call answers what `smoke` says.
fn fake<'a>(calls: &'a RefCell<Vec<Vec<String>>>, blobs: &'a [&'a str], smoke: &'a dyn Fn(bool) -> Result<String, String>) -> impl Fn(&[String], &str) -> Result<String, String> + 'a {
    move |argv: &[String], _input: &str| {
        calls.borrow_mut().push(argv.to_vec());
        if argv.iter().any(|a| a.ends_with(COMPILE_NAME)) {
            let scratch = PathBuf::from(argv.last().expect("scratch arg"));
            for name in blobs {
                fs::write(scratch.join(name), format!("bytecode of {name}")).expect("fake blob");
            }
            return Ok(String::new());
        }
        smoke(argv.iter().any(|a| a.contains(".tmp-")))
    }
}

fn healthy(_: bool) -> Result<String, String> {
    Ok(SMOKE_ANSWER.to_string())
}

#[test]
fn the_compile_jail_binds_one_writable_directory_and_the_vendor_tree_read_only() {
    let argv = compile_argv(Path::new("/usr/bin/qjs"), Path::new("/ui/vendor"), Path::new("/cache/figures/k.tmp-1"));
    let joined = argv.join(" ");
    assert_eq!(argv[0], "prlimit");
    assert!(joined.contains("--unshare-all") && joined.contains("--clearenv"), "the same boundary as the render jail: {joined}");
    assert_eq!(argv.iter().filter(|a| *a == "--bind").count(), 1, "exactly one writable bind: {joined}");
    assert!(joined.contains("--bind /cache/figures/k.tmp-1 /cache/figures/k.tmp-1"), "and it is the scratch directory: {joined}");
    assert!(joined.contains("--ro-bind /ui/vendor /ui/vendor"), "the sources it compiles stay read-only: {joined}");
    assert!(!joined.contains("--ro-bind /usr/bin/qjs"), "an engine under /usr is already visible: {joined}");
    assert_eq!(argv[argv.len() - 4..], ["/usr/bin/qjs", "/ui/vendor/figure-compile.mjs", "/ui/vendor", "/cache/figures/k.tmp-1"]);
    let hooked = compile_argv(Path::new("/home/x/qjs"), Path::new("/ui/vendor"), Path::new("/c/k.tmp-1")).join(" ");
    assert!(hooked.contains("--ro-bind /home/x/qjs /home/x/qjs"), "a hook outside /usr is bound read-only: {hooked}");
}

#[test]
fn a_build_installs_a_verified_directory_and_sweeps_what_is_no_longer_current() {
    let rig = rig("figure-build-ok");
    let old = rig.root.join(figurecache::digest(b"an older key"));
    fs::create_dir(&old).expect("old key dir");
    fs::write(rig.root.join("notes.txt"), "not ours").expect("unrelated file");
    fs::create_dir(rig.root.join("keepme")).expect("unrelated dir");
    let calls = RefCell::new(Vec::new());
    let smoke: &dyn Fn(bool) -> Result<String, String> = &healthy;
    build(&rig.root, &rig.qjs, &rig.ui, &fake(&calls, &figurecache::BLOBS, smoke)).expect("a clean build");
    let key = figurecache::key(&rig.qjs, &rig.ui).expect("key");
    assert_eq!(figurecache::verified(&rig.root.join(&key), &key), Some(rig.root.join(&key)));
    assert_eq!(calls.borrow().len(), 3, "one compile, then the same two requests through bytecode and source");
    assert!(!old.exists(), "another key's directory is swept");
    assert!(rig.root.join("notes.txt").is_file() && rig.root.join("keepme").is_dir(), "nothing that is not ours is touched");
    assert!(!lock_path(&rig.root, &key).exists() && !failed_path(&rig.root, &key).exists(), "no lock or failure mark remains");
    let names: Vec<String> = fs::read_dir(&rig.root).expect("root").flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
    assert!(names.iter().all(|n| !n.contains(".tmp-") && !n.contains(".old-")), "no scratch remains: {names:?}");
    let again = RefCell::new(Vec::new());
    build(&rig.root, &rig.qjs, &rig.ui, &fake(&again, &figurecache::BLOBS, smoke)).expect("a second build");
    assert!(again.borrow().is_empty(), "a verified cache is not built again");
}

#[test]
fn a_corrupt_or_foreign_directory_in_the_way_is_replaced_and_never_followed() {
    let rig = rig("figure-build-replace");
    let key = figurecache::key(&rig.qjs, &rig.ui).expect("key");
    let outside = rig.dir.join("outside");
    fs::create_dir(&outside).expect("outside dir");
    fs::write(outside.join("precious"), "keep").expect("outside file");
    std::os::unix::fs::symlink(&outside, rig.root.join(&key)).expect("link at the key's path");
    let calls = RefCell::new(Vec::new());
    build(&rig.root, &rig.qjs, &rig.ui, &fake(&calls, &figurecache::BLOBS, &healthy)).expect("a build over a link");
    assert_eq!(figurecache::verified(&rig.root.join(&key), &key), Some(rig.root.join(&key)), "the link is replaced by a real directory");
    assert_eq!(fs::read_to_string(outside.join("precious")).expect("outside file"), "keep", "the link's target is untouched");
    fs::write(rig.root.join(&key).join("math.bc"), "corrupt").expect("corrupt blob");
    let again = RefCell::new(Vec::new());
    build(&rig.root, &rig.qjs, &rig.ui, &fake(&again, &figurecache::BLOBS, &healthy)).expect("a build over a corrupt directory");
    assert_eq!(figurecache::verified(&rig.root.join(&key), &key), Some(rig.root.join(&key)), "the corrupt directory is replaced whole");
}

#[test]
fn a_failed_build_leaves_nothing_live_and_is_not_retried_at_once() {
    for (label, blobs, smoke) in [
        ("a compile that writes one blob", &figurecache::BLOBS[..1], &healthy as &dyn Fn(bool) -> Result<String, String>),
        ("bytecode that answers differently", &figurecache::BLOBS[..], &|bytecode| Ok(if bytecode { "{\"id\":1,\"svg\":\"<svg>x</svg>\"}\n{\"id\":2,\"svg\":\"<svg/>\"}\n".to_string() } else { SMOKE_ANSWER.to_string() })),
        ("bytecode that answers nothing", &figurecache::BLOBS[..], &|bytecode| Ok(if bytecode { String::new() } else { SMOKE_ANSWER.to_string() })),
        ("a jail that fails", &figurecache::BLOBS[..], &|_| Err("jail refused".to_string())),
    ] {
        let rig = rig("figure-build-fail");
        let key = figurecache::key(&rig.qjs, &rig.ui).expect("key");
        let calls = RefCell::new(Vec::new());
        let result = build(&rig.root, &rig.qjs, &rig.ui, &fake(&calls, blobs, smoke));
        assert!(result.is_err(), "{label} fails the build");
        assert!(!rig.root.join(&key).exists(), "{label} installs nothing");
        assert!(failed_path(&rig.root, &key).is_file() && !lock_path(&rig.root, &key).exists(), "{label} leaves the failure mark and no lock");
        assert!(!wanted(&rig.root, &key), "{label} is not retried at once");
        let before = calls.borrow().len();
        build(&rig.root, &rig.qjs, &rig.ui, &fake(&calls, blobs, smoke)).expect("a repeat is quiet");
        assert_eq!(calls.borrow().len(), before, "{label} runs no jail again inside the retry window");
        let names: Vec<String> = fs::read_dir(&rig.root).expect("root").flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
        assert!(names.iter().all(|n| !n.contains(".tmp-")), "{label} leaves no scratch: {names:?}");
    }
}

// Backdates a path's modification time.
fn age_by(path: &Path, by: Duration) {
    let file = fs::File::open(path).expect("open for time");
    file.set_modified(SystemTime::now() - by).expect("set mtime");
}

#[test]
fn a_live_lock_defers_a_build_and_a_stale_one_or_an_old_failure_does_not() {
    let rig = rig("figure-build-lock");
    let key = figurecache::key(&rig.qjs, &rig.ui).expect("key");
    create_new(&lock_path(&rig.root, &key)).expect("a rival's lock");
    let calls = RefCell::new(Vec::new());
    build(&rig.root, &rig.qjs, &rig.ui, &fake(&calls, &figurecache::BLOBS, &healthy)).expect("deferred");
    assert!(calls.borrow().is_empty() && !wanted(&rig.root, &key), "a fresh lock means another builder is on it");
    age_by(&lock_path(&rig.root, &key), LOCK_STALE + Duration::from_secs(1));
    assert!(wanted(&rig.root, &key), "a lock older than any build is stale");
    build(&rig.root, &rig.qjs, &rig.ui, &fake(&calls, &figurecache::BLOBS, &healthy)).expect("built over a stale lock");
    assert_eq!(figurecache::verified(&rig.root.join(&key), &key), Some(rig.root.join(&key)));
    let failed = rig.dir.join("failed-mark");
    fs::write(&failed, "").expect("mark");
    age_by(&failed, FAILED_RETRY + Duration::from_secs(1));
    let other = rig.dir.join("cache2");
    fs::create_dir_all(&other).expect("second root");
    fs::copy(&failed, failed_path(&other, &key)).expect("copy mark");
    age_by(&failed_path(&other, &key), FAILED_RETRY + Duration::from_secs(1));
    assert!(wanted(&other, &key), "a failure is retried after its window");
}

#[test]
fn only_stale_scratch_and_other_keys_are_swept() {
    let rig = rig("figure-build-sweep");
    let current = figurecache::digest(b"current");
    let other = figurecache::digest(b"other");
    let stale_scratch = rig.root.join(format!("{other}.tmp-4242"));
    let fresh_scratch = rig.root.join(format!("{other}.tmp-4343"));
    let stale_lock = rig.root.join(format!("{other}.lock"));
    let live_lock = rig.root.join(format!("{current}.lock"));
    let failed = rig.root.join(format!("{other}.failed"));
    for dir in [&stale_scratch, &fresh_scratch] {
        fs::create_dir(dir).expect("scratch dir");
    }
    for file in [&stale_lock, &live_lock, &failed] {
        fs::write(file, "").expect("marker file");
    }
    for path in [&stale_scratch, &stale_lock] {
        age_by(path, SCRATCH_STALE + Duration::from_secs(1));
    }
    let strangers = [rig.root.join("notes.txt"), rig.root.join(format!("{other}.bak")), rig.root.join("0123.tmp-1")];
    for path in &strangers {
        fs::write(path, "").expect("stranger");
    }
    sweep(&rig.root, &current);
    assert!(!stale_scratch.exists() && !stale_lock.exists() && !failed.exists(), "stale scratch, a stale lock of another key and its failure mark go");
    assert!(fresh_scratch.exists(), "a builder that may still be running keeps its scratch");
    assert!(live_lock.exists(), "the current key's own lock is the builder's to remove");
    assert!(strangers.iter().all(|p| p.exists()), "names that are not ours are never touched");
}

#[test]
fn classify_reads_only_our_names() {
    let key = figurecache::digest(b"k");
    assert!(matches!(classify(&key), Some((_, Kind::Live))));
    assert!(matches!(classify(&format!("{key}.lock")), Some((_, Kind::Lock))));
    assert!(matches!(classify(&format!("{key}.failed")), Some((_, Kind::Failed))));
    assert!(matches!(classify(&format!("{key}.tmp-12")), Some((_, Kind::Scratch))));
    assert!(matches!(classify(&format!("{key}.old-12")), Some((_, Kind::Scratch))));
    for bad in ["", "manifest", &format!("{key}.tmp-"), &format!("{key}.tmp-1a"), &format!("{key}x"), &format!("{key}.lock2"), "x.lock"] {
        assert!(classify(bad).is_none(), "{bad:?}");
    }
}

// The jail itself, where bwrap can make a namespace: the scratch directory takes a write and nothing else on this box does.
#[test]
fn the_real_compile_jail_writes_only_its_scratch_directory() {
    // Only a box whose layout the jail supports can run it: Arch's, which the CI image has and a Debian host does not.
    let runnable = |argv: Vec<String>| Command::new(&argv[0]).args(&argv[1..]).stdout(Stdio::null()).stderr(Stdio::null()).status().map(|s| s.success()).unwrap_or(false);
    let probe_dir = TestDir::new("figure-jail-probe");
    if !sandbox::available() || !runnable(sandbox::wrap_compile(&["/bin/true".to_string()], &[], probe_dir.path())) {
        eprintln!("SKIP the compile jail cannot run here, so it was not run for real");
        return;
    }
    let dir = TestDir::new("figure-jail");
    let (scratch, sibling, vendor) = (dir.join("scratch"), dir.join("sibling"), dir.join("vendor"));
    for path in [&scratch, &sibling, &vendor] {
        fs::create_dir(path).expect("dir");
    }
    let script = "echo ok > \"$1/inside\"; echo no > \"$2/sibling\"; echo no > \"$3/vendor\"; echo no > /usr/flea-escape; echo no > /etc/flea-escape; exit 0";
    let inner: Vec<String> = ["/bin/sh", "-c", script, "sh"].iter().map(|s| s.to_string()).chain([&scratch, &sibling, &vendor].iter().map(|p| p.to_string_lossy().into_owned())).collect();
    let argv = sandbox::wrap_compile(&inner, &[vendor.as_path()], &scratch);
    let status = Command::new(&argv[0]).args(&argv[1..]).stdout(Stdio::null()).stderr(Stdio::null()).status().expect("jail starts");
    assert!(status.success(), "the jail ran the probe");
    assert!(scratch.join("inside").is_file(), "the scratch directory takes the write");
    assert!(!sibling.join("sibling").exists(), "a sibling directory does not");
    assert!(!vendor.join("vendor").exists(), "the read-only vendor bind does not");
    assert!(!Path::new("/usr/flea-escape").exists() && !Path::new("/etc/flea-escape").exists(), "the system trees do not");
}

#[test]
fn a_cache_root_that_is_gone_is_not_recreated_by_a_late_build() {
    let rig = rig("figure-build-gone");
    fs::remove_dir(&rig.root).expect("remove the root");
    let calls = RefCell::new(Vec::new());
    let result = build(&rig.root, &rig.qjs, &rig.ui, &fake(&calls, &figurecache::BLOBS, &healthy));
    assert!(result.is_err() && calls.borrow().is_empty(), "no jail runs without a root");
    assert!(!rig.root.exists(), "and the root stays gone");
    let made = rig.dir.join("deep/er/cache");
    assert!(make_root(&made).is_some() && made.is_dir(), "the launcher makes the root, parents included");
}
