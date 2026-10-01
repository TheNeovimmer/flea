.import "../../ui/js/Anchor.js" as Anchor
.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/Selection.js" as Selection

// xw5: another window's change shows at once with the marks kept on the same files. The watched
// re-read no longer waits for a bare selection; it carries the marks across by file identity and
// the cursor back by name, with no scroll. Its own suite because tests/js/watch.js sits at the
// 300-line hard cap, and because this is one behaviour rather than another navigation.

function pane() {
    var p = {
        listInFlight: false,
        listedSeen: true,
        path: "/d",
        total: 0,
        held: 0,
        rows: [],
        kindNames: [],
        thumbState: "stale",
        dirSizeState: "stale",
        cursorIndex: 0,
        renamingIndex: -1,
        renamePending: false,
        menuVisible: false,
        menuActions: { opened: false, pendingAction: "", pendingActivation: false },
        filterTyping: false,
        filterQuery: "",
        searchMode: "",
        selectionBand: null,
        collide: { pending: null },
        windowSize: 350,
        selection: Selection.create(),
        selectionVersion: 0,
        selectionAnchor: 0,
        cursorSetTo: -1,
        cursorCtx: -2,
        clipboard: { paths: ["/d/a.txt"], moving: true },
        sent: []
    }
    p.selectionCount = function () { return p.selection.count() }
    p.selectedIndices = function () { return p.selection.indices() }
    p.clearSelection = function () { p.selection.clear(); p.selectionVersion += 1 }
    p.setCursor = function (index, context) { p.cursorIndex = index; p.cursorSetTo = index; p.cursorCtx = context }
    p.selectOnly = function (index) { p.selection.only(index); p.selectionVersion += 1; p.cursorIndex = index; p.cursorSetTo = index }
    p.rowFor = function (index) {
        var offset = index - p.held
        return offset < 0 || offset >= p.rows.length ? null : p.rows[offset]
    }
    p.message = function () {}
    p.swap = { hold: function () { return false } }
    p.listArea = { primeSettle: function () {} }
    p.backend = {
        list: function (path) { p.sent.push("list " + path) },
        askFsInfo: function () { p.sent.push("fsinfo") },
        window: function (start) { p.sent.push("window " + start) }
    }
    // The same wrapper ui/Pane.qml carries, so the re-read takes the one route that can refuse.
    p.openWithoutHistory = function (target, options) { Nav.openWithoutHistory(p, target, options) }
    return p
}

// A pane holding names with the cursor and the marks placed, as a settled listing would.
function staged(names, cursor, selected) {
    var p = pane()
    p.rows = names.map(function (n) { return { n: n } })
    p.total = names.length
    p.cursorIndex = cursor
    for (var i = 0; i < selected.length; i++)
        p.selection.toggle(selected[i])
    return p
}

// The re-read's own request, then one rows reply carrying names at held with total.
function landed(p, names, held, total, renames) {
    var anchor = Anchor.watched(p, renames)
    p.held = held
    p.rows = names.map(function (n) { return { n: n } })
    p.total = total === undefined ? names.length : total
    var standing = Anchor.apply(p, anchor)
    return { anchor: anchor, standing: standing }
}

