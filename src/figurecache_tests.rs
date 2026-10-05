use super::*;
use crate::backend::testdir::TestDir;

// A UI tree and engine of their own, so each test changes exactly one input.
fn tree(name: &str) -> (TestDir, PathBuf, PathBuf) {
    let dir = TestDir::new(name);
    let ui = dir.join("ui");
    fs::create_dir_all(ui.join("vendor")).expect("vendor dir");
    fs::create_dir_all(ui.join("js")).expect("js dir");
    for relative in KEYED_SOURCES {
        fs::write(ui.join(relative), format!("// {relative}\n")).expect("keyed source");
    }
    let qjs = dir.file("qjs", "engine one\n");
    (dir, ui, qjs)
}

#[test]
fn a_digest_tells_every_byte_and_the_length_apart() {
    assert_eq!(digest(b"").len(), KEY_HEX_CHARS);
    let base = digest(b"flea figure bytecode");
    assert_eq!(base, digest(b"flea figure bytecode"), "the same bytes, the same digest");
    assert_ne!(base, digest(b"flea figure bytecodf"), "one changed byte");
    assert_ne!(digest(b""), digest(&[0]), "a zero byte is not nothing");
    assert_ne!(digest(&[0u8; 8]), digest(&[0u8; 16]), "zero words of different length");
    assert_ne!(digest(&[0u8; 7]), digest(&[0u8; 8]), "a short tail is not a whole word");
    // The sample the manifest and the key both rest on; a change here invalidates every cache on purpose.
    assert_eq!(digest(b"123456789"), "979b431a1b9f2ae3c284e78339beb955");
}

#[test]
fn a_file_digests_as_its_bytes_do_across_the_read_chunk() {
    let dir = TestDir::new("figure-digest-chunk");
    for size in [0, 7, 8, READ_CHUNK_BYTES - 1, READ_CHUNK_BYTES, READ_CHUNK_BYTES + 9, 2 * READ_CHUNK_BYTES] {
        let bytes: Vec<u8> = (0..size).map(|i| (i % 251) as u8).collect();
        let path = dir.join(&format!("blob-{size}"));
        fs::write(&path, &bytes).expect("blob");
        assert_eq!(file_digest(&path), Some((size as u64, digest(&bytes))), "size {size}");
    }
}

#[test]
fn a_digest_reads_only_a_plain_file() {
    let dir = TestDir::new("figure-digest-plain");
    let target = dir.file("target", "bytes\n");
    std::os::unix::fs::symlink(&target, dir.join("link")).expect("link");
    assert!(file_digest(&target).is_some());
    assert_eq!(file_digest(&dir.join("link")), None, "a final symlink is never followed");
    assert_eq!(file_digest(dir.path()), None, "a directory has no digest");
    assert_eq!(file_digest(&dir.join("missing")), None);
}

#[test]
fn the_key_follows_the_engine_and_every_keyed_source() {
    let (dir, ui, qjs) = tree("figure-key");
    let base = key(&qjs, &ui).expect("a key");
    assert!(is_key(&base));
    assert_eq!(key(&qjs, &ui), Some(base.clone()), "the same inputs, the same key");
    for relative in KEYED_SOURCES {
        let path = ui.join(relative);
        let original = fs::read(&path).expect("source");
        fs::write(&path, [original.as_slice(), b" "].concat()).expect("changed source");
        let changed = key(&qjs, &ui);
        assert!(changed.is_some(), "{relative} changed still keys");
        assert_ne!(changed, Some(base.clone()), "{relative} is part of the key");
        fs::write(&path, original).expect("restored source");
    }
    fs::write(&qjs, "engine two\n").expect("changed engine");
    let other_engine = key(&qjs, &ui);
    assert!(other_engine.is_some(), "another engine still keys");
    assert_ne!(other_engine, Some(base.clone()), "the engine binary is part of the key");
    fs::write(&qjs, "engine one\n").expect("restored engine");
    assert_eq!(key(&qjs, &ui), Some(base.clone()));
    // An engine library beside the binary is part of the build identity too.
    fs::create_dir_all(dir.join("home/bin")).expect("bin dir");
    fs::create_dir(dir.join("home/lib")).expect("lib dir");
    let beside = dir.file("home/bin/qjs", "engine one\n");
    let without_library = key(&beside, &ui).expect("a key");
    fs::write(dir.join("home/lib/libqjs.so.0.1"), "library one").expect("library");
    let with_library = key(&beside, &ui).expect("a key");
    assert_ne!(with_library, without_library, "a library beside the engine is part of the key");
    fs::write(dir.join("home/lib/libqjs.so.0.1"), "library two").expect("changed library");
    let other_library = key(&beside, &ui);
    assert!(other_library.is_some(), "another library still keys");
    assert_ne!(other_library, Some(with_library), "so is its content");
}

