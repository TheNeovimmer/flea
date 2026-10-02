// The shared journal's wire form, both directions: every record is checked on read, never
// trusted. A Copied step's manifest never crosses a process, so decode always answers None for
// it and the undoing process takes today's whole-tree check instead.
use super::undoshare::{Doc, StoredRedo};
use crate::backend::redo::Replay;
use crate::backend::undo::{Entry, ItemIdentity, Step};
use crate::error::FleaError;
use crate::jsondoc::{parse, Json};
use std::path::PathBuf;

const VERSION: u32 = 1;
// A single record is checked, never trusted: absolute paths, closed kind sets, parsed numbers.
const MAX_OP: usize = 128;
const MAX_PATH: usize = 4096;
const MAX_TEXT: usize = 8192;
const MAX_STEPS: usize = 1_000_000;
const MAX_READ_ENTRIES: usize = 10_000;
// mode() & 0o170000 answers one of these for every file the kernel can stat.
const KNOWN_KINDS: [u32; 7] = [0o140000, 0o120000, 0o100000, 0o060000, 0o040000, 0o020000, 0o010000];

fn s(value: &str) -> Json {
    Json::Str(value.to_string())
}

fn n(value: impl ToString) -> Json {
    Json::Num(value.to_string())
}

fn obj(pairs: Vec<(&str, Json)>) -> Json {
    Json::Obj(pairs.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
}

fn arr(items: Vec<Json>) -> Json {
    Json::Arr(items)
}

fn identity(id: &ItemIdentity) -> Json {
    let (dev, ino, kind, len, mtime, changed) = id.to_parts();
    obj(vec![
        ("d", n(dev)),
        ("i", n(ino)),
        ("k", n(kind)),
        ("l", n(len)),
        ("m", arr(vec![n(mtime.0), n(mtime.1)])),
        ("c", arr(vec![n(changed.0), n(changed.1)])),
    ])
}

fn link_kind(kind: &super::link::LinkKind) -> &'static str {
    match kind {
        super::link::LinkKind::Relative => "relative",
        super::link::LinkKind::Absolute => "absolute",
        super::link::LinkKind::Hard => "hard",
    }
}

fn step(step: &Step) -> Json {
    match step {
        Step::Moved { from, to, before, after } => obj(vec![
            ("k", s("m")), ("from", s(&from.to_string_lossy())), ("to", s(&to.to_string_lossy())),
            ("before", identity(before)), ("after", identity(after)),
        ]),
        Step::Created { path } => obj(vec![("k", s("c")), ("path", s(&path.to_string_lossy()))]),
        Step::Linked { path, identity: id, source, kind } => obj(vec![
            ("k", s("l")), ("path", s(&path.to_string_lossy())), ("id", identity(id)),
            ("src", s(&source.to_string_lossy())), ("kind", s(link_kind(kind))),
        ]),
        // The manifest is the recording process's own anonymous file, so it never crosses one:
        // the undoing process takes today's whole-tree check instead.
        Step::Copied { from, to, source, created, .. } => obj(vec![
            ("k", s("cp")), ("from", s(&from.to_string_lossy())), ("to", s(&to.to_string_lossy())),
            ("src", identity(source)), ("made", identity(created)),
        ]),
        Step::MadeDir { path, identity: id } => obj(vec![
            ("k", s("md")), ("path", s(&path.to_string_lossy())), ("id", identity(id)),
        ]),
        Step::MadeFile { path, identity: id } => obj(vec![
            ("k", s("mf")), ("path", s(&path.to_string_lossy())), ("id", identity(id)),
        ]),
        Step::Trashed(entry) => obj(vec![
            ("k", s("t")), ("path", s(&entry.original.to_string_lossy())), ("uri", s(&entry.uri)),
        ]),
        Step::Mode { path, before, after } => obj(vec![
            ("k", s("pm")), ("path", s(&path.to_string_lossy())), ("before", n(before)), ("after", n(after)),
        ]),
    }
}

fn entry(entry: &Entry) -> Json {
    obj(vec![
        ("op", s(&entry.op)),
        ("steps", arr(entry.steps.iter().map(step).collect())),
    ])
}

