// Names a paste or a drop would land on: the question asked first, and the one choice the transfer carries.
use crate::backend::icons::Names;
use crate::backend::menu_actions::Selected;
use crate::backend::mime::Db;
use crate::backend::ops::free_copy_path;
use crate::backend::opsdispatch::Ops;
use crate::backend::opsreq::{usable_dest, OpMsg, ALREADY_THERE};
use crate::backend::trash;
use crate::backend::undo::{ItemIdentity, Step};
use crate::error::FleaError;
use crate::json::{escape, field_str, field_usize};
use std::cell::OnceCell;
use std::collections::{HashMap, HashSet};
use std::os::unix::fs::MetadataExt;
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;

// The card lists this many names and says how many more there are, so the answer never carries more.
pub const SHOWN: usize = 3;
// The word Duplicate already uses, so a kept copy and a duplicate are named by one rule.
const KEEP_WORD: &str = "copy";
pub const TRASH_REFUSED: &str = "the item already there could not be moved to Trash, so nothing was replaced";
pub const HOLDS_SOURCE: &str = "the item already there holds the one being moved in, so it was not replaced";
pub const LINKS_HERE: &str = "the incoming link points at the item already there, so it was not replaced";
pub const NO_FREE_NAME: &str = "every copy name for this item is already taken";
// copyfile's own word for a cancelled item, which is what the transfer counts a cancel by.
pub(crate) const CANCELLED: &str = "cancelled";
// What a failed put-back adds to the item's error, a cancel's included, so the old item is never reported as untouched.
const STILL_IN_TRASH: &str = "; the item it replaced is still in Trash";
// Symlinks Linux follows in one lookup before it answers ELOOP, so a walk that follows more is broken wherever it was heading.
const MAX_HOPS: usize = 40;

// The operator's one answer, for every name the question listed.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Collide {
    Refuse,
    Keep,
    Replace,
    Skip,
}

impl Collide {
    // Anything that is not one of the three choices refuses, so a malformed word can never replace.
    fn from_word(word: &str) -> Collide {
        match word {
            "keep" => Collide::Keep,
            "replace" => Collide::Replace,
            "skip" => Collide::Skip,
            _ => Collide::Refuse,
        }
    }
}

// What the question saw: each colliding source, and the item that held its name in dest at that moment.
pub struct Question {
    id: usize,
    dest: PathBuf,
    seen: HashMap<PathBuf, ItemIdentity>,
    menu: Option<MenuCapture>,
}

// A menu's selection as its question saw it: Copy to closes its dialog, which expires the live one, before the answer lands.
struct MenuCapture {
    id: usize,
    items: Vec<Selected>,
    destination: Option<Selected>,
}

// The transfer request's two fields, before the question they name has been looked up.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Ask {
    word: Option<String>,
    id: usize,
}

impl Ask {
    // Sample input: {"c":"transfer","op":"copy","paths":["/home/gm/a.png"],"dest":"/home/gm/Pictures","collide":"replace","collideId":7}
    pub fn parse(line: &str) -> Ask {
        Ask { word: field_str(line, "collide"), id: field_usize(line, "collideId").unwrap_or(0) }
    }

    // The choice covers only the question this request names, asked about this same destination.
    pub fn policy(self, question: Option<Question>, dest: &Path) -> Policy {
        let seen = match question {
            Some(q) if self.answers(&q, dest) => q.seen,
            _ => HashMap::new(),
        };
        Policy { choice: self.word.as_deref().map(Collide::from_word), seen: Arc::new(seen), ..Policy::default() }
    }

    fn answers(&self, question: &Question, dest: &Path) -> bool {
        self.id != 0 && question.id == self.id && question.dest == dest
    }
}

// The selection a menu transfer runs on: the one its question captured, else the menu's live one.
pub(crate) fn menu_sources(ops: &Ops, id: usize, dest: &str, collide: &Ask) -> Result<(Vec<Selected>, Option<Selected>), String> {
    let captured = ops.question.as_ref().filter(|q| collide.answers(q, Path::new(dest))).and_then(|q| q.menu.as_ref());
    if let Some(menu) = captured.filter(|menu| menu.id == id) {
        return Ok((menu.items.clone(), menu.destination.clone()));
    }
    ops.menuactions.as_ref().ok_or_else(|| "Menu selection expired; reopen the menu.".to_string())
        .and_then(|menu| Ok((menu.selection(id)?, menu.provider_destination(id, Path::new(dest))?)))
}

