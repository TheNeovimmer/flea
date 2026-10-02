use super::*;
use crate::backend::testdir::TestDir;
use std::sync::mpsc::channel;

#[test]
fn redo_accepts_a_born_less_record_of_an_unchanged_source() {
    let sandbox = TestDir::new("redo-born-less");
    let original = sandbox.file("original", "payload");
    let fresh = ItemIdentity::inspect(&original).unwrap();
    if fresh.born().is_none() {
        eprintln!("SKIP born-less redo: filesystem reports no birth time");
        return;
    }
    let (dev, ino, kind, len, mtime, changed, _) = fresh.to_parts();
    let recorded = ItemIdentity::from_parts(dev, ino, kind, len, mtime, changed, None);
    let copy = sandbox.join("copy");
    let step = Step::Copied {
        from: original.clone(), to: copy.clone(), source: recorded.clone(), created: fresh,
        manifest: None, manifest_nonce: None,
    };
    let parent = Some((sandbox.path().to_path_buf(), ItemIdentity::inspect(sandbox.path()).unwrap()));
    let replay = Replay::from_steps("copy".into(), vec![(step, Some(recorded), parent)]);
    let (tx, _rx) = channel();
    let (entry, _, result) = replay.run(1, &AtomicBool::new(false), &tx);
    assert_eq!(result.expect("an unchanged source with no recorded birth time must redo"), "copy");
    assert_eq!(entry.steps.len(), 1);
    assert_eq!(std::fs::read_to_string(copy).unwrap(), "payload");
    assert_eq!(std::fs::read_to_string(original).unwrap(), "payload");
}
