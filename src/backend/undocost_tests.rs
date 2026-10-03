// What one shared-journal operation costs: work counts per operation, never wall time.
use super::undoprobe::{self, Counts};
use super::undoshare::{claim_redo, claim_undo, finish_redone, finish_undone, live_nonces, push_entry, redo_info, Doc, PushResult, Shared, StoredRedo, JOURNAL_FILE};
use super::undocodec::encode;
use crate::backend::testdir::TestDir;
use crate::backend::undo::{Entry, ItemIdentity, Step};
use crate::error::FleaError;
use crate::jsondoc::render;
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;

const STEPS_PER_MOVE: usize = 1000;
const DEVICE: u64 = 66;
const REGULAR: u32 = 0o100000;
const BASE_SECONDS: i64 = 1_790_000_000;
// One 1,000-file move is about 0.93 MiB of journal, so these make about 1, 8 and 26 MB.
const JOURNAL_ENTRY_COUNTS: [usize; 3] = [1, 8, 28];
// The count tests use a journal of this many entries of FIXTURE_STEPS steps, a few thousand stored steps.
const FIXTURE_ENTRIES: usize = 5;
const FIXTURE_STEPS: usize = 200;

// One identity per (salt, n), so two salts never collide and one pair always matches itself.
pub(super) fn identity(salt: u64, n: u64) -> ItemIdentity {
    let at = salt * 1_000_000 + n;
    ItemIdentity::from_parts(DEVICE, at, REGULAR, 4096 + n, (BASE_SECONDS + n as i64, 123_456_789),
        (BASE_SECONDS + salt as i64, 987_654_321), Some((BASE_SECONDS as u64 - 5, n as u32)))
}

// The after identity of step n in a move entry of the given salt; a later move starts from it.
fn after_of(salt: u64, n: u64) -> ItemIdentity {
    identity(salt + 500, n)
}

// A bulk move of `steps` files into one folder, as the perf harness's 1,000-file move records it.
fn move_entry(salt: u64, steps: usize) -> Entry {
    let steps = (0..steps as u64).map(|n| Step::Moved {
        from: PathBuf::from(format!("/home/gm/Work/project-{}/assets/images/file-{:05}.png", salt, n)),
        to: PathBuf::from(format!("/home/gm/Work/archive-{}/assets/images/file-{:05}.png", salt, n)),
        before: identity(salt, n),
        after: after_of(salt, n),
    }).collect();
    Entry { op: format!("move {}", salt), steps }
}

// Writes a journal of these entries the way the old and new code both render it.
fn write_journal(shared_dir: &std::path::Path, undo: Vec<Entry>, redo: Vec<StoredRedo>) -> u64 {
    let doc = Doc { undo, redo, push_gen: 3 };
    let text = render(&encode(&doc));
    let path = shared_dir.join(JOURNAL_FILE);
    let mut file = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&path).unwrap();
    use std::io::Write;
    file.write_all(text.as_bytes()).unwrap();
    text.len() as u64
}

fn stored_steps(entries: usize, steps: usize) -> u64 {
    (entries * steps) as u64
}

fn fixture(name: &str) -> (TestDir, Shared, u64) {
    let sandbox = TestDir::new(name);
    let shared = Shared::at(sandbox.path().join("runtime")).unwrap();
    let undo = (0..FIXTURE_ENTRIES as u64).map(|salt| move_entry(salt + 1, FIXTURE_STEPS)).collect();
    let size = write_journal(&sandbox.path().join("runtime"), undo, Vec::new());
    (sandbox, shared, size)
}

