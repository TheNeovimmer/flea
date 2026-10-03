use crate::backend::meta::stat_range;
use crate::backend::meta::Meta;
use crate::backend::archivereq::{formats_line, start_archive, start_convert};
use crate::backend::convert;
use crate::backend::peek::peek_line;
use crate::backend::metareq::spawn as spawn_meta;
use crate::backend::opsdispatch::{cancel_transfer, do_mkdir, do_newfile, do_permissions_batch, do_rename, do_undo, report_op, resolve_rows, start_duplicate, start_link, start_link_target, start_trash, start_transfer, start_menu_transfer, start_redo, Ops};
use crate::backend::opsreq::OpMsg;
use crate::backend::dirsizereq::{queue_dirsizes, seed_answered, start_next, report_done as report_dirsize};
use crate::backend::events::{spawn_forwarder, spawn_op_forwarder, spawn_reader, Event};
use crate::backend::fsinfo::fsinfo_line;
use crate::backend::fsinforeq::FsInfo;
use crate::backend::listpaths;
use crate::backend::proto::{error_line, error_line_with_mode, listed_line, parse_request, paths_line, thumbed_line, Request};
use crate::backend::proto::with_anchor;
use crate::backend::rows::rows_line;
use crate::backend::sandbox;
use crate::backend::listing::Listing;
use crate::backend::search::Search;
use crate::backend::state::{Held, State, Tables};
use crate::backend::searchreq::{finish_search, step_search};
use crate::backend::thumbcache::{default_root, Cache};
use crate::backend::thumbreq::{cancel_row, forget_one, report_done, thumb_rows};
use crate::backend::thumbs::{Done, Pool};
use crate::backend::thumbwrite::sweep_own_temps;
use crate::backend::watch::{changed_line, Watch};
use crate::error::FleaError;
use crate::heap;
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{channel, Receiver, Sender, TryRecvError};
use std::sync::Arc;
use std::time::{Duration, Instant};

// Wider pools settle sooner and answer input later: 6 settles the media fixture ahead of strata for 5.5 ms of input under a full pool; see AGENTS.md "Thumbnail requests".
const THUMB_WORKERS: usize = 6;
// The whole shutdown budget: a running job is killed at the pool's own 20 s deadline, so waiting longer than that can never cut one short.
pub(crate) const DRAIN_LIMIT: Duration = Duration::from_secs(25);
// The UI gives up on a silent child after this; the budget above stays under it (ui/Backend.qml quitDeadline).
pub(crate) const UI_QUIT_DEADLINE_SECS: u64 = 30;
const _: () = assert!(DRAIN_LIMIT.as_secs() < UI_QUIT_DEADLINE_SECS);
const _: () = assert!(crate::backend::archivework::CANCEL_DRAIN_SECS < DRAIN_LIMIT.as_secs());

// The loop stops on Quit; every other request continues it, because errors are responses.
#[derive(PartialEq)]
enum Control {
    Continue,
    Quit,
}

