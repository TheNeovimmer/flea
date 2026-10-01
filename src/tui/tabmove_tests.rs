// Tabs040 callout 1 through the real key path: { and } move the current tab
// one place, clamped at either end, and a move sends nothing because the pane
// stays on its path.
use super::sort_tests::{drain, press};
use super::*;
use crate::tui::input::Key;
use crate::tui::keymap::Map;
use crate::tui::model::Model;
use std::path::PathBuf;

fn move_key(text: &str) -> Key {
    let key = Key::character(text.chars().next().unwrap(), "");
    let action = Map::load().action(&key, "default");
    assert_eq!(action, if text == "}" { "tabMoveRight" } else { "tabMoveLeft" },
        "the test presses the shipped reorder key");
    key
}

fn shift_page(up: bool) -> Key {
    let key = Key::named(if up { "PageUp" } else { "PageDown" }, "ctrlshift");
    let action = Map::load().action(&key, "default");
    assert_eq!(action, if up { "tabMoveLeft" } else { "tabMoveRight" },
        "the test presses the shipped reorder chord");
    key
}

fn cursors(model: &Model) -> Vec<usize> {
    model.tabs.iter().map(|tab| tab.cursor).collect()
}

// A tab switch opens the tab's path, so each new tab settles its listing
// before the next opens, the way sort_tests' open_names settles its one.
fn settle_open(model: &mut Model, wire: &mut Wire) {
    drain(wire);
    model.receive(crate::jsondoc::parse(r#"{"t":"listed","n":1,"read":0.0,"sort":0.0,"v":1,"path":"/listing"}"#).unwrap(), wire).unwrap();
    drain(wire);
    model.receive(crate::jsondoc::parse(r#"{"t":"rows","start":0,"rows":[{"n":"photo.jpg"}]}"#).unwrap(), wire).unwrap();
    drain(wire);
}

#[test]
fn reorder_keys_move_the_current_tab_and_send_nothing() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/listing"), &Json::Null);
    for _ in 0..2 {
        press(&mut model, &mut wire, &Key::character('t', ""));
        settle_open(&mut model, &mut wire);
    }
    assert_eq!(model.tabs.len(), 3, "two new tabs stand beside the first");
    assert_eq!(model.tab, 2, "a new tab lands current");
    model.tabs[0].cursor = 10;
    model.tabs[1].cursor = 20;
    model.tabs[2].cursor = 30;
    press(&mut model, &mut wire, &move_key("{"));
    assert_eq!(cursors(&model), vec![10, 30, 20], "{{ swaps the current tab left");
    assert_eq!(model.tab, 1, "and the current tab stays current");
    assert!(drain(&mut wire).is_empty(), "and a move lists nothing");
    press(&mut model, &mut wire, &move_key("}"));
    assert_eq!(cursors(&model), vec![10, 20, 30], "}} moves it back");
    assert_eq!(model.tab, 2, "still current");
    press(&mut model, &mut wire, &shift_page(true));
    assert_eq!(cursors(&model), vec![10, 30, 20], "ctrl-shift-pageup moves left too");
    press(&mut model, &mut wire, &shift_page(false));
    assert_eq!(cursors(&model), vec![10, 20, 30], "ctrl-shift-pagedown moves right too");
    press(&mut model, &mut wire, &move_key("}"));
    assert_eq!(cursors(&model), vec![10, 20, 30], "}} on the last tab is a no-op");
    assert_eq!(model.tab, 2, "and stays current");
    finish(wire, reader);
}
