.import "../../ui/js/Anchor.js" as Anchor
.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/Ops.js" as Ops
.import "../../ui/js/Errors.js" as Errors
.import "../../ui/js/Swap.js" as Swap
.import "../../ui/js/Sort.js" as Sort
.import "../../ui/js/SlowOp.js" as SlowOp
.import "sourcefixture.js" as Source

// Issue 68's watched re-read: a change another program made under the open listing is read again
// without moving the user off the file they were on. Its own suite because tests/js/nav.js sits at
// the 300-line JS hard cap, and because this is one behaviour rather than another navigation.

// Only the members openWithoutHistory writes, so the check is what a new listing forgets.
function pane() {
    var p = {
        listInFlight: false,
        listedSeen: true,
        path: "/home/gm",
        total: 40,
        held: 10,
        rows: [{ n: "a" }],
        kindNames: ["Plain text document"],
        thumbState: "stale",
        dirSizeState: "stale",
        cursorIndex: 7,
        renamingIndex: 4,
        trashArmedAt: 12345,
        listingState: "ready",
        stateMessage: "something",
        lockedMode: 0o40750,
        filterQuery: "scr",
        filterTyping: true,
        cleared: 0,
        said: [],
        sent: [],
        want: []
    }
    p.clearSelection = function () { p.cleared += 1 }
    p.message = function (text, isError) { p.said.push(text) }
    p.listArea = { primeSettle: function () {} }
    // ui/PaneSwap.qml with nothing held, so the reset and the query it hands back both run at the request.
    p.swap = { hold: function () { return false } }
    p.backend = {
        list: function (path, first, hidden, wantChanged) {
            p.sent.push("list " + path)
            p.want.push(wantChanged === true)
        },
        askFsInfo: function () { p.sent.push("fsinfo") },
        window: function (start, count) { p.sent.push("window " + start) }
    }
    return p
}

// Issue 68's re-read, which unlike a navigation puts the user back where they were. windowSize and
// setCursor are the two members only this path uses; rowFor is the pane's own held-window lookup.
function watched(held, rows, cursorIndex, total) {
    var p = pane()
    p.held = held
    p.rows = rows
    p.cursorIndex = cursorIndex
    p.total = total === undefined ? 40 : total
    p.windowSize = 350
    p.cursorSetTo = -1
    p.contexts = []
    p.rowFor = function (index) {
        var offset = index - p.held
        return offset < 0 || offset >= p.rows.length ? null : p.rows[offset]
    }
    p.setCursor = function (index, context) {
        p.cursorSetTo = index
        p.contexts.push(context)
    }
    // Only a delete's own anchor selects; a watched re-read must never touch the operator's marks.
    p.selectedAt = -1
    p.selectOnly = function (index, context) {
        p.selectedAt = index
        p.cursorSetTo = index
        p.contexts.push(context)
    }
    // The same wrapper ui/Pane.qml carries, so the re-read takes the one route that can refuse.
    p.openWithoutHistory = function (target, options) { Nav.openWithoutHistory(p, target, options) }
    // A preference anchor re-marks by name, so the stub carries the mark set the pane owns.
    p.marked = []
    p.selection = { clear: function () { p.marked = [] }, toggle: function (i) { p.marked.push(i) } }
    p.selectionVersion = 0
    return p
}