// Errors are responses, so the loop never exits on a bad request.
pub fn run() -> i32 {
    super::picker::raise_file_limit();
    // Before the first listing, because a threshold glibc has already ratcheted strands the next arena on the heap.
    heap::pin_mmap_threshold();
    // Recorded when the first rows go out, the next launch's prefetch list; see src/prefetch.rs.
    crate::prefetch::record_after_first_rows();
    let mut out = BufWriter::new(io::stdout());
    let tb = Tables::load();
    let (tx, rx) = channel::<Event>();
    let mut st = State::new(super::dirsizeworker::Worker::new(tx.clone()));
    let (results, done) = channel::<Done>();
    let (op_tx, op_rx) = channel::<OpMsg>();
    let mut ops = Ops::new_shared(op_tx);
    let pool = Pool::new(THUMB_WORKERS, results, default_root(), Arc::clone(&tb.aliases), Arc::clone(&tb.thumbs));
    let cache = Cache::new();
    // Every thumbnail job fails closed without these two, so the reason is said once here rather than never; see AGENTS.md "Thumbnail sandbox".
    if !sandbox::available() {
        eprintln!("flea: thumbnails are disabled, bwrap or prlimit is not on PATH");
    }
    // The workers hold senders too, so no exit can come from a disconnect and every exit is an explicit event; see AGENTS.md "Thumbnail requests".
    spawn_forwarder(done, tx.clone());
    spawn_op_forwarder(op_rx, tx.clone());
    spawn_reader(tx.clone(), Arc::clone(&ops.live));
    let mut fsinfo = FsInfo::new(tx.clone());
    let loop_tx = tx.clone();
    // Armed before the first request, so no listing is ever answered with nothing watching it.
    let mut watch = Watch::start(tx.clone());
    let poller = super::watchpoll::Poller::new(tx.clone());
    loop {
        start_next(&mut st);
        // Size results wake this receiver; only search still needs idle ticks.
        let event = if st.search.is_none() {
            match rx.recv() {
                Ok(e) => e,
                Err(_) => break,
            }
        } else {
            match rx.try_recv() {
                Ok(e) => e,
                // Search takes one bounded step before checking requests again.
                Err(TryRecvError::Empty) => {
                    tick_walkers(&mut out, &mut st, &pool);
                    continue;
                }
                Err(TryRecvError::Disconnected) => break,
            }
        };
        match event {
            Event::Request(line) => {
                if handle_line(&line, &mut out, &mut st, &tb, &pool, &cache, &mut ops, &mut watch, &mut fsinfo, &poller, &loop_tx) == Control::Quit {
                    break;
                }
            }
            Event::Thumb(d) => report_done(&mut out, &mut st, d),
            Event::DirSize(d) => report_dirsize(&mut out, &mut st, d),
            // A slow mount's figures, printed only for the directory on screen now.
            Event::FsInfo(d) => {
                if let Some(info) = fsinfo.finish(d, &st.base) {
                    say(&mut out, &fsinfo_line(&info, &st.base.to_string_lossy(), crate::backend::fsinforeq::slow_class(&st.base)));
                }
            }
            // The one line no client asked for, and only ever for the directory being listed now.
            Event::Changed(wd) => {
                if watch.is_current(wd) {
                    say(&mut out, &changed_line(&st.base));
                }
            }
            // The open mount went away, so the pane leaves the volume for its nearest parent.
            Event::Unmounted(wd) => {
                if watch.is_current(wd) {
                    let start = watch.unmount_start(&st.base);
                    let parent = super::watch::nearest_parent(&start, |p| p.symlink_metadata().is_ok());
                    say(&mut out, &super::watch::unmounted_line(&st.base, &parent));
                    poller.clear();
                }
            }
            // A network folder's mtime moved, which inotify never delivers; only the open path counts.
            Event::PollChanged(path) => {
                if path == st.base {
                    say(&mut out, &changed_line(&st.base));
                }
            }
            // A late list worker's descriptor goes unless a re-list aliased it onto the live watch.
            Event::AbandonWatch(wd) => watch.abandon_wd(wd),
            Event::Op(m) => report_op(&mut out, &mut ops, m),
            Event::ReadError(e) => {
                // The framing cannot be trusted past a decode failure, so this reports and stops, as before.
                writeln!(out, "{}", error_line(&e)).ok();
                out.flush().ok();
                break;
            }
            Event::Closed => break,
        }
    }
    st.dirsize_worker.cancel();
    drain(&mut out, &mut st, &mut ops, &rx, &pool, &cache);
    0
}

// One answer, written and flushed: the four read-only requests below differ only in what they say.
fn say(out: &mut impl Write, line: &str) {
    writeln!(out, "{}", line).ok();
    out.flush().ok();
}

