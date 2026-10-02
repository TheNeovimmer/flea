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
        window: function (start) { p.sent.push("window " + start) },
        send: function (o) { p.sent.push(o.c + ":" + (o.rows ? o.rows.join(",") : o.paths ? o.paths.length + "p" : "")) },
        askPaths: function (r) { p.sent.push("paths:" + r.join(",")) }
    }
    p.join = function (b, n) { return b === "/" ? "/" + n : b + "/" + n }
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
function landed(p, names, held, total) {
    var anchor = Anchor.watched(p)
    if (anchor && anchor.needPaths) {
        var need = anchor.needPaths
        var list = need.map(function (idx) { var r = p.rowFor(idx); return r ? "/d/" + r.n : "" })
        anchor = Anchor.fillPaths(p, anchor, list)
    }
    p.held = held
    p.rows = names.map(function (n) { return { n: n } })
    p.total = total === undefined ? names.length : total
    var standing = Anchor.apply(p, anchor)
    if (standing && standing.locateSent && !standing.locateDone) {
        var matches = []
        for (var i = 0; i < (standing.locatePaths || []).length; i++) {
            var leaf = String(standing.locatePaths[i]).substring(3)
            for (var r = 0; r < p.rows.length; r++) {
                if (p.rows[r].n === leaf) { matches.push({ path: standing.locatePaths[i], index: p.held + r }); break }
            }
        }
        standing = Anchor.fillLocated(p, standing, matches)
    }
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

    // An unheld mark resolves through the paths round trip, so it goes rather than re-pointing at another file.
    var beyond = staged(["a", "b"], 0, [0])
    beyond.selection.toggle(9)
    landed(beyond, ["NEW", "a", "b"], 0)
    check("an unheld mark goes instead of landing on another file",
          beyond.selectedIndices().join(","), "1")

    // No resolver holds the re-read while an unheld mark stands: a backend answering neither send nor askPaths.
    var bare = pane()
    delete bare.backend.send
    delete bare.backend.askPaths
    bare.rows = [{ n: "a" }, { n: "b" }]
    bare.total = 2
    bare.selection.toggle(9)
    check("with no resolver an unheld mark holds the re-read", Anchor.busy(bare), true)
    var resolving = pane()
    resolving.rows = [{ n: "a" }, { n: "b" }]
    resolving.total = 2
    resolving.selection.toggle(9)
    check("with a resolver it holds nothing back", Anchor.busy(resolving), false)

    // F1: every paths asker is tagged, so a reply reaches only the asker that sent it.
    var taggedAnchor = { needPaths: [1], marks: [{ index: 1, name: null }] }
    var foreign = pane()
    foreign.pathsPending = { kind: "drag" }
    check("a drag paths reply never fills the anchor", Anchor.takesPaths(foreign, taggedAnchor), false)
    var owned = pane()
    owned.pathsPending = { kind: "anchor" }
    check("the anchor takes only its own tagged reply", Anchor.takesPaths(owned, taggedAnchor), true)
    check("an untagged reply takes nothing", Anchor.takesPaths(pane(), taggedAnchor), false)
    var otherAsk = pane()
    otherAsk.pathsPending = { kind: "compress" }
    check("another asker's paths request holds the re-read", Anchor.busy(otherAsk), true)
    var clipAsk = pane()
    clipAsk.clipPending = true
    check("a clipboard resolve in flight holds the re-read", Anchor.busy(clipAsk), true)

    // The cursor's file is gone past the new total, so the cursor lands clamped at once and the locate answer keeps it there.
    var gone = staged(["a", "b", "c"], 2, [1, 2])
    var goneAnchor = Anchor.watched(gone)
    gone.held = 0
    gone.rows = [{ n: "a" }, { n: "b" }]
    gone.total = 2
    var goneStanding = Anchor.apply(gone, goneAnchor)
    check("a gone cursor file waits on its marks with the anchor standing", goneStanding === goneAnchor, true)
    check("landed on the clamped old index", gone.cursorSetTo, 1)
    var goneEnd = Anchor.fillLocated(gone, goneStanding, [])
    check("the locate answer keeps the clamped cursor", goneEnd + "|" + gone.cursorSetTo, "null|1")
    check("and the surviving mark follows its file", gone.selectedIndices().join(","), "1")

    // F3: a failed anchor paths ask ends the anchor instead of stranding it.
    // A settled listing holds its rows across the re-list, so the failed anchor still lands on them.
    var failed = staged(["a", "b"], 0, [0])
    failed.selection.toggle(9)
    failed.swap = { hold: function () { return true } }
    var failedAnchor = Anchor.watched(failed)
    check("an unheld mark waits on its paths reply", !!failedAnchor.needPaths, true)
    check("a failed paths reply ends the anchor", Anchor.failAnchor(failed, failedAnchor), null)
    check("a failed paths reply still lists the changed directory", failed.sent.join(","), "paths:9,list /d,fsinfo")
    check("on the clamped index", failed.cursorSetTo, 0)
    check("and releases the paths claim", failed.pathsPending, null)
    var throwing = pane()
    throwing.rows = [{ n: "a" }]
    throwing.total = 1
    throwing.selection.toggle(5)
    throwing.backend.send = function () { throw new Error("dead backend") }
    throwing.backend.askPaths = function () { throw new Error("dead backend") }
    var thrownAnchor = Anchor.watched(throwing)
    check("a throwing paths send still lists", throwing.sent.join(","), "list /d,fsinfo")
    check("and leaves no paths claim behind", thrownAnchor && !thrownAnchor.needPaths && !throwing.pathsPending, true)
    var locatedPane = staged(["a", "b"], 0, [])
    var locatedAnchor = Anchor.watched(locatedPane)
    locatedAnchor.locateSent = true
    var wrong = Anchor.takeLocated(locatedPane, locatedAnchor, { directory: "/other", matches: [] })
    check("a locate reply for another directory keeps the anchor standing",
          wrong.handled === false && wrong.anchor === locatedAnchor, true)
    var refused = Anchor.takeLocated(locatedPane, locatedAnchor, { directory: "/d", ok: false, matches: [] })
    check("a refused locate ends the anchor", refused.handled === true && refused.anchor === null, true)

    // F18: a navigation while the anchor waits for its paths reply drops the anchor.
    var moved = staged(["a", "b"], 0, [0])
    moved.selection.toggle(9)
    var movedAnchor = Anchor.watched(moved)
    moved.path = "/new"
    check("a navigation during the paths wait drops the anchor", Anchor.fillPaths(moved, movedAnchor, [""]), null)
    check("and lists nothing for the folder just opened", moved.sent.join(","), "paths:9")

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