function run(check) {
    // A bare selection is not a reason to hold: xw5 applies the change at once instead.
    var rest = pane()
    check("a pane at rest holds no watched re-read back", Anchor.busy(rest), false)
    rest.selection.toggle(1)
    rest.selection.toggle(2)
    rest.selection.toggle(3)
    check("a selection of three holds nothing back", Anchor.busy(rest), false)

    // Every hold that stays, and what interaction each one protects.
    var held = pane()
    held.renamingIndex = 2
    check("an open rename editor holds the re-read", Anchor.busy(held), true)
    held.renamingIndex = -1
    held.renamePending = true
    check("a rename commit in flight holds the re-read", Anchor.busy(held), true)
    held.renamePending = false
    held.menuVisible = true
    check("an open menu holds the re-read", Anchor.busy(held), true)
    held.menuVisible = false
    held.menuActions.opened = true
    check("an opened menu action holds the re-read", Anchor.busy(held), true)
    held.menuActions.opened = false
    held.menuActions.pendingAction = "rename"
    check("a menu action waiting on its reply holds the re-read", Anchor.busy(held), true)
    held.menuActions.pendingAction = ""
    held.menuActions.pendingActivation = true
    check("a menu activation waiting holds the re-read", Anchor.busy(held), true)
    held.menuActions.pendingActivation = false
    held.filterTyping = true
    check("a filter line being typed holds the re-read", Anchor.busy(held), true)
    held.filterTyping = false
    held.searchMode = "results"
    check("a search walk holds the re-read", Anchor.busy(held), true)
    held.searchMode = ""
    held.selectionBand = {}
    check("a rubber-band drag holds the re-read", Anchor.busy(held), true)
    held.selectionBand = null
    held.collide.pending = {}
    check("a transfer waiting on the collision card holds the re-read", Anchor.busy(held), true)
    held.collide.pending = null
    held.listInFlight = true
    check("a listing already in flight holds the re-read", Anchor.busy(held), true)

    // An insert above: the cursor follows its file down, the marks follow theirs, the held window
    // is asked for again with no scroll, and the copy mark rides on its path untouched.
    var insert = staged(["a", "b", "c"], 1, [1, 2])
    var moved = landed(insert, ["NEW", "a", "b", "c"], 0)
    check("an insert above re-reads the same directory", insert.sent.join(","), "list /d,fsinfo")
    check("the cursor lands on its file at its new index", insert.cursorSetTo, 2)
    check("and lands with no scroll, so the viewport does not jump", insert.cursorCtx, 0)
    check("the marks stay on the same files, never by row index",
          insert.selectedIndices().join(","), "2,3")
    check("and the path-keyed copy mark survives the re-read",
          insert.clipboard.paths.join(","), "/d/a.txt")

    // A delete of a marked file: its mark goes and the rest stay on their files.
    var deleted = staged(["a", "b", "c"], 2, [0, 2])
    landed(deleted, ["b", "c"], 0)
    check("a deleted mark goes while the cursor stays on its file", deleted.cursorSetTo, 1)
    check("and the surviving mark follows its file", deleted.selectedIndices().join(","), "1")

    // A rename of the cursor file with no pair is a delete plus a create: the cursor falls back
    // to the clamped old index and the mark goes.
    var renamed = staged(["a", "b"], 0, [0])
    landed(renamed, ["a2", "b"], 0)
    check("a renamed cursor file falls back to its old index", renamed.cursorSetTo, 0)
    check("and its mark goes", renamed.selectionCount(), 0)

    // A rename of a marked file with no pair drops that mark and keeps the cursor's.
    var marked = staged(["a", "b", "c"], 2, [0])
    landed(marked, ["a2", "b", "c"], 0)
    check("a renamed mark goes while the cursor stays on its file", marked.cursorSetTo, 2)
    check("and the selection is empty rather than re-pointed", marked.selectionCount(), 0)

    // Only a rename pair the watcher reported keeps identity across the new name. The live
    // changed line carries no pair, so the arms above are the live behaviour; these pin the pair.
    var paired = staged(["a", "b", "c"], 2, [0])
    landed(paired, ["a2", "b", "c"], 0, undefined, { "a": "a2" })
    check("a paired rename keeps the mark on the new name", paired.selectedIndices().join(","), "0")
    check("while the cursor stays on its own file", paired.cursorSetTo, 2)
    var pairedCursor = staged(["a", "b"], 0, [0])
    landed(pairedCursor, ["a2", "b"], 0, undefined, { "a": "a2" })
    check("a paired rename of the cursor file follows it", pairedCursor.cursorSetTo, 0)
    check("and keeps its mark with it", pairedCursor.selectedIndices().join(","), "0")

    // Under a filter the same identity rules run over listing rows: a new matching file appears in
    // the set while the marks and the cursor follow theirs.
    var filtered = staged(["a1", "a2", "b1"], 0, [0, 1])
    filtered.filterQuery = "a"
    var kept = landed(filtered, ["a0", "a1", "a2", "b1"], 0)
    check("the filter query survives the re-read", filtered.filterQuery, "a")
    check("the cursor follows its file within the filtered set", filtered.cursorSetTo, 1)
    check("the marks follow theirs", filtered.selectedIndices().join(","), "1,2")
    check("a watched re-read with a filter still only moves marks, never the query",
          kept.standing, null)

    // A mark on a row the pane does not hold has no name to record, so it goes rather than
    // re-pointing at another file when the rows land.
    var beyond = staged(["a", "b"], 0, [0])
    beyond.selection.toggle(9)
    landed(beyond, ["NEW", "a", "b"], 0)
    check("an unheld mark goes instead of landing on another file",
          beyond.selectedIndices().join(","), "1")

    // A cursor deep in a large directory: the first window cannot hold its name, so the anchor
    // stands, sweeping whatever marks that window holds, until the asked window arrives.
    var deep = staged(["m", "n"], 4001, [4000])
    deep.held = 4000
    deep.total = 100000
    var deepAnchor = Anchor.watched(deep)
    check("a deep re-read asks for its window again, so the viewport does not jump",
          deep.sent.join(","), "list /d,fsinfo,window 4000")
    deep.held = 0
    deep.rows = [{ n: "a" }, { n: "b" }]
    deep.total = 100000
    check("the first window does not resolve a deep anchor",
          Anchor.apply(deep, deepAnchor) === deepAnchor, true)
    check("and moves no cursor while it waits", deep.cursorSetTo, -1)
    deep.held = 4000
    deep.rows = [{ n: "NEW" }, { n: "m" }, { n: "n" }]
    check("the asked window puts the cursor back on its file",
          Anchor.apply(deep, deepAnchor) + "|" + deep.cursorSetTo, "null|4002")
    check("with no scroll", deep.cursorCtx, 0)
    check("and the swept mark lands on its file too",
          deep.selectedIndices().join(","), "4001")
}
