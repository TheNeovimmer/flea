.import "../../ui/js/MenuRefresh.js" as MenuRefresh
.import "../../ui/js/RecentMode.js" as RecentMode
.import "../../ui/js/Search.js" as Search
.import "../../ui/js/Swap.js" as Swap
.import "sourcefixture.js" as Source

// Advloop permfocus r1: the flyout-close debt, the Undo stage and the search listing's Apply refresh.
var ORIGINAL_MODE = 0o100644
var APPLIED_MODE = 0o100600
var ROW_HEIGHT = 37
var CURSOR = 3
var MARKED = 1
var MARKS = "1,3"
var LISTING = 4

// A pressed flyout row, a provider change, then a close with no release: the debt must still be repaid.
function flyoutClose(check, body) {
    var source = Source.source("ui/ContextMenu.qml")
    var later = []
    var qt = {callLater: function (callback) { later.push(callback) }}
    var main = {count: 0, itemAt: function () { return null }}
    var flyout = {count: 1, itemAt: function () { return {pressed: true} }}
    var menu = {opened: true, forRail: false, forHeader: false, forLocked: false,
        refreshOwed: false, entries: [{action: "openWith", label: "Old"}], cursor: 0,
        openSubmenuRow: 0, submenuCursor: 0, submenuOpen: true,
        buildEntries: function () { return [{action: "openWith", label: "New"}] }}
    var refresh = new Function("root", "MenuRefresh", "menuRows", "subRows", "Qt", "scroll", body(source, "refreshProviderRows"))
    menu.refreshProviderRows = function () { refresh(menu, MenuRefresh, main, flyout, qt, {reveal: function () {}}) }
    menu.refreshProviderRows()
    check("pressed flyout holds provider debt", menu.refreshOwed, true)
    check("pressed flyout keeps original rows", menu.entries[0].label, "Old")
    var callback = source.split("\n").filter(function (line) { return line.indexOf("onSubmenuOpenChanged:") >= 0 })[0]
    var press = new Function("Qt", "menu", "pressed", body(Source.source("ui/js/MenuRefresh.js"), "pressChanged"))
    var refreshApi = {pressChanged: function (owner, pressed) { press(qt, owner, pressed) }}
    menu.openSubmenuRow = -1
    menu.submenuOpen = false
    if (callback) new Function("root", "MenuRefresh", callback.substring(callback.indexOf(":") + 1))(menu, refreshApi)
    check("flyout close schedules deferred debt check", later.length, 1)
    flyout.count = 0
    while (later.length > 0) later.shift()()
    check("flyout close without release refreshes provider rows", menu.entries[0].label, "New")
    check("flyout close clears provider debt", menu.refreshOwed, false)
}

// The real Undo stage of tests/permissions-focus.qml, run against a root where Apply's watch re-read has landed.
function undoGuard(check, body) {
    var selections = 0
    var failures = 0
    var sent = []
    var root = {stage: "refreshUndone", started: Date.now(), stageLimitMs: 5000,
        pane: {listInFlight: false, wire: {anchor: null, stale: false}, backend: {listRequests: 2, send: function (message) { sent.push(message) }}},
        beforeLists: 1, undoReplies: 0, beforeUndoReplies: 0, undoInspectSent: false,
        undoModes: [], expectedModes: ["0644", "0644"], undoPaths: ["/d/b", "/d/d"],
        undoInspectBase: 1000000, markedRows: [1, 3], refreshIndex: 0, refreshCases: [{}],
        check: function (name, actual, expected) { if (actual !== expected) failures += 1 },
        checkSelection: function () { selections += 1 }, finish: function () {}, next: function () {}}
    var stage = new Function("root", "with(root) " + body(Source.source("tests/permissions-focus.qml"), "runStage"))
    stage(root)
    check("Apply watch reread cannot stand in for Undo reply", sent.length + selections, 0)
    root.undoReplies = 1
    root.pane.wire.stale = true
    stage(root)
    check("Undo waits for the re-read it owes", sent.length, 0)
    root.pane.wire.stale = false
    stage(root)
    check("Undo reply asks both on-disk modes before selection", sent.filter(function (message) { return message.op === "inspect" }).length, root.markedRows.length)
    check("Undo waits for on-disk inspection replies", selections, 0)
    root.undoModes = ["0744", "0644"]
    stage(root)
    check("Undo with wrong disk mode fails its mode check", failures, 1)
    check("Undo with wrong disk mode cannot check selection", selections, 0)
    root.undoModes = root.expectedModes.slice()
    stage(root)
    check("Undo with reply and restored disk modes checks selection", selections, 1)
}

// A search listing with marks 1 and 3, the cursor on 3 and rows holding the old mode, as a settled walk leaves it.
function searchPane(pane, running) {
    var p = pane("list", false, false)
    p.searchMode = Search.RESULTS
    p.searchRunning = running
    p.backend.heldListing = LISTING
    p.rows.forEach(function (row) { row.p = ORIGINAL_MODE })
    return p
}

// The window reply lands through PaneSwap's own takeRows, so the swap's selection rule is the production one.
function landWindow(p, body, mode) {
    var take = new Function("root", "Swap", "RecentMode", "start", "items", "kinds", "listing", body(Source.source("ui/PaneSwap.qml"), "takeRows"))
    var swap = {pane: p, phase: Swap.idle(), rowsLanded: function () {}}
    take(swap, Swap, RecentMode, p.held, p.rows.map(function (row) { return {n: row.n, p: mode} }), [], LISTING)
}

// An Apply on a search listing re-stats the held window: no walk, no debt, and the rows show the new mode.
function searchRefresh(check, body, pane, apply) {
    for (var running = 0; running < 2; running++) {
        var p = searchPane(pane, running === 1)
        var label = running ? "running search" : "completed search"
        apply(p, "batch")
        check(label + " Apply asks only the held window", p.sent.join(","), "window 0")
        check(label + " Apply leaves no debt", p.wire.stale, false)
        check(label + " Apply starts no anchored re-read", p.wire.anchor, null)
        landWindow(p, body, APPLIED_MODE)
        check(label + " marked row shows the new mode", p.rowFor(MARKED).p, APPLIED_MODE)
        check(label + " cursor row shows the new mode", p.rowFor(CURSOR).p, APPLIED_MODE)
        check(label + " keeps marks", p.selectedIndices().join(","), MARKS)
        check(label + " keeps cursor", p.cursorIndex, CURSOR)
        check(label + " keeps scroll", p.listArea.contentY, ROW_HEIGHT)
        if (running === 1) {
            Search.ranked(p)
            check("running search rank re-asks the window at the finish", p.sent.join(","), "window 0,window 0")
        }
    }
}

function run(check, body, pane, apply) {
    flyoutClose(check, body)
    undoGuard(check, body)
    searchRefresh(check, body, pane, apply)
}