// An expired selection captures nothing, so the question answers no collision and the transfer its own error.
fn capture(ops: &Ops, id: usize, dest: &str) -> Option<MenuCapture> {
    let menu = ops.menuactions.as_ref()?;
    Some(MenuCapture { id, items: menu.selection(id).ok()?, destination: menu.provider_destination(id, Path::new(dest)).ok()? })
}

// No choice at all is today's transfer exactly; any choice also turns on the same-folder rule.
#[derive(Default)]
pub struct Policy {
    choice: Option<Collide>,
    seen: Arc<HashMap<PathBuf, ItemIdentity>>,
    batch: Vec<PathBuf>,
    // Every source of the batch and every folder above it, resolved on the first Replace, so one lookup says whether a trash would take a source.
    held: OnceCell<HashSet<PathBuf>>,
}

// Where one item goes; replace says what holds that path now goes to Trash first.
#[derive(Debug, PartialEq)]
pub enum Place {
    Land { to: PathBuf, replace: bool },
    Skip,
    Refuse(String),
}

impl Policy {
    // Replace checks each item against the whole batch, so the batch is kept only when there is a Replace to check.
    pub fn for_batch(mut self, paths: &[String]) -> Policy {
        if self.choice == Some(Collide::Replace) {
            self.batch = paths.iter().map(PathBuf::from).collect();
        }
        self
    }

    // Skip's test for the sweep beside the copy, which leaves out of the batch's total what place will leave in place.
    pub fn skipping(&self) -> Option<Skipping> {
        (self.choice == Some(Collide::Skip)).then(|| Skipping { seen: Arc::clone(&self.seen) })
    }

    // here says the item already lives in dest; a name the question did not see is left to the exclusive create, which refuses it.
    pub fn place(&self, src: &Path, dst: PathBuf, here: bool, moving: bool) -> Place {
        let Some(choice) = self.choice else {
            return if here { Place::Refuse(ALREADY_THERE.to_string()) } else { Place::Land { to: dst, replace: false } };
        };
        if here {
            // A move onto itself changes nothing, and a copy into its own folder is a Duplicate.
            return if moving { Place::Skip } else { keep_both(dst) };
        }
        if !covers(&self.seen, src, &dst) {
            return Place::Land { to: dst, replace: false };
        }
        match choice {
            Collide::Refuse => Place::Land { to: dst, replace: false },
            Collide::Keep => keep_both(dst),
            Collide::Skip => Place::Skip,
            Collide::Replace => match self.guard(&dst, src) {
                Some(reason) => Place::Refuse(reason.to_string()),
                None => Place::Land { to: dst, replace: true },
            },
        }
    }

    // What a trash of dst would take with it: any source this batch names, or the item an incoming link resolves to.
    fn guard(&self, dst: &Path, src: &Path) -> Option<&'static str> {
        let there = resolved_parent(dst)?;
        if self.held.get_or_init(|| held_sources(&self.batch)).contains(&there) {
            return Some(HOLDS_SOURCE);
        }
        links_into(src, &there).then_some(LINKS_HERE)
    }
}

// The question listed this source and its name still holds the item the question saw there: the one test every choice waits on.
fn covers(seen: &HashMap<PathBuf, ItemIdentity>, src: &Path, dst: &Path) -> bool {
    seen.get(src).is_some_and(|seen| ItemIdentity::inspect(dst).is_ok_and(|current| seen.same_item(&current)))
}

// What a Skip leaves in place, shared with the sweep's own thread so the first byte never waits on its lstat per name.
pub struct Skipping {
    seen: Arc<HashMap<PathBuf, ItemIdentity>>,
}

impl Skipping {
    pub fn leaves(&self, src: &Path, dst: &Path) -> bool {
        covers(&self.seen, src, dst)
    }
}

// Each source and its ancestors; an ancestor already in the set had its own ancestors added with it.
fn held_sources(batch: &[PathBuf]) -> HashSet<PathBuf> {
    let mut held = HashSet::new();
    // A selection shares a folder or a few, so each folder is resolved once rather than once per item.
    let mut folders: HashMap<&Path, Option<PathBuf>> = HashMap::new();
    for src in batch {
        let (Some(parent), Some(name)) = (src.parent(), src.file_name()) else { continue };
        let folder = folders.entry(parent).or_insert_with(|| parent.canonicalize().ok());
        let Some(resolved) = folder.as_ref().map(|folder| folder.join(name)) else { continue };
        for ancestor in resolved.ancestors() {
            if !held.insert(ancestor.to_path_buf()) {
                break;
            }
        }
    }
    held
}