function run(check) {
    // Issue 68: a change another program made under the listing is re-read in place. The cursor goes
    // back on the file it was on by name, because a create above it renumbers every row below.
    var seen = watched(0, [{ n: "a" }, { n: "b" }, { n: "c" }], 1)
    var anchor = Anchor.watched(seen)
    check("a watched re-read asks for the same directory again",
          seen.sent.join(","), "list /home/gm,fsinfo")
    check("and anchors on the name the cursor was on, not on its index",
          anchor.name + "|" + anchor.index, "b|1")
    check("and keeps the filter, which narrows rows rather than choosing the directory",
          seen.filterQuery, "scr")
    check("and a watched re-read asks for no count", seen.want.join(","), "false")
    // A manual reload wants the count, so true reaches backend.list through Nav.
    var seenCounted = watched(0, [{ n: "a" }, { n: "b" }, { n: "c" }], 1)
    var countedAnchor = Anchor.watched(seenCounted, true)
    check("and a watched re-read that wants the count asks for it", seenCounted.want.join(","), "true")
    check("and the counted re-read still anchors on the cursor name", countedAnchor.name, "b")

    // The name moved down a row, which is exactly what a create above the cursor does.
    seen.held = 0
    seen.rows = [{ n: "NEW" }, { n: "a" }, { n: "b" }, { n: "c" }]
    seen.total = 41
    check("the cursor lands on the anchored name at its new index",
          Anchor.apply(seen, anchor) + "|" + seen.cursorSetTo, "null|2")
    check("and the re-land moves with context 0", seen.contexts.join(","), "0")

    // A name that is gone leaves the old index, which keeps the view where the user left it rather
    // than throwing them back to the top of the directory.
    var deleted = watched(0, [{ n: "a" }, { n: "c" }], 1, 2)
    check("a deleted anchor falls back to the index it had",
          Anchor.apply(deleted, { name: "b", index: 1, start: 0, path: "/home/gm" }) + "|" + deleted.cursorSetTo, "null|1")
    var shrunk = watched(0, [{ n: "a" }], 7, 1)
    check("and that index is clamped to what the directory now holds",
          Anchor.apply(shrunk, { name: "gone", index: 7, start: 0, path: "/home/gm" }) + "|" + shrunk.cursorSetTo, "null|0")
    var emptied = watched(0, [], 3, 0)
    check("a directory that emptied moves no cursor at all",
          Anchor.apply(emptied, { name: "gone", index: 3, start: 0, path: "/home/gm" }) + "|" + emptied.cursorSetTo, "null|-1")

    // PR 53's own guard: a delete that landed anchors on the row the request went out with, which
    // for a block is the row the block left; one that failed anchors on the row the cursor was on.
    var landed = watched(0, [{ n: "a" }, { n: "b" }, { n: "c" }], 2, 3)
    landed.trashedFirst = 1
    check("a delete that landed anchors where the block was",
          Anchor.afterDelete(landed, true).index + "|" + landed.trashedFirst, "1|-1")
    var refused = watched(0, [{ n: "a" }, { n: "b" }, { n: "c" }], 2, 3)
    refused.trashedFirst = 1
    check("and one that failed anchors on the row the cursor was already on",
          Anchor.afterDelete(refused, false).index + "|" + refused.trashedFirst, "2|-1")

    // A cursor deep in a large directory: the re-read answers from row 0, so its own window is asked
    // for and the anchor stands until that window arrives rather than giving up on the first reply.
    var deep = watched(4000, [{ n: "m" }, { n: "n" }], 4001, 100000)
    var deepAnchor = Anchor.watched(deep)
    check("a re-read below the first window asks for the window the cursor was in",
          deep.sent.join(","), "list /home/gm,fsinfo,window 4000")
    // A rows reply waits until its listed line has run, so it always carries its total; see ui/PaneSwap.qml.
    deep.held = 0
    deep.rows = [{ n: "a" }, { n: "b" }]
    deep.total = 100000
    check("and the first window, which cannot hold that name, does not resolve the anchor",
          Anchor.apply(deep, deepAnchor) === deepAnchor, true)
    check("and moves no cursor while it waits", deep.cursorSetTo, -1)
    // The wait is on the window arriving, not on a number of replies, so more of the first window
    // in between does not give up on it; the anchor leaks for good if this ever stops holding.
    check("more replies at the first window do not give up on the window asked for",
          Anchor.apply(deep, deepAnchor) === deepAnchor, true)
    check("and still move no cursor", deep.cursorSetTo, -1)
    // A listing that shrank past that offset comes back clamped to row 0, so the window asked for is
    // never coming; waiting on it for ever would leave the cursor unrestored and the anchor leaking.
    var clamped = watched(4000, [{ n: "m" }, { n: "n" }], 4001, 100000)
    var clampedAnchor = Anchor.watched(clamped)
    clamped.held = 0
    clamped.rows = [{ n: "a" }, { n: "b" }]
    clamped.total = 2
    check("a listing that shrank past the window asked for resolves against the clamp",
          Anchor.apply(clamped, clampedAnchor) + "|" + clamped.cursorSetTo, "null|1")
    // A listing of exactly start rows holds 0 to start-1, so window(start) is clamped here too: this is
    // the offset the comparison has to exclude, and a >= would wait on that reply for ever.
    var exact = watched(4000, [{ n: "m" }, { n: "n" }], 4001, 100000)
    var exactAnchor = Anchor.watched(exact)
    exact.held = 0
    exact.rows = [{ n: "a" }, { n: "b" }]
    exact.total = 4000
    check("a listing of exactly the offset asked for is clamped too, and resolves",
          Anchor.apply(exact, exactAnchor) + "|" + exact.cursorSetTo, "null|3999")
    deep.held = 4000
    deep.rows = [{ n: "m" }, { n: "n" }]
    check("the window it asked for is what puts the cursor back",
          Anchor.apply(deep, deepAnchor) + "|" + deep.cursorSetTo, "null|4001")

    // Nothing under the cursor is not a reason to refuse the re-read; the index still stands.
    var unloaded = watched(500, [{ n: "x" }], 3)
    var noRow = Anchor.watched(unloaded)
    check("a cursor over a row the pane does not hold anchors on no name", noRow.name, "")

    // The anchor can outlive one rows reply, so a navigation in between drops it rather than putting
    // this directory's cursor row onto the next directory's listing.
    var left = watched(0, [{ n: "a" }, { n: "b" }], 1)
    var leftAnchor = Anchor.watched(left)
    left.path = "/home/gm/Work"
    left.rows = [{ n: "b" }]
    left.total = 1
    check("an anchor from another directory is dropped, not applied",
          Anchor.apply(left, leftAnchor) + "|" + left.cursorSetTo, "null|-1")

    // A re-read while a listing is already running would queue a second one behind it.
    var loading = watched(0, [{ n: "a" }], 0)
    loading.listInFlight = true
    check("a re-read is refused while a list is in flight",
          Anchor.watched(loading) === null && loading.sent.length === 0, true)
    check("and an absent anchor resolves to nothing", Anchor.apply(loading, null), null)

    // Reported 2026-09-11: "deleting one refreshes the entire file list and loses my selection, so I
    // have to start over". The rows that were marked are gone, so the anchor is the deleted cursor
    // row and applyAnchor's own fallback lands on whatever took its place, selected.
    var deleted2 = watched(0, [{ n: "a" }, { n: "b" }, { n: "c" }], 1)
    var deleteAnchor = Anchor.afterDelete(deleted2)
    check("a delete re-reads the same directory", deleted2.sent.join(","), "list /home/gm,fsinfo")
    check("and anchors on the row that was deleted", deleteAnchor.name, "b")
    deleted2.rows = [{ n: "a" }, { n: "c" }]
    deleted2.total = 2
    check("the row that took its place takes the cursor",
          Anchor.apply(deleted2, deleteAnchor) + "|" + deleted2.cursorSetTo, "null|1")
    check("and it is selected, so the next delete needs no mouse", deleted2.selectedAt, 1)

    // The last row deleted has nothing below it, so the cursor lands on the new last row.
    var lastGone = watched(0, [{ n: "a" }, { n: "b" }, { n: "c" }], 2)
    var lastAnchor = Anchor.afterDelete(lastGone)
    lastGone.rows = [{ n: "a" }, { n: "b" }]
    lastGone.total = 2
    check("deleting the last row selects the new last row",
          Anchor.apply(lastGone, lastAnchor) + "|" + lastGone.selectedAt, "null|1")

    // A delete that failed leaves the row standing, and then the name matches and the cursor and the
    // selection both go back exactly where they were.
    var refused = watched(0, [{ n: "a" }, { n: "b" }, { n: "c" }], 1)
    var refusedAnchor = Anchor.afterDelete(refused)
    refused.rows = [{ n: "a" }, { n: "b" }, { n: "c" }]
    refused.total = 3
    check("a delete nothing removed puts the cursor back on the same file",
          Anchor.apply(refused, refusedAnchor) + "|" + refused.selectedAt, "null|1")

    // Emptying a directory leaves nothing to select, and selecting row -1 would be a mark on nothing.
    var emptied2 = watched(0, [{ n: "a" }], 0)
    var emptyAnchor = Anchor.afterDelete(emptied2)
    emptied2.rows = []
    emptied2.total = 0
    check("deleting the only row selects nothing rather than a row that is not there",
          Anchor.apply(emptied2, emptyAnchor) + "|" + emptied2.selectedAt, "null|-1")

    // The watch's own anchor must not have grown a selection with it: a change another program made
    // is not a reason to rewrite what the operator had marked.
    var untouched = watched(0, [{ n: "a" }, { n: "b" }], 1)
    var untouchedAnchor = Anchor.watched(untouched)
    untouched.rows = [{ n: "a" }, { n: "b" }]
    check("a watched re-read still only moves the cursor",
          Anchor.apply(untouched, untouchedAnchor) + "|" + untouched.selectedAt, "null|-1")

    // The same refusal the watched re-read carries, for the same reason.
    var busy = watched(0, [{ n: "a" }], 0)
    busy.listInFlight = true
    check("a delete re-read is refused while a list is in flight",
          Anchor.afterDelete(busy) === null && busy.sent.length === 0, true)

    // A click-away rename keeps the pointer's row: the reply anchors on the clicked name.
    var click = watched(0, [{ n: "a-original.md" }, { n: "b-existing.md" }], 1, 1202)
    click.path = "/dir"
    var clickReq = { source: "/dir/a-original.md", destination: "/dir/c-clickaway.md", folder: "/dir" }
    var clickAnchor = Anchor.pointerRow(click, clickReq)
    check("a click-away anchors on the clicked row, not the renamed one",
          clickAnchor.name + "|" + clickAnchor.index + "|" + clickAnchor.start + "|" + clickAnchor.select,
          "b-existing.md|1|0|true")
    click.rows = [{ n: "b-existing.md" }, { n: "c-clickaway.md" }]
    click.total = 1202
    check("and lands on that name after the rows shift",
          Anchor.apply(click, clickAnchor) + "|" + click.cursorSetTo, "null|0")
    check("and selects it, so the next write reads the clicked row", click.selectedAt, 0)

    // Enter still sits on the source when the reply lands, so that leaf maps to the dest.
    var enter = watched(0, [{ n: "a-original.md" }, { n: "b-existing.md" }], 0, 1202)
    enter.path = "/dir"
    var enterReq = { source: "/dir/a-original.md", destination: "/dir/a-clickaway.md", folder: "/dir" }
    var enterAnchor = Anchor.pointerRow(enter, enterReq)
    check("Enter maps the source leaf to the destination leaf",
          enterAnchor.name + "|" + enterAnchor.index, "a-clickaway.md|0")
    enter.rows = [{ n: "a-clickaway.md" }, { n: "b-existing.md" }]
    check("and the renamed row is found in the first window",
          Anchor.apply(enter, enterAnchor) + "|" + enter.cursorSetTo, "null|0")

    // A deep click-away needs its old window back, the same wait a watched re-read does.
    var deepClick = watched(900, [{ n: "f1198.txt" }, { n: "f1199.txt" }], 900, 1202)
    deepClick.path = "/dir"
    var deepReq = { source: "/dir/f1199.txt", destination: "/dir/f1199-new.txt", folder: "/dir" }
    var deepAnchor = Anchor.pointerRow(deepClick, deepReq)
    check("a deep click-away anchors with its old window",
          deepAnchor.name + "|" + deepAnchor.start, "f1198.txt|900")
    deepClick.held = 0
    deepClick.rows = [{ n: "a-original.md" }, { n: "b-existing.md" }]
    deepClick.total = 1202
    check("the first window does not resolve a deep click-away",
          Anchor.apply(deepClick, deepAnchor) === deepAnchor, true)
    deepClick.held = 900
    deepClick.rows = [{ n: "f1199-new.txt" }, { n: "f1198.txt" }]
    check("the asked window puts the cursor back on the clicked row",
          Anchor.apply(deepClick, deepAnchor) + "|" + deepClick.cursorSetTo, "null|901")

    // A deep Enter misses the first window too, so it waits for the same ask.
    var deepEnter = watched(900, [{ n: "f1199.txt" }], 900, 1202)
    deepEnter.path = "/dir"
    var deepEnterAnchor = Anchor.pointerRow(deepEnter, deepReq)
    check("a deep Enter maps to the destination leaf",
          deepEnterAnchor.name + "|" + deepEnterAnchor.start, "f1199-new.txt|900")
    deepEnter.held = 0
    deepEnter.rows = [{ n: "a-original.md" }]
    deepEnter.total = 1202
    check("its first window waits too",
          Anchor.apply(deepEnter, deepEnterAnchor) === deepEnterAnchor, true)
    deepEnter.held = 900
    deepEnter.rows = [{ n: "f1198.txt" }, { n: "f1199-new.txt" }]
    check("and its window lands on the renamed row",
          Anchor.apply(deepEnter, deepEnterAnchor) + "|" + deepEnter.cursorSetTo, "null|901")

    // A cursor past the held window has no name to keep, but its index still stands.
    var beyond = watched(0, [{ n: "a" }], 5, 1202)
    beyond.path = "/dir"
    var beyondAnchor = Anchor.pointerRow(beyond, clickReq)
    check("a cursor past the held window anchors on no name but keeps its index",
          beyondAnchor.name + "|" + beyondAnchor.index, "|5")

    // A preference re-list keeps selection and cursor by name across a hidden toggle that inserts .dot ahead of the files.
    var pref = watched(0, [{ n: "sub" }, { n: "a.txt" }, { n: "b.txt" }], 2)
    pref.path = "/dir"
    pref.selectedIndices = function () { return [1, 2] }
    var prefAnchor = Anchor.preference(pref)
    check("a preference anchor names the cursor file", prefAnchor.name, "b.txt")
    check("and the selected files", prefAnchor.selected.join(","), "a.txt,b.txt")
    pref.held = 0
    pref.rows = [{ n: ".dot" }, { n: "sub" }, { n: "a.txt" }, { n: "b.txt" }]
    pref.total = 4
    Anchor.applyPreference(pref, prefAnchor)
    check("the cursor follows its file past the insertion", pref.cursorSetTo, 3)
    check("and the selection follows its files too", pref.marked.join(","), "2,3")
    // A selection reaching past the held window never keeps its in-window subset; the whole of it clears instead.
    var wide = []
    for (var w = 0; w < 350; w++) wide.push({ n: "f" + w })
    var partial = watched(0, wide, 10)
    partial.selectedIndices = function () { var all = []; for (var s = 0; s < 500; s++) all.push(s); return all }
    check("a selection past the held window clears whole", Anchor.preference(partial).selected.length, 0)
    // A pane without rowFor drops the selection instead of throwing on it.
    var noRowFor = { cursorIndex: 1, held: 0, path: "/dir", selectedIndices: function () { return [0, 1] } }
    check("a pane without rowFor drops the selection instead of throwing", Anchor.preference(noRowFor).selected.length, 0)
    // A preference anchor waits only for its asked window: a scrolled reply or a moved cursor drops it without moving anything.
    var asked = { name: "m", index: 4000, start: 4000, path: "/home/gm", selected: [] }
    var firstWin = watched(4000, [{ n: "a" }, { n: "b" }], 0, 100000)
    firstWin.held = 0
    check("the first window keeps the anchor waiting", Anchor.applyPreference(firstWin, asked) === asked, true)
    var scrolled = watched(4000, [{ n: "x" }, { n: "y" }], 0, 100000)
    scrolled.held = 350
    check("a scrolled window drops it without moving", Anchor.applyPreference(scrolled, asked) === null && scrolled.cursorSetTo === -1, true)
    var moved = watched(4000, [{ n: "a" }, { n: "b" }], 7, 100000)
    moved.held = 0
    check("a moved cursor drops it too", Anchor.applyPreference(moved, asked) === null && moved.cursorSetTo === -1, true)
    var landedWin = watched(4000, [{ n: "m" }, { n: "n" }], 0, 100000)
    landedWin.held = 4000
    check("its asked window lands the cursor", Anchor.applyPreference(landedWin, asked) === null && landedWin.cursorSetTo === 4000, true)
    var clampedPref = watched(4000, [{ n: "a" }], 0, 2)
    clampedPref.held = 0
    var clampedAnchor = { name: "gone", index: 4001, start: 4000, path: "/home/gm", selected: [] }
    check("a listing clamped past the asked window still resolves", Anchor.applyPreference(clampedPref, clampedAnchor) === null && clampedPref.cursorSetTo === 1, true)
    renameReplies(check)
}