fn handle_line(
    line: &str,
    out: &mut impl Write,
    st: &mut State,
    tb: &Tables,
    pool: &Pool,
    cache: &Cache,
    ops: &mut Ops,
    watch: &mut Watch,
    fsinfo: &mut FsInfo,
    poller: &super::watchpoll::Poller,
    loop_tx: &Sender<Event>,
) -> Control {
    // Rows read from a numbering this listing has already replaced name other files, so they are refused.
    if let Some(refused) = super::rowguard::refusal(line, st.generation) {
        say(out, &refused);
        return Control::Continue;
    }
    match parse_request(line) {
        Request::Permissions { line } => say(out, &ops.permissions.handle(&line)),
        Request::Picker { line } => {
            let replies = ops.tx.clone();
            ops.picker.get_or_insert_with(|| super::picker::Picker::new(replies)).request(line);
        }
        Request::MenuAction { line, rows } => {
            let paths = resolve_rows(Vec::new(), &rows, &st.base, &st.listing);
            let cursor = crate::json::field_usize(&line, "cursor").map(|index|
                resolve_rows(Vec::new(), &[index], &st.base, &st.listing).into_iter().next().unwrap_or_default());
            super::opsdispatch::request_menu_action(out, ops, line, paths, cursor);
        }
        // Directive 71: a CLI run of a second or more, so it answers on its own thread.
        Request::LocalSend { op, peer, paths, id } => super::localsend::request(op, peer, paths, id, ops.tx.clone()),
        Request::TrashBrowse { line } => {
            let replies = ops.tx.clone();
            // The browser resolves its originals inside, so the mounts held slow travel with the request.
            let pending = ops.pending.iter().map(|held| held.mount.clone()).collect();
            let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
            ops.trashbrowser.get_or_insert_with(|| super::trashbrowse::TrashBrowser::new(replies)).request(line, pending, body);
        }
        Request::List { path, first, hidden, want_changed } => {
            // A new listing replaces whatever the walk was filling, so the walk ends before the scan starts.
            if finish_search(out, st, true) {
                forget_rows(st, pool);
            }
            let fd = watch.raw_fd();
            let mime = std::sync::Arc::clone(&tb.mime);
            let line_owned = line.to_string();
            match super::iomount::list_dir(path.clone(), hidden, first, line_owned, mime, fd, loop_tx.clone()) {
                Ok(done) => {
                    watch.set_incoming(done.watch_wd);
                    watch.commit();
                    // Said once per listing, because a folder nobody can watch goes stale in silence.
                    if watch.refused() {
                        eprintln!("flea: {} will not follow outside changes, inotify refused a watch on it", path);
                    }
                    adopt_listed(out, st, pool, tb, &path, done, want_changed);
                    out.flush().ok();
                    // After the rows, because a statfs beside gio's own listing slows it on the share.
                    fsinfo.list_arrived(Path::new(&path));
                    // The open folder alone is polled, so a remote change arrives without inotify.
                    poller.set(PathBuf::from(&path));
                }
                Err(failed) => {
                    // The listing did not move, so the loop removes the watch the failed scan armed.
                    watch.abandon_wd(failed.watch_wd);
                    // A typed path reaches the denial with no parent row to remember the mode from,
                    // so the stat that survives the refused read is the pane's only source for it.
                    if failed.mode == 0 {
                        writeln!(out, "{}", error_line(&failed.error)).ok();
                    } else {
                        writeln!(out, "{}", error_line_with_mode(&failed.error, failed.mode)).ok();
                    }
                }
            }
            out.flush().ok();
            crate::prefetch::first_rows_sent();
        }
        // A set of named paths is not a directory, so the watch stops rather than following its base.
        Request::ListPaths { paths, first } => {
            watch.stop();
            poller.clear();
            listpaths::answer(out, st, pool, tb, &paths, first, line)
        }
        Request::Window { start, count } => {
            match window_metas(st, start, count) {
                Ok((metas, ms)) => {
                    let start_w = start.min(st.listing.len());
                    let mut kinds = tb.kinds.borrow_mut();
                    let line = super::rows::rows_line(&st.listing, &metas, start_w, ms, &tb.mime, &tb.icons, &tb.aliases, &tb.thumbs, &mut kinds);
                    writeln!(out, "{}", super::rowguard::stamped(line, st.generation)).ok();
                }
                Err(e) => {
                    writeln!(out, "{}", error_line(&e)).ok();
                }
            }
            out.flush().ok();
        }
        Request::Search { path, query, hidden } => {
            if finish_search(out, st, true) {
                forget_rows(st, pool);
            }
            st.base = PathBuf::from(&path);
            st.listing = Listing::new();
            // A walk holds no directory listing, so neither re-read counts over it.
            st.held = Held::Walk;
            // A walk's matches are not a directory either, so nothing is watched until list asks again.
            watch.stop();
            poller.clear();
            forget_rows(st, pool);
            // The client is told at once that its old rows are gone, then the count grows as matches arrive.
            match search_root_info(&st.base) {
                // A root that answers nothing starts no walk, so no terminal line can strand it.
                Err(e) => { writeln!(out, "{}", error_line(&e)).ok(); }
                Ok((dev, writable)) => {
                    writeln!(out, "{}", listed_line(0, 0.0, 0.0, dev, &st.base.to_string_lossy(), writable)).ok();
                    st.search = Some(Search::new(&path, &query, hidden));
                    st.search_reported = Instant::now();
                }
            }
            out.flush().ok();
        }
        Request::SearchCancel => {
            if finish_search(out, st, true) {
                forget_rows(st, pool);
            }
        }
        Request::Sort { by, desc: _, anchor } => {
            // The walk owns the listing sort would reorder, so it ends first rather than racing it.
            if finish_search(out, st, true) {
                forget_rows(st, pool);
            }
            let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
            let base = st.base.clone();
            let listing = st.listing.clone();
            let mime = std::sync::Arc::clone(&tb.mime);
            let line_owned = line.to_string();
            // A key that names no order is refused by name, so a client's sort mark can only describe the order it got.
            match super::iomount::call_bulk(&base.clone(), &body, "sort", move || {
                let mut l = listing;
                match super::ordering::request(&mut l, &base, &mime, &line_owned) {
                    Err(msg) => Err(msg.to_string()),
                    Ok((pass_ms, sort_ms, sized)) => {
                        let dev = super::fsinfo::dev_of(&base);
                        let writable = super::ops::dir_writable(&base);
                        Ok((l, pass_ms, sort_ms, sized, dev, writable))
                    }
                }
            }) {
                Err(e) => {
                    writeln!(out, "{}", error_line(&e)).ok();
                }
                Ok(Err(msg)) => {
                    let e = FleaError { where_: "sort".to_string(), path: by.clone(), msg };
                    writeln!(out, "{}", error_line(&e)).ok();
                }
                Ok(Ok((l, pass_ms, sort_ms, sized, dev, writable))) => {
                    st.listing = l;
                    forget_rows(st, pool);
                    // After forget_rows, which clears the very map this seeds.
                    seed_answered(st, &sized);
                    let line = match anchor.as_deref() {
                        // The listing is a snapshot, so only a path it never held answers -1.
                        Some(anchor) => {
                            let base = listed_line(st.listing.len(), pass_ms, sort_ms, dev,
                                &st.base.to_string_lossy(), writable);
                            with_anchor(&base, anchor,
                                st.listing.index_of(&st.base, Path::new(anchor)).map(|index| index as isize).unwrap_or(-1))
                        }
                        None => listed_line(st.listing.len(), pass_ms, sort_ms, dev, &st.base.to_string_lossy(), writable),
                    };
                    writeln!(out, "{}", line).ok();
                }
            }
            out.flush().ok();
        }
        Request::Thumb { rows, cache_only } => {
            thumb_rows(out, &rows, st, tb, pool, cache, cache_only);
            out.flush().ok();
        }
        Request::ThumbCancel { rows } => {
            if rows.is_empty() {
                // An empty rows cancels everything queued, and every job it drops has to leave the map with it; see AGENTS.md "Thumbnail requests".
                for job in pool.cancel_all() {
                    forget_one(st, &job.path);
                }
            } else {
                for row in &rows {
                    cancel_row(st, pool, *row);
                }
            }
        }
        Request::DirSize { rows } => {
            queue_dirsizes(out, st, &rows);
        }
        // No rows form: a stale row from a scrolled-past viewport would delay the rows the new one wants, see docs/protocol.md "dirsizecancel".
        Request::DirSizeCancel => {
            st.dirsize_queue.clear();
            st.dirsize_worker.cancel();
        }
        Request::Transfer { op, paths, rows, dest, menu_id, shelf, collide } => {
            if !shelf.is_empty() {
                crate::backend::shelfdrop::start(out, ops, &shelf, &dest, collide)
            } else if menu_id != 0 {
                start_menu_transfer(out, ops, &op, menu_id, &dest, collide)
            } else {
                let named = resolve_rows(paths, &rows, &st.base, &st.listing);
                start_transfer(out, ops, &op, named, &dest, collide)
            }
        }
        Request::Collisions { id, paths, rows, dest, menu_id } => super::collide::ask_beside(ops, id, menu_id, resolve_rows(paths, &rows, &st.base, &st.listing), &dest, &tb.mime, &tb.icons),
        Request::Link { op, paths, rows, dest, collide } => {
            let named = resolve_rows(paths, &rows, &st.base, &st.listing);
            start_link(out, ops, &op, named, &dest, collide)
        }
        Request::LinkTarget { path, id } => start_link_target(ops, &path, id),
        Request::PermissionsBatch { paths, modes, id } => do_permissions_batch(out, ops, paths, modes, id),
        Request::TransferCancel { id } => cancel_transfer(out, ops, id),
        Request::Trash { paths, rows, menu_id } => {
            let named = resolve_rows(paths, &rows, &st.base, &st.listing);
            start_trash(out, ops, named, menu_id)
        }
        Request::Rename { path, to, menu_id } => {
            if menu_id == 0 { do_rename(out, ops, &path, &to); }
            else { super::opsdispatch::do_menu_rename(out, ops, &path, &to, menu_id); }
        }
        Request::MkDir { path, name } => do_mkdir(out, ops, &path, &name),
        Request::NewFile { path, name, id } => do_newfile(out, ops, &path, &name, id),
        Request::Duplicate { path, menu_id } => start_duplicate(out, ops, &path, menu_id),
        Request::Undo => do_undo(out, ops),
        Request::Redo => start_redo(out, ops),
        // Never touches st.listing, which is the whole point: a column is not the pane's own listing.
        Request::Peek { path, first, hidden, hidden_last, focus } => {
            let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
            let base = PathBuf::from(&path);
            let mime = std::sync::Arc::clone(&tb.mime);
            let icons = std::sync::Arc::clone(&tb.icons);
            match super::iomount::call(&base, &body, "peek", move || {
                peek_line(&path, first, hidden, hidden_last, &focus, &mime, &icons)
            }) {
                Ok(line) => say(out, &line),
                Err(_) => say(out, &format!("{{\"t\":\"peeked\",\"path\":\"{}\",\"hidden\":{},\"hiddenLast\":{},\"first\":{},\"n\":0,\"failed\":true,\"rows\":[]}}", crate::json::escape(&base.to_string_lossy()), hidden, hidden_last, first)),
            }
        }
        // A compress names absolute paths and no path; an extract names the one archive in path.
        Request::Archive { op, paths, path, dest, format, menu_id } => start_archive(
            out, ops, Arc::clone(&tb.formats), &op,
            paths, format, PathBuf::from(&path), PathBuf::from(&dest), menu_id),
        Request::Convert { path, dest, strip, menu_id, request_id, check } =>
            start_convert(out, ops, PathBuf::from(&path), PathBuf::from(&dest), strip, menu_id, request_id, check),
        Request::Formats { id } => {
            let mut line = formats_line(&tb.formats, convert::available());
            line.insert_str(line.len() - 1, &format!(r#", "id":{},"providers":{}"#, id, super::providers::facts()));
            say(out, &line);
        }
        // The class rides beside the figures once per directory change; a slow mount's fresh figures follow as a second line.
        Request::FsInfo => {
            let (info, class) = fsinfo.answer(&st.base);
            say(out, &fsinfo_line(&info, &st.base.to_string_lossy(), class));
        }
        Request::PdfCopy { id, slot, path } => {
            super::pdfcopy::spawn(id, slot, PathBuf::from(&path), ops.tx.clone());
        }
        // One row, only when a client asked: the same no-sweep rule thumb and dirsize already follow.
        Request::Meta { row, text, media, archive, token } => {
            if row < st.listing.len() {
                let want = if archive { Some(Arc::clone(&tb.formats)) } else { None };
                spawn_meta(row, st.base.join(st.listing.name(row)), text, media, want, token, ops.tx.clone())
            }
        }
        // The Make executable row's own probe, answered on a thread: an open on a hung mount never returns.
        Request::Shebang { path, id } => {
            super::shebang::spawn(PathBuf::from(&path), id, ops.tx.clone())
        }
        Request::Paths { rows } =>
            say(out, &paths_line(&resolve_rows(Vec::new(), &rows, &st.base, &st.listing))),
        Request::Locate { path } => {
            let index = st.listing.index_of(&st.base, Path::new(&path));
            say(out, &super::proto::located_line(&st.base.to_string_lossy(), &path, index));
        }
        Request::LocateMany { paths, id, menu_id, transfer_id } => {
            let mut matches = st.listing.indices_of(&st.base, &paths);
            let error = if transfer_id > 0 {
                if ops.transfer_retry.0 != transfer_id {
                    Some("Transfer retry identities expired; select the items again.".to_string())
                } else {
                    super::opsreq::retain_retry(&ops.transfer_retry.1, &mut matches);
                    None
                }
            } else if menu_id == 0 { None } else {
                ops.menuactions.as_ref().ok_or_else(|| "Deletion survivor identities expired; select the items again.".to_string())
                    .and_then(|menu| menu.retain_survivors(menu_id, &mut matches)).err()
            };
            if error.is_some() { matches.clear(); }
            say(out, &super::proto::located_many_line(&st.base.to_string_lossy(), id, transfer_id, &matches, error.as_deref()));
        }
        Request::Jump { id, favourites, recent } => super::jump::request(id, favourites, recent, ops.tx.clone()),
        Request::Quit => return Control::Quit,
        // corner: an unrecognised line is answered with silence, see AGENTS.md.
        Request::Unknown => {}
    }
    Control::Continue
}

// A new row order invalidates every outstanding index, so the queue goes and no result can be reported against the new listing.
pub fn forget_rows(st: &mut State, pool: &Pool) {
    st.generation += 1;
    st.outstanding = st.outstanding.saturating_sub(pool.cancel_all().len());
    st.asked.clear();
    st.window_meta.clear();
    // A list or a sort changes which row an index names, the same reason thumbnails clear their map.
    st.dirsizes.clear();
    st.dirsize_queue.clear();
    st.dirsize_worker.cancel();
}

// A worker-built listing lands without a syscall, carrying its own dev and writability.
pub(crate) fn adopt_listed(out: &mut impl Write, st: &mut State, pool: &Pool, tb: &Tables, path: &str, done: super::iomount::ListOut, want_changed: bool) {
    // A same-path re-list names added plus removed rows, so a rename counts 2 against a net delta of 0.
    let same = st.held == Held::List && Path::new(path) == st.base.as_path();
    let changed = if same && want_changed { crate::backend::listing::changed_count(&st.listing, &done.listing) } else { 0 };
    st.base = PathBuf::from(path);
    st.listing = done.listing;
    // A list holds a directory now, so only its own re-read counts.
    st.held = Held::List;
    forget_rows(st, pool);
    seed_answered(st, &done.sized);
    let listed = super::proto::say_listed(st.listing.len(), done.read_ms, done.sort_ms, done.dev, &st.base.to_string_lossy(), done.writable);
    let listed = if same && want_changed { crate::backend::proto::with_changed(&listed, changed) } else { listed };
    writeln!(out, "{}", listed).ok();
    let mut kinds = tb.kinds.borrow_mut();
    let line = super::rows::rows_line(&st.listing, &done.first_metas, 0, done.first_ms, &tb.mime, &tb.icons, &tb.aliases, &tb.thumbs, &mut kinds);
    writeln!(out, "{}", super::rowguard::stamped(line, st.generation)).ok();
}

// Search advances only when the request channel is idle.
fn tick_walkers(out: &mut BufWriter<io::Stdout>, st: &mut State, pool: &Pool) {
    // A finished walk hands back its rows in ranked order, which renames every outstanding index.
    if step_search(out, st) {
        forget_rows(st, pool);
    }
}

// A worker inside a child owns a temp file in the shared cache that only its own return publishes or removes; see AGENTS.md "Thumbnail requests".
pub(crate) fn drain(
    out: &mut impl Write,
    st: &mut State,
    ops: &mut Ops,
    rx: &Receiver<Event>,
    pool: &Pool,
    cache: &Cache,
) {
    let deadline = Instant::now() + DRAIN_LIMIT;
    // A clean shutdown cancels the slot operation and each detached job, so a cancelled copy removes its partial destination and each Work cleanup runs.
    if let Some(id) = ops.live.running() {
        ops.live.cancel(id);
    }
    ops.detached.cancel_all();
    while st.outstanding > 0 || ops.live.running().is_some() || !ops.detached.is_empty() {
        match rx.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
            Ok(Event::Thumb(d)) => report_done(out, st, d),
            Ok(Event::Op(m)) => report_op(out, ops, m),
            Ok(_) => {}
            Err(_) => break,
        }
    }
    pool.cancel_all();
    // The queue is empty now, so no worker can start a new job and the temps still on disk are exactly the abandoned ones.
    if st.outstanding > 0 {
        sweep_own_temps(&cache.large_dir());
    }
    // corner: a row the deadline cut short is answered empty rather than left unanswered, see AGENTS.md "Thumbnail requests".
    for (_, row) in std::mem::take(&mut st.asked) {
        writeln!(out, "{}", thumbed_line(row, "", 0.0)).ok();
    }
    out.flush().ok();
}

pub fn write_window(out: &mut impl Write, st: &mut State, start: usize, count: usize, tb: &Tables) {
    let (metas, ms) = stat_range(&st.base, &st.listing, start, count);
    let start = start.min(st.listing.len());
    for (i, m) in metas.iter().enumerate() {
        st.window_meta.insert(start + i, (m.mode, m.mtime, m.target_is_dir));
    }
    // Sample window: start 0 with 3 metas keeps keys 0..3, so a scrolled-past window never grows the map.
    let end = start.saturating_add(metas.len());
    st.window_meta.retain(|&row, _| row >= start && row < end);
    let mut kinds = tb.kinds.borrow_mut();
    let line = rows_line(&st.listing, &metas, start, ms, &tb.mime, &tb.icons, &tb.aliases, &tb.thumbs, &mut kinds);
    writeln!(out, "{}", super::rowguard::stamped(line, st.generation)).ok();
}

// The walk root's figures, statted through the bound so a dead server answers instead of hanging.
pub(crate) fn search_root_info(base: &Path) -> Result<(u64, bool), FleaError> {
    let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    let owned = base.to_path_buf();
    let key = owned.clone();
    super::iomount::call(&key, &body, "search", move || (super::fsinfo::dev_of(&owned), super::ops::dir_writable(&owned)))
}

// One window's metas: remoteness is decided before anything is moved, so a local window stats inline with no clone and a remote one moves only its rows to the worker.
pub(crate) fn window_metas(st: &State, start: usize, count: usize) -> Result<(Vec<Meta>, f64), FleaError> {
    let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    if super::iomount::is_remote(&st.base, &body) {
        let rows = super::meta::window_rows(&st.listing, start, count);
        let threaded = st.listing.threaded_cached_with(&body);
        let base = st.base.clone();
        super::iomount::call(&base.clone(), &body, "window", move || super::meta::stat_window_rows(&base, &rows, threaded))
    } else {
        Ok(super::meta::stat_range(&st.base, &st.listing, start, count))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;

    const REPLY_DEADLINE: Duration = Duration::from_secs(5);
    const THUMB_TEST_WORKERS: usize = 1;

    #[test]
    fn a_held_link_keeps_requests_responsive_and_holds_the_operation_slot() {
        let d = TestDir::new("heldlink");
        let src = d.dir("src");
        let a = d.file("src/a.txt", "a");
        let b = d.file("src/b.txt", "b");
        let dest = d.dir("dest");
        let (release, entered) = super::super::opsdispatch::test_hold_link(&dest);
        let (answered, answers) = channel();
        let dest_path = dest.clone();
        let cache_root = d.join("cache");
        let backend = std::thread::spawn(move || {
            let tb = Tables::load();
            let (events, _events_rx) = channel();
            let mut st = State::new(super::super::dirsizeworker::Worker::new(events.clone()));
            st.base = src;
            st.listing.push("a.txt", false);
            st.listing.push("b.txt", false);
            let (results, _done) = channel();
            let pool = Pool::new(THUMB_TEST_WORKERS, results, cache_root, Arc::clone(&tb.aliases), Arc::clone(&tb.thumbs));
            let cache = Cache::new();
            let (tx, rx) = channel();
            let mut ops = Ops::new(tx);
            let mut watch = Watch::start(events.clone());
            let mut fsinfo = FsInfo::new(events.clone());
            let poller = super::super::watchpoll::Poller::new(events.clone());
            let link = format!(r#"{{"c":"link","rows":[0,1],"dest":"{}","op":"relative"}}"#, crate::json::escape(&dest_path.to_string_lossy()));
            let mut out = Vec::new();
            for line in [&link, r#"{"c":"paths","rows":[0,1]}"#, &link] {
                assert!(handle_line(line, &mut out, &mut st, &tb, &pool, &cache, &mut ops,
                    &mut watch, &mut fsinfo, &poller, &events) == Control::Continue);
            }
            answered.send((std::mem::take(&mut out), ops.live.running().is_some(), ops.journal.is_empty(), ops.pending.is_empty())).unwrap();
            let landed = rx.recv_timeout(REPLY_DEADLINE).expect("the released link reports through the op channel");
            assert!(matches!(landed, OpMsg::Linked { .. }), "the production link sends Linked");
            report_op(&mut out, &mut ops, landed);
            assert_eq!(String::from_utf8_lossy(&out).trim(), r#"{"t":"linked","ok":2,"failed":0,"skipped":0}"#);
            assert_eq!(ops.journal.len(), 1, "one journal entry covers both links");
            assert!(ops.live.running().is_none(), "Linked releases the operation slot");
            super::super::opsdispatch::do_undo(&mut out, &mut ops);
            assert!(String::from_utf8_lossy(&out).contains(r#"{"t":"undone","op":"link","ok":true}"#));
        });
        entered.recv_timeout(REPLY_DEADLINE).expect("run_link reached the handshake");
        let responsive = answers.recv_timeout(REPLY_DEADLINE);
        drop(release);
        backend.join().expect("the backend finishes after releasing the held link");
        let (out, running, unjournalled, no_pending) = responsive.expect("a held link must leave Request::Paths responsive");
        let lines = String::from_utf8(out).unwrap();
        let mut replies = lines.lines();
        assert_eq!(replies.next(), Some(paths_line(&[a.to_string_lossy().to_string(), b.to_string_lossy().to_string()]).as_str()));
        let refused = replies.next().expect("the second link is refused while the slot is held");
        assert!(refused.contains(r#""t":"error""#) && refused.contains("an operation is already running"), "{refused}");
        assert!(replies.next().is_none(), "a held link emits neither slow nor a premature linked line: {lines}");
        assert!(running && unjournalled && no_pending, "the link holds the slot, with no slow claim or journal before completion");
        assert!(std::fs::symlink_metadata(dest.join("a.txt")).is_err(), "undo removed the first link");
        assert!(std::fs::symlink_metadata(dest.join("b.txt")).is_err(), "undo removed the second link");
        assert!(a.exists() && b.exists(), "undo preserves both sources");
    }

    // A local window stats inline: an O(directory) copy per scroll breaks load-bearing rule 1.
    #[test]
    fn a_local_window_stats_inline_with_no_bound_call() {
        crate::backend::iomount::test_reset();
        let d = TestDir::new("windowlocal");
        d.file("a.txt", "a");
        d.file("b.txt", "b");
        let (tx, _rx) = channel::<Event>();
        let mut st = State::new(crate::backend::dirsizeworker::Worker::new(tx));
        st.base = d.path().to_path_buf();
        st.listing.push("a.txt", false);
        st.listing.push("b.txt", false);
        let (metas, _) = window_metas(&st, 0, 10).expect("a local window answers");
        assert_eq!(metas.len(), 2, "the window carries its rows");
        assert_eq!(crate::backend::iomount::test_calls(), 0, "a local window takes no bound call and clones no listing");
    }

    // The search root's figures go through the bound, so a dead server answers instead of hanging.
    #[test]
    fn a_search_root_is_statted_through_the_bound() {
        crate::backend::iomount::test_reset();
        let d = TestDir::new("searchroot");
        let (dev, writable) = search_root_info(d.path()).expect("a live root answers");
        assert_eq!(dev, crate::backend::fsinfo::dev_of(d.path()), "the bound answers the root's own figures");
        assert!(writable, "the sandbox is writable");
        assert_eq!(crate::backend::iomount::test_calls(), 1, "the root's stat takes exactly one bound call");
    }
}