// A link lands under its own text in dest, so it resolves into there either now or once it sits there itself.
fn links_into(src: &Path, there: &Path) -> bool {
    let Ok(text) = std::fs::read_link(src) else { return false };
    let now = src.canonicalize().is_ok_and(|target| target.starts_with(there));
    now || there.parent().is_some_and(|dest| matches!(walk(dest.to_path_buf(), &text, there, &mut 0), Walk::Loops))
}

// Where a lookup ends: a folder or file it reached, a name that is not there, back at there, which holds the link itself, or past MAX_HOPS short of there.
enum Walk {
    Ends(PathBuf),
    Dangles,
    Loops,
    // The kernel answers ELOOP before the lookup reaches there, so the link is broken like a dangling one and not a link to itself.
    Overflows,
}

// Resolves text from at as the kernel would once there holds a link with this same text, so reaching there starts the lookup over.
fn walk(mut at: PathBuf, text: &Path, there: &Path, hops: &mut usize) -> Walk {
    for part in text.components() {
        match part {
            Component::RootDir => at = PathBuf::from(Component::RootDir.as_os_str()),
            Component::Prefix(_) | Component::CurDir => {}
            Component::ParentDir => { at.pop(); }
            Component::Normal(name) => {
                let next = at.join(name);
                if next == there {
                    return Walk::Loops;
                }
                let Ok(meta) = next.symlink_metadata() else { return Walk::Dangles };
                if !meta.file_type().is_symlink() {
                    at = next;
                    continue;
                }
                *hops += 1;
                let Ok(target) = std::fs::read_link(&next) else { return Walk::Dangles };
                if *hops > MAX_HOPS {
                    return Walk::Overflows;
                }
                at = match walk(at, &target, there, hops) {
                    Walk::Ends(end) => end,
                    stopped => return stopped,
                };
            }
        }
    }
    Walk::Ends(at)
}

fn keep_both(dst: PathBuf) -> Place {
    match free_copy_path(&dst, KEEP_WORD) {
        Some(free) => Place::Land { to: free, replace: false },
        None => Place::Refuse(NO_FREE_NAME.to_string()),
    }
}

// The parent resolved and the last component left as it is, so a symlink names itself and not its target.
fn resolved_parent(path: &Path) -> Option<PathBuf> {
    Some(path.parent()?.canonicalize().ok()?.join(path.file_name()?))
}

// The item already lives in dest: its name there is the item itself, through a symlinked folder too.
pub fn already_there(src: &Path, name: &str, dst: &Path, dest_real: &Path) -> bool {
    let src_here = match src.parent() {
        Some(parent) => parent.canonicalize().unwrap_or_else(|_| parent.to_path_buf()).join(name),
        None => src.to_path_buf(),
    };
    dst == src || dest_real.join(name) == src_here
}

// Replace is Trash and then the transfer, journaled as one entry: undo removes the new item, then restores the old.
pub fn replacing(dst: &Path, steps: &mut Vec<Step>, land: impl FnOnce(&mut Vec<Step>) -> Result<(), FleaError>) -> Result<(), FleaError> {
    let (mut entries, failed) = trash::trash(&[dst.to_path_buf()]);
    if failed != 0 || entries.len() != 1 {
        return Err(FleaError { where_: "transfer".into(), path: dst.to_string_lossy().into(), msg: TRASH_REFUSED.into() });
    }
    let entry = entries.remove(0);
    let at = steps.len();
    steps.push(Step::Trashed(entry.clone()));
    let mut outcome = land(steps);
    if let Err(error) = &mut outcome {
        put_back(&entry, dst, steps, at, error);
    }
    outcome
}

// Nothing took the name, a cancel included, so the old item goes straight back instead of waiting on an undo.
fn put_back(entry: &trash::Entry, dst: &Path, steps: &mut Vec<Step>, at: usize, error: &mut FleaError) {
    let vacant = matches!(dst.symlink_metadata(), Err(e) if e.kind() == std::io::ErrorKind::NotFound);
    if !vacant || steps.len() != at + 1 {
        return;
    }
    match trash::restore(entry) {
        Ok(()) => steps.truncate(at),
        // The step stays, so undo can still restore it.
        Err(restore) => error.msg.push_str(&format!("{} ({})", STILL_IN_TRASH, restore.msg)),
    }
}

