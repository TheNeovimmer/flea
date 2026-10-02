use super::*;
use crate::backend::testdir::TestDir;

#[test]
fn inaccessible_selection_reports_plain_cause_and_recovers() {
    use std::os::unix::fs::PermissionsExt;
    let dir = TestDir::new("picker-plain-error");
    let parent = dir.dir("locked");
    let path = dir.file("locked/item", "retained contents");
    let mut state = State::default();
    let cancel = Cancellation::default();
    let mark = format!(r#"{{"op":"mark","id":1,"path":"{}"}}"#, escape(&path.to_string_lossy()));
    dir.assert_contains(&parent);
    std::fs::set_permissions(&parent, std::fs::Permissions::from_mode(0o0)).unwrap();
    let refused = state.handle(&mark, &cancel);
    std::fs::set_permissions(&parent, std::fs::Permissions::from_mode(0o700)).unwrap();
    assert_eq!(refused.unwrap_err(), format!("Could not inspect {}: permission denied", path.display()));
    assert!(state.marks.is_empty());
    state.handle(&mark, &cancel).unwrap();
    assert_eq!(std::fs::read(path).unwrap(), b"retained contents");
}

#[test]
fn marks_keep_order_across_navigation_and_drop_missing_or_replaced_items() {
    let dir = TestDir::new("picker-marks");
    let first = dir.file("first", "one");
    let second = dir.file("second", "two");
    let mut state = State::default();
    let cancel = Cancellation::default();
    for path in [&first, &second] {
        let line = format!(r#"{{"op":"mark","id":1,"path":"{}","multiple":true}}"#, escape(&path.to_string_lossy()));
        assert!(state.handle(&line, &cancel).unwrap().contains(r#""removed":0"#));
    }
    std::fs::rename(&first, dir.join("retained")).unwrap();
    dir.file("first", "replacement");
    let reply = state.handle(r#"{"op":"validate","id":2}"#, &cancel).unwrap();
    assert!(reply.contains(r#""removed":1"#));
    assert_eq!(state.marks.len(), 1);
    assert_eq!(state.marks[0].path, second);
    std::fs::rename(&second, dir.join("second-retained")).unwrap();
    assert!(state.handle(r#"{"op":"validate","id":3}"#, &cancel).unwrap().contains(r#""marks":[]"#));
}

#[test]
fn save_review_detects_arrivals_and_replacements_without_writing() {
    let dir = TestDir::new("picker-save");
    let mut state = State::default();
    let cancel = Cancellation::default();
    let probe = format!(r#"{{"op":"save","id":4,"folder":"{}","name":"result.txt"}}"#, escape(&dir.path().to_string_lossy()));
    assert!(state.handle(&probe, &cancel).unwrap().contains(r#""collision":false"#));
    assert!(!dir.join("result.txt").exists());
    let path = dir.file("result.txt", "caller data");
    assert!(state.handle(r#"{"op":"review","id":5,"review":4}"#, &cancel).is_err());
    assert!(state.handle(&probe, &cancel).unwrap().contains(r#""collision":true"#));
    assert!(state.handle(r#"{"op":"review","id":6,"review":4}"#, &cancel).is_ok());
    std::fs::rename(&path, dir.join("retained")).unwrap();
    dir.file("result.txt", "replacement");
    assert!(state.handle(r#"{"op":"review","id":7,"review":4}"#, &cancel).is_err());
    assert_eq!(std::fs::read_to_string(&path).unwrap(), "replacement");
}

#[test]
fn filters_keep_directories_and_matches_beyond_the_first_window() {
    let mut listing = Listing::new();
    listing.push("folder", true);
    for index in 0..150 { listing.push(&format!("file-{}.txt", index), false); }
    listing.push("last.PNG", false);
    filter_listing(&mut listing, &Db::from_str(""), r#"{"pickerGlobs":["*.png"]}"#);
    assert_eq!(listing.len(), 2);
    assert_eq!(listing.name(1), "last.PNG");
}

#[test]
fn filters_keep_symlink_navigation_without_inspecting_targets() {
    let dir = TestDir::new("picker-filter-links");
    let folder = dir.dir("folder");
    let link = dir.join("linked-folder");
    let broken = dir.join("broken-link");
    std::os::unix::fs::symlink(&folder, &link).unwrap();
    std::os::unix::fs::symlink(dir.join("missing-target"), &broken).unwrap();
    dir.file("hidden-by-filter.txt", "text");
    let (mut listing, _) = super::super::scan::scan(&dir.path().to_string_lossy(), false).unwrap();
    filter_listing(&mut listing, &Db::from_str(""), r#"{"pickerGlobs":["*.png"]}"#);
    let names: Vec<_> = (0..listing.len()).map(|index| listing.name(index)).collect();
    assert!(names.contains(&"folder"));
    assert!(names.contains(&"linked-folder"));
    assert!(names.contains(&"broken-link"));
    assert!(!names.contains(&"hidden-by-filter.txt"));
    let (mut recent, _) = super::super::listpaths::listing_of(&[link.to_string_lossy().into(), broken.to_string_lossy().into()]);
    filter_listing(&mut recent, &Db::from_str(""), r#"{"pickerMimes":["image/png"]}"#);
    assert_eq!(recent.len(), 2);
}

#[test]
fn save_refuses_directories_and_links_to_directories() {
    let dir = TestDir::new("picker-save-directory");
    let folder = dir.dir("folder");
    std::os::unix::fs::symlink(folder, dir.join("linked-folder")).unwrap();
    let mut state = State::default();
    for name in ["folder", "linked-folder"] {
        let line = format!(r#"{{"op":"save","id":1,"folder":"{}","name":"{}"}}"#, escape(&dir.path().to_string_lossy()), name);
        let error = state.handle(&line, &Cancellation::default()).unwrap_err();
        assert!(error.contains("is a directory"));
        assert!(state.save.is_none());
    }
}

#[test]
fn directory_symlink_keeps_its_uri_and_rejects_a_replaced_target() {
    let dir = TestDir::new("picker-link");
    let target = dir.dir("target");
    let link = dir.join("link");
    std::os::unix::fs::symlink(&target, &link).unwrap();
    let mut state = State::default();
    let cancel = Cancellation::default();
    let line = format!(r#"{{"op":"mark","id":1,"path":"{}","directory":true}}"#, escape(&link.to_string_lossy()));
    assert!(state.handle(&line, &cancel).is_ok());
    assert_eq!(state.marks[0].path, link);
    assert_eq!(state.marks[0].current().unwrap().len(), link.symlink_metadata().unwrap().len());
    std::fs::rename(&target, dir.join("retained-target")).unwrap();
    dir.dir("target");
    assert!(state.handle(r#"{"op":"validate","id":2}"#, &cancel).unwrap().contains(r#""removed":1"#));
}

#[test]
fn single_selection_replaces_toggles_and_refuses_wrong_types() {
    let dir = TestDir::new("picker-single");
    let first = dir.file("first", "one");
    let second = dir.file("second", "two");
    let mut state = State::default();
    let cancel = Cancellation::default();
    let mark = |path: &Path| format!(r#"{{"op":"mark","id":1,"path":"{}"}}"#, escape(&path.to_string_lossy()));
    state.handle(&mark(&first), &cancel).unwrap();
    state.handle(&mark(&second), &cancel).unwrap();
    assert_eq!(state.marks.len(), 1);
    assert_eq!(state.marks[0].path, second);
    assert!(state.handle(&mark(dir.path()), &cancel).is_err());
    assert_eq!(state.marks[0].path, second);
    state.handle(&mark(&second), &cancel).unwrap();
    assert!(state.marks.is_empty());
    assert!(state.handle(&mark(Path::new("relative")), &cancel).is_err());
}

#[test]
fn save_review_rejects_parent_replacement_bad_names_and_cancellation() {
    let dir = TestDir::new("picker-parent");
    let folder = dir.dir("folder");
    let mut state = State::default();
    let cancel = Cancellation::default();
    let probe = |name: &str| format!(r#"{{"op":"save","id":1,"folder":"{}","name":"{}"}}"#, escape(&folder.to_string_lossy()), escape(name));
    for name in ["", ".", "..", "../outside", "nul\0name"] {
        assert!(state.handle(&probe(name), &cancel).is_err());
    }
    state.handle(&probe("output"), &cancel).unwrap();
    std::fs::rename(&folder, dir.join("retained-folder")).unwrap();
    dir.dir("folder");
    assert!(state.handle(r#"{"op":"review","id":2,"review":1}"#, &cancel).is_err());
    cancel.next();
    assert!(state.handle(&probe("output"), &cancel).is_err());
    assert!(!folder.join("output").exists());
}

#[test]
fn mime_and_glob_rules_are_alternatives_and_all_files_restores_rows() {
    let db = Db::from_str("50:text/plain:*.txt\n50:image/png:*.png\n");
    let mut listing = Listing::new();
    for name in ["notes.txt", "photo.png", "archive.zip"] { listing.push(name, false); }
    filter_listing(&mut listing, &db, r#"{"pickerGlobs":["*.zip"],"pickerMimes":["image/*"]}"#);
    assert_eq!(listing.len(), 2);
    assert_eq!(listing.name(0), "photo.png");
    let mut all = Listing::new();
    all.push("notes.txt", false);
    filter_listing(&mut all, &db, r#"{"pickerGlobs":[],"pickerMimes":[]}"#);
    assert_eq!(all.len(), 1);
}

#[test]
fn batch_selection_filters_kinds_and_shrinks_without_rebinding_identities() {
    let dir = TestDir::new("picker-batch");
    let first = dir.file("first", "one");
    let second = dir.file("second", "two");
    let folder = dir.dir("folder");
    let mut state = State::default();
    let cancel = Cancellation::default();
    let select = |paths: &[&Path]| format!(r#"{{"op":"select","id":1,"paths":[{}]}}"#,
        paths.iter().map(|path| format!(r#""{}""#, escape(&path.to_string_lossy()))).collect::<Vec<_>>().join(","));
    state.handle(&select(&[&first, &folder, &second, &first]), &cancel).unwrap();
    assert_eq!(state.marks.iter().map(|held| &held.path).collect::<Vec<_>>(), vec![&first, &second]);
    state.handle(&select(&[&first]), &cancel).unwrap();
    assert_eq!(state.marks.len(), 1);
    std::fs::rename(&first, dir.join("retained")).unwrap();
    dir.file("first", "replacement");
    assert!(state.handle(&select(&[&first, &second]), &cancel).unwrap_err().contains("changed"));
    assert_eq!(state.marks.len(), 1);
    assert_eq!(state.marks[0].path, first);
    assert_eq!(std::fs::read_to_string(second).unwrap(), "two");
}

#[test]
fn batch_selection_follows_folder_links_and_preserves_marks_on_failure() {
    let dir = TestDir::new("picker-batch-link");
    let file = dir.file("file", "one");
    let folder = dir.dir("folder");
    let link = dir.join("folder-link");
    std::os::unix::fs::symlink(&folder, &link).unwrap();
    let mut state = State::default();
    let cancel = Cancellation::default();
    let select = format!(r#"{{"op":"select","id":1,"directory":true,"paths":["{}","{}"]}}"#,
        escape(&file.to_string_lossy()), escape(&link.to_string_lossy()));
    state.handle(&select, &cancel).unwrap();
    assert_eq!(state.marks.len(), 1);
    assert_eq!(state.marks[0].path, link);
    assert!(state.handle(r#"{"op":"select","id":2,"paths":["relative"]}"#, &cancel).is_err());
    assert_eq!(state.marks.len(), 1);
    assert_eq!(state.marks[0].path, link);
}