// A second move of files an earlier entry moved: each of its steps starts where one stored step ended.
fn remove_again(steps: usize) -> Entry {
    let steps = (0..steps as u64).map(|n| {
        let salt = n / FIXTURE_STEPS as u64 + 1;
        let at = n % FIXTURE_STEPS as u64;
        Step::Moved {
            from: PathBuf::from(format!("/home/gm/Work/archive-{}/assets/images/file-{:05}.png", salt, at)),
            to: PathBuf::from(format!("/home/gm/Work/second-{}/file-{:05}.png", salt, at)),
            before: after_of(salt, at),
            after: identity(salt + 900, at),
        }
    }).collect();
    Entry { op: "move again".to_string(), steps }
}

fn rename_entry() -> Entry {
    Entry { op: "rename".to_string(), steps: vec![Step::Moved {
        from: PathBuf::from("/home/gm/Work/a.txt"), to: PathBuf::from("/home/gm/Work/b.txt"),
        before: identity(77, 1), after: identity(78, 1),
    }] }
}

fn measured<T>(work: impl FnOnce() -> T) -> (T, Counts) {
    undoprobe::reset();
    let out = work();
    (out, undoprobe::snapshot())
}

fn pairs_of(entry: &Entry) -> Vec<(ItemIdentity, ItemIdentity)> {
    entry.steps.iter().filter_map(|step| match step {
        Step::Moved { before, after, .. } => Some((before.clone(), after.clone())),
        _ => None,
    }).collect()
}

fn file_len(shared_dir: &std::path::Path) -> u64 {
    std::fs::metadata(shared_dir.join(JOURNAL_FILE)).unwrap().len()
}

#[test]
fn one_push_decodes_once_renders_once_and_reads_the_file_once() {
    let (sandbox, shared, size) = fixture("ucost-push-one");
    let (result, counts) = measured(|| push_entry(&shared, &rename_entry()));
    assert!(matches!(result, Ok(PushResult::Stored)));
    assert_eq!(counts.decodes, 1, "one decode of the file");
    assert_eq!(counts.renders, 1, "one render of the document");
    assert_eq!(counts.bytes_read, size, "the file is read once");
    assert_eq!(counts.bytes_written, file_len(&sandbox.path().join("runtime")), "the file is written once");
}

#[test]
fn a_push_of_a_thousand_moves_visits_each_stored_step_once() {
    let (_sandbox, shared, _) = fixture("ucost-push-move");
    let stored = stored_steps(FIXTURE_ENTRIES, FIXTURE_STEPS);
    let entry = remove_again(STEPS_PER_MOVE);
    let (result, counts) = measured(|| push_entry(&shared, &entry));
    assert!(matches!(result, Ok(PushResult::Stored)));
    assert!(counts.visits <= stored, "rebase visited {} steps of a journal of {}", counts.visits, stored);
    // Each stored identity is compared with the moves that name its own inode only.
    assert!(counts.compares <= 2 * stored, "{} identity comparisons for {} stored steps", counts.compares, stored);
    assert_eq!((counts.decodes, counts.renders), (1, 1));
}

#[test]
fn an_undo_of_a_thousand_moves_visits_each_stored_step_once() {
    let (_sandbox, shared, _) = fixture("ucost-undo");
    let big = move_entry(40, STEPS_PER_MOVE);
    assert!(matches!(push_entry(&shared, &big), Ok(PushResult::Stored)));
    let stored = stored_steps(FIXTURE_ENTRIES, FIXTURE_STEPS);
    let (claimed, counts) = measured(|| claim_undo(&shared));
    let (entry, gen) = claimed.unwrap().unwrap();
    assert_eq!((counts.decodes, counts.renders), (1, 1), "a claim decodes and renders once");
    let changes: Vec<_> = pairs_of(&entry).into_iter().map(|(old, new)| (new, old)).collect();
    let (done, counts) = measured(|| finish_undone(&shared, Some(entry), &changes, gen));
    assert!(done.is_ok());
    assert!(counts.visits <= stored, "rebase visited {} steps of a journal of {}", counts.visits, stored);
    assert_eq!((counts.decodes, counts.renders), (1, 1), "a finish decodes and renders once");
}