// A cancel, bare or with the put-back that failed after it: either way the batch stops, and only the bare one is a skip.
pub(crate) fn cancelled(msg: &str) -> bool {
    msg.strip_prefix(CANCELLED).is_some_and(|rest| rest.is_empty() || rest.starts_with(STILL_IN_TRASH))
}

// One colliding source as the card draws it: its name, and the kind its mark is chosen from.
struct Shown {
    name: String,
    dir: bool,
    mode: u32,
}

// The question itself, read-only: which sources would land on a name dest already holds.
fn ask(id: usize, paths: &[String], dest: &str) -> (Question, Vec<Shown>) {
    let mut question = Question { id, dest: PathBuf::from(dest), seen: HashMap::new(), menu: None };
    let mut shown = Vec::new();
    // An unusable destination asks nothing: the transfer that follows answers its own error.
    let Ok(dest_path) = usable_dest(dest) else { return (question, shown) };
    let dest_real = dest_path.canonicalize().unwrap_or_else(|_| dest_path.clone());
    for raw in paths {
        let src = Path::new(raw);
        if !src.is_absolute() {
            continue;
        }
        let Some(name) = src.file_name().and_then(|n| n.to_str()) else { continue };
        let Ok(meta) = src.symlink_metadata() else { continue };
        let dst = dest_path.join(name);
        // Same-folder items never ask: a copy keeps both and a move stays put, see Policy::place.
        if already_there(src, name, &dst, &dest_real) {
            continue;
        }
        let Ok(there) = ItemIdentity::inspect(&dst) else { continue };
        if question.seen.insert(src.to_path_buf(), there).is_none() && shown.len() < SHOWN {
            shown.push(Shown { name: name.to_string(), dir: meta.is_dir(), mode: meta.mode() });
        }
    }
    (question, shown)
}

// Sample output: {"t":"collisions","id":7,"total":1,"names":[{"n":"a.png","d":false,"i":"image-x-generic"}]}
fn collisions_line(id: usize, total: usize, shown: &[Shown], mime: &Db, icons: &Names) -> String {
    let names: Vec<String> = shown.iter().map(|s| format!(r#"{{"n":"{}","d":{},"i":"{}"}}"#,
        escape(&s.name), s.dir, escape(icons.icon_for(mime.lookup(&s.name), s.dir, s.mode)))).collect();
    format!(r#"{{"t":"collisions","id":{},"total":{},"names":[{}]}}"#, id, total, names.join(","))
}

// A test's hold on the next question's thread, released once the requests that must come first are sent.
#[cfg(test)]
thread_local! {
    pub(crate) static HOLD: std::cell::RefCell<Option<std::sync::mpsc::Receiver<()>>> = const { std::cell::RefCell::new(None) };
}

// Measured 0.9 s for 100,000 local sources, a stall per network round trip on a mount, so the question runs beside the loop.
pub(crate) fn ask_beside(ops: &mut Ops, id: usize, menu_id: usize, named: Vec<String>, dest: &str, mime: &Arc<Db>, icons: &Arc<Names>) {
    // Captured here and not on the thread, because the close that expires the live selection may be the very next request.
    let menu = if menu_id == 0 { None } else { capture(ops, menu_id, dest) };
    let paths = match (&menu, menu_id) {
        (Some(menu), _) => menu.items.iter().map(|item| item.path.to_string_lossy().to_string()).collect(),
        (None, 0) => named,
        (None, _) => Vec::new(),
    };
    ops.asked += 1;
    let (turn, tx, dest, mime, icons) = (ops.asked, ops.tx.clone(), dest.to_string(), Arc::clone(mime), Arc::clone(icons));
    #[cfg(test)]
    let hold = HOLD.with(|slot| slot.borrow_mut().take());
    std::thread::spawn(move || {
        #[cfg(test)]
        if let Some(hold) = hold { let _ = hold.recv(); }
        let (mut question, shown) = ask(id, &paths, &dest);
        question.menu = menu;
        let line = collisions_line(id, question.seen.len(), &shown, &mime, &icons);
        let _ = tx.send(OpMsg::Asked { turn, question, line });
    });
}

// The latest question asked is the one kept and answered, so an earlier one that finishes later cannot stand in for it; the one transfer that names it spends it.
pub(crate) fn landed(ops: &mut Ops, turn: usize, question: Question) -> bool {
    let latest = turn == ops.asked;
    if latest {
        ops.question = Some(question);
    }
    latest
}

#[cfg(test)]
#[path = "collide_tests.rs"]
pub(crate) mod tests;
#[cfg(test)]
#[path = "collide_replace_tests.rs"]
mod replace_tests;