fn replay_step(st: &Step, input: &Option<ItemIdentity>, parent: &Option<(PathBuf, ItemIdentity)>) -> Json {
    let mut pairs = vec![("s", step(st))];
    match input {
        Some(id) => pairs.push(("in", identity(id))),
        None => pairs.push(("in", Json::Null)),
    }
    match parent {
        Some((path, id)) => pairs.push(("parent", arr(vec![s(&path.to_string_lossy()), identity(id)]))),
        None => pairs.push(("parent", Json::Null)),
    }
    obj(pairs)
}

fn stored_redo(stored: &StoredRedo) -> Json {
    match stored {
        StoredRedo::Ok(replay) => {
            let (op, steps) = replay.steps_data();
            obj(vec![
                ("op", s(&op)),
                ("steps", arr(steps.iter().map(|(st, input, parent)| replay_step(st, input, parent)).collect())),
            ])
        }
        StoredRedo::Err(error) => obj(vec![
            ("err", obj(vec![("where", s(&error.where_)), ("path", s(&error.path)), ("msg", s(&error.msg))])),
        ]),
    }
}

pub(crate) fn encode(doc: &Doc) -> Json {
    obj(vec![
        ("v", n(VERSION)),
        ("undo", arr(doc.undo.iter().map(entry).collect())),
        ("redo", arr(doc.redo.iter().map(stored_redo).collect())),
    ])
}

fn get<'a>(pairs: &'a [(String, Json)], key: &str) -> Option<&'a Json> {
    pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v)
}

fn get_str<'a>(pairs: &'a [(String, Json)], key: &str) -> Option<&'a str> {
    match get(pairs, key) {
        Some(Json::Str(text)) => Some(text),
        _ => None,
    }
}

fn parse_u64(value: &Json) -> Option<u64> {
    match value {
        Json::Num(literal) => literal.parse().ok(),
        _ => None,
    }
}

fn parse_i64(value: &Json) -> Option<i64> {
    match value {
        Json::Num(literal) => literal.parse().ok(),
        _ => None,
    }
}

fn parse_u32(value: &Json) -> Option<u32> {
    match value {
        Json::Num(literal) => literal.parse().ok(),
        _ => None,
    }
}

// Absolute paths only: a relative one names whatever directory the reader happens to run in, so it
// is foreign rather than a record.
fn checked_path(value: &Json) -> Option<PathBuf> {
    match value {
        Json::Str(text) if !text.is_empty() && text.len() <= MAX_PATH
            && text.starts_with('/') && !text.contains('\0') => Some(PathBuf::from(text)),
        _ => None,
    }
}

fn checked_text(value: &Json) -> Option<String> {
    match value {
        Json::Str(text) if text.len() <= MAX_TEXT && !text.contains('\0') => Some(text.clone()),
        _ => None,
    }
}

// A trash entry journals an empty uri when gio listed nothing for the file it took, so the uri
// alone of every text field may be empty; bounded and NUL-free is the whole check either way.
fn checked_uri(value: &Json) -> Option<String> {
    checked_text(value)
}

fn checked_op(value: &Json) -> Option<String> {
    match value {
        Json::Str(text) if !text.is_empty() && text.len() <= MAX_OP && !text.contains('\0') => Some(text.clone()),
        _ => None,
    }
}

fn decode_identity(value: &Json) -> Option<ItemIdentity> {
    let pairs = value.as_object()?;
    let kind = get(pairs, "k").and_then(parse_u32)?;
    if !KNOWN_KINDS.contains(&kind) {
        return None;
    }
    let pair = |key: &str| -> Option<(i64, i64)> {
        let items = get(pairs, key)?.as_array()?;
        if items.len() != 2 {
            return None;
        }
        Some((parse_i64(&items[0])?, parse_i64(&items[1])?))
    };
    Some(ItemIdentity::from_parts(
        get(pairs, "d").and_then(parse_u64)?,
        get(pairs, "i").and_then(parse_u64)?,
        kind,
        get(pairs, "l").and_then(parse_u64)?,
        pair("m")?,
        pair("c")?,
    ))
}