#[test]
fn a_finished_redo_visits_each_stored_step_once() {
    let (_sandbox, shared, _) = fixture("ucost-redo");
    let stored = stored_steps(FIXTURE_ENTRIES, FIXTURE_STEPS);
    let entry = remove_again(STEPS_PER_MOVE);
    let changes = pairs_of(&entry);
    let (done, counts) = measured(|| finish_redone(&shared, entry, &changes, false));
    assert!(done.is_ok());
    assert!(counts.visits <= stored, "rebase visited {} steps of a journal of {}", counts.visits, stored);
    assert_eq!((counts.decodes, counts.renders), (1, 1));
}

#[test]
fn a_read_only_question_decodes_once_and_never_renders() {
    let (sandbox, shared, size) = fixture("ucost-read");
    let (live, counts) = measured(|| live_nonces(&shared));
    assert!(live.is_some());
    assert_eq!((counts.decodes, counts.renders, counts.bytes_read, counts.bytes_written), (1, 0, size, 0));
    write_journal(&sandbox.path().join("runtime"), Vec::new(),
        vec![StoredRedo::Err(FleaError { where_: "redo".into(), path: String::new(), msg: "nothing recorded".into() })]);
    let size = file_len(&sandbox.path().join("runtime"));
    let (info, counts) = measured(|| redo_info(&shared));
    assert!(info.is_err());
    assert_eq!((counts.decodes, counts.renders, counts.bytes_read, counts.bytes_written), (1, 0, size, 0));
    let (claimed, counts) = measured(|| claim_redo(&shared));
    assert!(matches!(claimed, Ok(Some(StoredRedo::Err(_)))));
    assert_eq!((counts.decodes, counts.renders, counts.bytes_read), (1, 1, size));
}

// Information for the controller: the cost of one operation by journal size. It asserts nothing about time.
#[test]
#[ignore]
fn measure_the_cost_of_one_operation_by_journal_size() {
    for count in JOURNAL_ENTRY_COUNTS {
        for (name, kind) in [("rename", 0), ("move1000", 1), ("undo1000", 2)] {
            let sandbox = TestDir::new("ucost-measure");
            let dir = sandbox.path().join("runtime");
            let shared = Shared::at(dir.clone()).unwrap();
            let entries = (0..count as u64).map(|salt| move_entry(salt + 1, STEPS_PER_MOVE)).collect();
            let size = write_journal(&dir, entries, Vec::new());
            if kind == 0 {
                let text = std::fs::read_to_string(dir.join(JOURNAL_FILE)).unwrap();
                let parsed = std::time::Instant::now();
                let super::undostage::Read::Doc(doc) = super::undostage::read(&text) else { panic!("the fixture decodes") };
                let decoded = parsed.elapsed().as_millis();
                let rendered = std::time::Instant::now();
                let staged = super::undostage::Staged::new(&doc);
                let render_ms = rendered.elapsed().as_millis();
                let joined = std::time::Instant::now();
                let joined_len = staged.text().len();
                println!("PARTS entries={} parse_and_decode_ms={} render_pieces_ms={} join_ms={} bytes={}", count, decoded, render_ms, joined.elapsed().as_millis(), joined_len);
            }
            let began = std::time::Instant::now();
            undoprobe::reset();
            match kind {
                0 => { let _ = push_entry(&shared, &rename_entry()); }
                1 => { let _ = push_entry(&shared, &move_entry(900, STEPS_PER_MOVE)); }
                _ => {
                    let (entry, gen) = claim_undo(&shared).unwrap().unwrap();
                    let changes: Vec<_> = pairs_of(&entry).into_iter().map(|(old, new)| (new, old)).collect();
                    let _ = finish_undone(&shared, Some(entry), &changes, gen);
                }
            }
            let took = began.elapsed().as_millis();
            let counts = undoprobe::snapshot();
            println!("MEASURE size={} entries={} op={} ms={} {:?}", size, count, name, took, counts);
        }
    }
}