#[test]
fn a_missing_input_gives_no_key() {
    let (dir, ui, qjs) = tree("figure-key-missing");
    fs::remove_file(ui.join("vendor/mermaid.mjs")).expect("remove a source");
    assert_eq!(key(&qjs, &ui), None, "a tree missing a keyed source");
    assert_eq!(key(&dir.join("no-engine"), &ui), None, "a missing engine");
}

// Sample input: the text manifest_text writes.
fn sample_blobs() -> Vec<(String, u64, String)> {
    vec![("math.bc".into(), 12, digest(b"math")), ("mermaid.bc".into(), 34, digest(b"mermaid"))]
}

#[test]
fn a_manifest_reads_back_what_was_written_and_nothing_else() {
    let key = digest(b"key");
    let text = manifest_text(&key, &sample_blobs());
    assert_eq!(parse_manifest(&text), Some((key.clone(), sample_blobs())));
    for bad in [
        text.replacen("flea-figures 1", "flea-figures 2", 1),
        text.replacen("key ", "kay ", 1),
        text.lines().take(3).collect::<Vec<_>>().join("\n"),
        text.replacen("math.bc", "evil.bc", 1),
        text.replacen("math.bc 12", "math.bc twelve", 1),
        format!("{text}mermaid.bc 1 x extra\n"),
        String::new(),
    ] {
        assert_eq!(parse_manifest(&bad), None, "{bad:?}");
    }
}

// A cache directory holding exactly the blobs its manifest names.
fn cache_dir(dir: &TestDir) -> (PathBuf, String) {
    let key = digest(b"the key");
    let live = dir.join(&key);
    fs::create_dir(&live).expect("live dir");
    let mut blobs = Vec::new();
    for name in BLOBS {
        let bytes = format!("bytecode of {name}").into_bytes();
        fs::write(live.join(name), &bytes).expect("blob");
        blobs.push((name.to_string(), bytes.len() as u64, digest(&bytes)));
    }
    fs::write(live.join(MANIFEST), manifest_text(&key, &blobs)).expect("manifest");
    (live, key)
}

#[test]
fn a_directory_is_trusted_only_when_it_is_what_its_manifest_says() {
    let dir = TestDir::new("figure-verified");
    let (live, key) = cache_dir(&dir);
    assert_eq!(verified(&live, &key), Some(live.clone()));
    assert_eq!(verified(&live, &digest(b"another key")), None, "a manifest for another key is foreign");
    let blob = live.join("math.bc");
    let original = fs::read(&blob).expect("blob");
    fs::write(&blob, &original[..original.len() - 1]).expect("truncated");
    assert_eq!(verified(&live, &key), None, "a short blob");
    let mut flipped = original.clone();
    flipped[3] ^= 1;
    fs::write(&blob, &flipped).expect("flipped");
    assert_eq!(verified(&live, &key), None, "a flipped byte of the same size");
    fs::remove_file(&blob).expect("remove blob");
    std::os::unix::fs::symlink(dir.file("elsewhere", &String::from_utf8(original.clone()).expect("text")), &blob).expect("link");
    assert_eq!(verified(&live, &key), None, "a symlinked blob, even with the right bytes behind it");
    fs::remove_file(&blob).expect("remove link");
    fs::write(&blob, &original).expect("restored");
    assert_eq!(verified(&live, &key), Some(live.clone()));
    fs::write(live.join(MANIFEST), "x".repeat(MAX_MANIFEST_BYTES as usize + 1)).expect("oversize manifest");
    assert_eq!(verified(&live, &key), None, "an oversize manifest is not read");
    fs::remove_file(live.join(MANIFEST)).expect("remove manifest");
    assert_eq!(verified(&live, &key), None, "no manifest");
}

#[test]
fn a_linked_key_directory_is_refused_even_with_a_matching_manifest() {
    let dir = TestDir::new("figure-verified-link");
    let (live, key) = cache_dir(&dir);
    let moved = dir.join("elsewhere");
    fs::rename(&live, &moved).expect("move the real directory away");
    std::os::unix::fs::symlink(&moved, &live).expect("a link at the key's path");
    assert_eq!(verified(&moved, &key), Some(moved.clone()), "the directory behind the link is itself fine");
    assert_eq!(verified(&live, &key), None, "a link at the key directory is never followed");
}

#[test]
fn only_a_hex_key_names_a_cache_directory() {
    assert!(is_key(&digest(b"x")));
    for bad in ["", "abc", "0123456789ABCDEF0123456789abcdef", "0123456789abcdef0123456789abcdeg", "0123456789abcdef0123456789abcdef0"] {
        assert!(!is_key(bad), "{bad:?}");
    }
}