fn decode_step(value: &Json) -> Option<Step> {
    let pairs = value.as_object()?;
    match get_str(pairs, "k")? {
        "m" => Some(Step::Moved {
            from: checked_path(get(pairs, "from")?)?,
            to: checked_path(get(pairs, "to")?)?,
            before: decode_identity(get(pairs, "before")?)?,
            after: decode_identity(get(pairs, "after")?)?,
        }),
        "c" => Some(Step::Created { path: checked_path(get(pairs, "path")?)? }),
        "l" => {
            let kind = match get_str(pairs, "kind")? {
                "relative" => super::link::LinkKind::Relative,
                "absolute" => super::link::LinkKind::Absolute,
                "hard" => super::link::LinkKind::Hard,
                _ => return None,
            };
            Some(Step::Linked {
                path: checked_path(get(pairs, "path")?)?,
                identity: decode_identity(get(pairs, "id")?)?,
                source: checked_path(get(pairs, "src")?)?,
                kind,
            })
        }
        "cp" => Some(Step::Copied {
            from: checked_path(get(pairs, "from")?)?,
            to: checked_path(get(pairs, "to")?)?,
            source: decode_identity(get(pairs, "src")?)?,
            created: decode_identity(get(pairs, "made")?)?,
            manifest: None,
        }),
        "md" => Some(Step::MadeDir {
            path: checked_path(get(pairs, "path")?)?,
            identity: decode_identity(get(pairs, "id")?)?,
        }),
        "mf" => Some(Step::MadeFile {
            path: checked_path(get(pairs, "path")?)?,
            identity: decode_identity(get(pairs, "id")?)?,
        }),
        "t" => Some(Step::Trashed(crate::backend::trash::Entry {
            original: checked_path(get(pairs, "path")?)?,
            uri: checked_uri(get(pairs, "uri")?)?,
        })),
        "pm" => Some(Step::Mode {
            path: checked_path(get(pairs, "path")?)?,
            before: get(pairs, "before").and_then(parse_u32)?,
            after: get(pairs, "after").and_then(parse_u32)?,
        }),
        _ => None,
    }
}

fn decode_entry(value: &Json) -> Option<Entry> {
    let pairs = value.as_object()?;
    let steps = get(pairs, "steps")?.as_array()?;
    if steps.len() > MAX_STEPS {
        return None;
    }
    let mut out = Vec::with_capacity(steps.len().min(1024));
    for step in steps {
        out.push(decode_step(step)?);
    }
    Some(Entry { op: checked_op(get(pairs, "op")?)?, steps: out })
}

fn decode_replay_step(value: &Json) -> Option<(Step, Option<ItemIdentity>, Option<(PathBuf, ItemIdentity)>)> {
    let pairs = value.as_object()?;
    let step = decode_step(get(pairs, "s")?)?;
    let input = match get(pairs, "in")? {
        Json::Null => None,
        id => Some(decode_identity(id)?),
    };
    let parent = match get(pairs, "parent")? {
        Json::Null => None,
        Json::Arr(items) if items.len() == 2 => Some((checked_path(&items[0])?, decode_identity(&items[1])?)),
        _ => return None,
    };
    Some((step, input, parent))
}

fn decode_redo(value: &Json) -> Option<StoredRedo> {
    let pairs = value.as_object()?;
    if let Some(err) = get(pairs, "err") {
        let fields = err.as_object()?;
        return Some(StoredRedo::Err(FleaError {
            where_: checked_text(get(fields, "where")?)?,
            path: get_str(fields, "path").unwrap_or("").to_string(),
            msg: checked_text(get(fields, "msg")?)?,
        }));
    }
    let steps = get(pairs, "steps")?.as_array()?;
    if steps.len() > MAX_STEPS {
        return None;
    }
    let mut out = Vec::with_capacity(steps.len().min(1024));
    for step in steps {
        out.push(decode_replay_step(step)?);
    }
    Some(StoredRedo::Ok(Replay::from_steps(checked_op(get(pairs, "op")?)?, out)))
}

pub(crate) fn decode(text: &str) -> Option<Doc> {
    let root = parse(text).ok()?;
    let pairs = root.as_object()?;
    match get(pairs, "v") {
        Some(Json::Num(literal)) if literal == &VERSION.to_string() => {}
        _ => return None,
    }
    let undo_items = get(pairs, "undo")?.as_array()?;
    let redo_items = get(pairs, "redo")?.as_array()?;
    if undo_items.len() > MAX_READ_ENTRIES || redo_items.len() > MAX_READ_ENTRIES {
        return None;
    }
    let mut undo = Vec::with_capacity(undo_items.len());
    for item in undo_items {
        undo.push(decode_entry(item)?);
    }
    let mut redo = Vec::with_capacity(redo_items.len());
    for item in redo_items {
        redo.push(decode_redo(item)?);
    }
    Some(Doc { undo, redo })
}