// The rename request, reply and refresh handlers, compiled from the shipped ui/ source so a changed handler is what runs.
// Sample input: "function refreshRename(request, selected, pointer) {" up to the "Connections {" that follows it.
function handler(file, from, to) {
    var text = Source.slice(Source.source(file), from, to)
    return eval("(function (pane, root, watchSettle, Anchor, Nav, SlowOp, Errors, Ops, Swap, Sort) { return (" + text + ") })")
}

// What the pane showed, re-read and windowed, reset per editing(); closure arrays so every stub field is a real Pane property.
var messages = [], refreshed = [], windowed = []
// One editing pane with the cursor on before.txt (index 7, top of the list), Return already committed after.txt.
function editing() {
    messages = []
    refreshed = []
    windowed = []
    var wireFile = "ui/PaneWire.qml"
    var p = { path: "/fixture/list", cursorIndex: 7, held: 0, windowSize: 350, shown: null, renameRequest: null, renameSource: "", renameError: "",
              renameMenuId: 42, renameKeepsPointerRow: false, listInFlight: false, searchMode: "", listingState: "ready",
              total: 40, sent: [] }
    var cursorRow = "before.txt"
    p.cursorOn = function (name) { cursorRow = name }
    p.setCursor = function (index) { p.cursorIndex = index }
    p.rowFor = function () { return { n: cursorRow } }
    p.renameEditor = function () { return p.renamingIndex >= 0 ? {} : null }
    p.join = function (base, name) { return base + "/" + name }
    p.swap = { drop: function () {} }
    p.message = function (text, error) { messages.push(text + "|" + error) }
    p.sticky = function () {}
    p.refresh = function (selected) { refreshed.push(selected) }
    p.renamingIndexValue = -1
    var clearEditor = eval("(function (root, Sort) { " + Source.slice(Source.source("ui/Pane.qml"),
        "onRenamingIndexChanged: ", "// A navigation during a slow rename").replace("onRenamingIndexChanged: ", "") + " })")
    Object.defineProperty(p, "renamingIndex", { get: function () { return p.renamingIndexValue },
        set: function (value) { p.renamingIndexValue = value; clearEditor(p, Sort) } })
    Object.defineProperty(p, "renamePending", { get: function () { return p.renameRequest !== null } })
    p.backend = { rename: function (a, b, c) { p.sent.push([a, b, c].join("|")) }, window: function (start, count) { windowed.push(start + "," + count) } }
    var root = { stale: false, anchor: null }
    var stop = { stop: function () {} }
    var refresh = handler(wireFile, "function refreshRename(request, selected, pointer) {", "\n    Connections {")(p, root, stop, Anchor, Nav, SlowOp, Errors, Ops, Swap, Sort)
    root.refreshRename = refresh
    var failed = handler(wireFile, "function onFailed(where, input, message, mode) {", "\n    }\n\n    // flea --ui-state")
    var renamed = handler(wireFile, "function onRenamed(ok, path) {", "// A remote write past its deadline")(p, root, stop, Anchor, Nav, SlowOp, Errors, Ops, Swap, Sort)
    p.fail = function (where, input, message) { failed(p, root, stop, Anchor, Nav, SlowOp, Errors, Ops, Swap, Sort)(where, input, message, 0) }
    p.done = function (name) { renamed(true, name) }
    p.wire = root
    p.startAt = function () { Ops.startRename(p, 42); Ops.commitRename(p, "after.txt") }
    p.startAt()
    return p
}

function renameReplies(check) {
    // A missing anchor reads as empty fields, so the red run names the check instead of throwing.
    function anchored(pane) { return pane.wire.anchor === null ? {} : pane.wire.anchor }
    function same(label, actual, expected) { check(label, JSON.stringify(actual), JSON.stringify(expected)) }
    var p = editing()
    same("Return sends the rename once", p.sent, ["/fixture/list/before.txt|after.txt|42"])
    p.done("/fixture/list/after.txt")
    same("a reply with the cursor still on the renamed row re-reveals it under its new name",
         [p.renamePending, p.renamingIndex, refreshed, p.wire.anchor, windowed], [false, -1, ["/fixture/list/after.txt"], null, []])

    // A click or a key that left the renamed row while the write was pending keeps its row, at the top and deep in the list.
    var shapes = [[0, "clicked.txt"], [900, "clicked.txt"], [0, "key-moved.txt"], [900, "key-moved.txt"]]
    for (var i = 0; i < shapes.length; i++) {
        var held = shapes[i][0], name = shapes[i][1]
        p = editing()
        p.cursorIndex = held + 3
        p.held = held
        p.cursorOn(name)
        p.done("/fixture/list/after.txt")
        same("a cursor moved while the rename was pending keeps its row at held " + held + ": " + name, refreshed, [""])
        same("and anchors on that row at held " + held,
             [anchored(p).name, anchored(p).index, anchored(p).start, anchored(p).select], [name, held + 3, held, true])
        same("and asks for its window only when it is deep, held " + held, windowed, held > 0 ? [held + ",350"] : [])
        // The failure replies that re-read the listing keep the moved cursor the same way.
        p = editing()
        p.cursorIndex = held + 3
        p.held = held
        p.cursorOn(name)
        p.fail("journal", "/fixture/list/after.txt", "permission denied")
        same("a destination-side journal failure keeps the moved cursor at held " + held, [refreshed, anchored(p).name], [[""], name])
    }

    // A cursor on the destination name is the renamed row, so the reply still reveals it; deep, the window comes back too.
    p = editing()
    p.cursorOn("after.txt")
    p.done("/fixture/list/after.txt")
    same("a cursor on the destination name reveals the renamed row", [refreshed, p.wire.anchor], [["/fixture/list/after.txt"], null])
    p = editing()
    p.cursorIndex = 900
    p.held = 900
    p.done("/fixture/list/after.txt")
    same("a deep Enter reveals the renamed row and asks for its window",
         [refreshed, anchored(p).name, anchored(p).start, windowed], [["/fixture/list/after.txt"], "after.txt", 900, ["900,350"]])

    // A click-away commit keeps the pointer's row: no pendingSelect, anchor on that name, deep ones ask for their window.
    p = editing()
    p.renameKeepsPointerRow = true
    p.cursorIndex = 3
    p.cursorOn("clicked.txt")
    p.done("/fixture/list/after.txt")
    same("a click-away commit keeps the clicked row", [refreshed, anchored(p).name, anchored(p).select, windowed], [[""], "clicked.txt", true, []])
    p = editing()
    p.renameKeepsPointerRow = true
    p.cursorIndex = 900
    p.held = 900
    p.cursorOn("f1198.txt")
    p.done("/fixture/list/after.txt")
    same("a deep click-away asks for its old window too", [refreshed, anchored(p).name, anchored(p).start, windowed], [[""], "f1198.txt", 900, ["900,350"]])
    var kept = [["journal", "/fixture/list/after.txt"], ["rename-kept", "/fixture/list/before.txt"]]
    for (var k = 0; k < kept.length; k++) {
        p = editing()
        p.renameKeepsPointerRow = true
        p.cursorIndex = 3
        p.cursorOn("clicked.txt")
        p.fail(kept[k][0], kept[k][1], "permission denied")
        same("a pointer " + kept[k][0] + " keeps the click, never the destination", [refreshed, anchored(p).name], [[""], "clicked.txt"])
    }
    p = editing()
    p.renameKeepsPointerRow = true
    p.cursorIndex = 3
    p.cursorOn("clicked.txt")
    p.fail("rename", "/fixture/list/before.txt", "permission denied")
    same("a pointer refusal keeps the editor on the clicked row with no re-list",
         [p.renamePending, p.renamingIndex, refreshed.length, p.renameError], [false, 7, 0, "Permission denied."])

    // The replies and refusals that end the request without a moved cursor.
    p = editing()
    p.fail("journal", "/fixture/list/before.txt", "file or folder not found")
    same("a source-side refusal keeps the editor open with the plain cause",
         [p.renamePending, p.renamingIndex, p.renameError, refreshed.length], [false, 7, "File or folder not found.", 0])
    Ops.commitRename(p, "retry.txt")
    same("and the retry sends a second request", [p.renamePending, p.sent.length, p.renameRequest.destination], [true, 2, "/fixture/list/retry.txt"])
    p = editing()
    p.fail("journal", "/fixture/list/after.txt", "permission denied")
    same("a destination-side journal failure re-reads with the new name selected",
         [p.renamePending, p.renamingIndex, refreshed, messages], [false, -1, ["/fixture/list/after.txt"], ["Renamed, but Undo was not recorded: permission denied.|true"]])
    p = editing()
    p.fail("rename-kept", "/fixture/list/before.txt", "permission denied")
    same("a kept twin re-reads selecting nothing", [p.renamePending, p.renamingIndex, refreshed, messages],
         [false, -1, [""], [Errors.sentence("rename-kept", "permission denied") + "|true"]])
    var inputs = ["", "/fixture/list/after.txt", "/fixture/list/after.txt/child"]
    for (var q = 0; q < inputs.length; q++) {
        p = editing()
        p.fail("rename", inputs[q], "permission denied")
        same("a refusal naming the request closes it on the editor: " + inputs[q], [p.renamePending, p.renamingIndex, p.renameError], [false, 7, "Permission denied."])
    }
    var wheres = ["rename", "journal", "rename-kept"]
    for (var w = 0; w < wheres.length; w++) {
        p = editing()
        p.fail(wheres[w], "/fixture/unrelated", "permission denied")
        same("a failure for another path leaves the request open: " + wheres[w], [p.renamePending, p.renamingIndex, p.renameError], [true, 7, ""])
    }
    p = editing()
    p.done("/fixture/unrelated")
    same("a reply for another path leaves it open", [p.renamePending, p.renamingIndex, refreshed.length], [true, 7, 0])
    p = editing()
    p.path = "/fixture/another-directory"
    p.renamingIndex = -1
    same("a navigation during the write leaves the request pending", [p.renamePending, p.renameSource, p.renameError], [true, "", ""])
    p.done("/fixture/list/after.txt")
    same("and its late reply re-lists nothing in the new directory", [p.renamePending, p.renamingIndex, refreshed.length], [false, -1, 0])
    p = editing()
    p.path = "/fixture/another-directory"
    p.renamingIndex = -1
    Ops.startRename(p, 99)
    same("and a Rename started while it is pending is refused with no second request", [p.renamingIndex, p.sent.length], [-1, 1])
    var dead = ["backend", "read"]
    for (var d = 0; d < dead.length; d++) {
        p = editing()
        p.fail(dead[d], "", "the backend stopped")
        same("a " + dead[d] + " failure ends the request without a verdict", [p.renamePending, p.renamingIndex, messages],
             [false, -1, ["Backend stopped; rename outcome unknown.|true"]])
        same("and leaves the listing in the error state with no rows: " + dead[d], [p.listingState, p.total], ["error", 0])
    }
    p = editing()
    p.searchMode = "results"
    p.done("/fixture/list/after.txt")
    same("a reply during a search marks the listing stale instead of re-reading", [p.renamePending, refreshed.length, p.wire.stale], [false, 0, true])
}
