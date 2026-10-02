.import "../../ui/js/Menu.js" as Menu
.import "../../ui/js/Ops.js" as Ops
.import "sourcefixture.js" as Source

function executable(check, state, entry, actions) {
    // A logical row can land before its delegate; Paste as still needs the row's snapshot.
    var entrance = Source.slice(Source.source("ui/Pane.qml"), "function openPasteAs()", "function invertSelection")
    var openPasteAs = eval("(function(root, menu) {" + entrance + "\nopenPasteAs();})")
    var opened = "", p = {cursorRow: {n: "canary.txt"},
        openCursorMenu: function() { return false },
        listSlot: {width: 40, height: 40, mapToItem: function() { return Qt.point(20, 20) }}}
    var menu = {clipboardAvailable: true, openAt: function() { opened = "row" },
        openBackground: function() { opened = "background" }, openSubmenuFor: function() {}}
    openPasteAs(p, menu)
    check("hunt: Paste as snapshots a logical row before its delegate lands", opened, "row")
    p.cursorRow = null
    openPasteAs(p, menu)
    check("hunt: empty Paste as uses the background inventory", opened, "background")
    // Both approved boards require a cursor-row script without any execute bit.
    check("Make executable shows on a script missing its bit",
        entry(Menu.listingEntries(state({ hiddenActions: [], rowMode: 0o100644, hasShebang: true, cursorIsTarget: true })), "makeExecutable").action, "makeExecutable")
    check("and wears the play mark no neighbour wears",
        entry(Menu.listingEntries(state({ hiddenActions: [], rowMode: 0o100644, hasShebang: true, cursorIsTarget: true })), "makeExecutable").glyph, "play")
    check("without a shebang it is absent",
        entry(Menu.listingEntries(state({ hiddenActions: [], rowMode: 0o100644, cursorIsTarget: true })), "makeExecutable").action, undefined)
    check("with the execute bit already set it is absent too",
        entry(Menu.listingEntries(state({ hiddenActions: [], rowMode: 0o100744, hasShebang: true, cursorIsTarget: true })), "makeExecutable").action, undefined)
    // Both approved boards require no execute bit, rather than just no owner execute bit.
    check("hunt: Make executable is absent with group execute already set",
        entry(Menu.listingEntries(state({ hiddenActions: [], rowMode: 0o100654, hasShebang: true, cursorIsTarget: true })), "makeExecutable").action, undefined)
    check("hunt: Make executable is absent with everyone execute already set",
        entry(Menu.listingEntries(state({ hiddenActions: [], rowMode: 0o100645, hasShebang: true, cursorIsTarget: true })), "makeExecutable").action, undefined)
    check("on a directory it is absent",
        entry(Menu.listingEntries(state({ hiddenActions: [], rowMode: 0o040755, hasShebang: true, cursorIsTarget: true })), "makeExecutable").action, undefined)
    check("on a multi-selection it is absent",
        entry(Menu.listingEntries(state({ hiddenActions: [], rowMode: 0o100644, selectionCount: 2, hasShebang: true, cursorIsTarget: true })), "makeExecutable").action, undefined)
    check("on a single selection that is not the cursor row it is absent",
        entry(Menu.listingEntries(state({ hiddenActions: [], rowMode: 0o100644, hasShebang: true, cursorIsTarget: false })), "makeExecutable").action, undefined)
    check("and the Menus switch takes it away like any other row",
        entry(Menu.listingEntries(state({ hiddenActions: ["makeExecutable"], rowMode: 0o100644, hasShebang: true, cursorIsTarget: true })), "makeExecutable").action, undefined)
    check("it sits where hidden Permissions would sit before it",
        actions(Menu.listingEntries(state({ hiddenActions: [], rowMode: 0o100644, hasShebang: true, cursorIsTarget: true, selectionModes: [0o100644] }))).indexOf("permissions,makeExecutable") >= 0, true)
}

function clipboard(check, pathsPane) {
    var cutSent = []
    var cutPane = pathsPane(cutSent)
    cutPane.pathsPending = { kind: "drag" }
    Ops.clip(cutPane, true)
    check("a cut refuses out loud while a drag claim is waiting",
          cutSent.length + "|" + String(cutPane.clipPending) + "|" + JSON.stringify(cutPane.said),
          "0|null|[[\"Still resolving the last selection; try again.\",false]]")
    // An overlapping Cut cannot rewrite the outstanding Copy verb.
    var overlapSent = []
    var overlapPane = pathsPane(overlapSent)
    var overlapAt = 0
    overlapPane.selectedIndices = function () { return [overlapAt] }
    Ops.clip(overlapPane, false)
    overlapAt = 1
    Ops.clip(overlapPane, true)
    check("hunt: pending Copy refuses a second Cut", overlapSent.length, 1)
    Ops.pathsResolved(overlapPane, ["/d/f0"])
    check("hunt: previous Copy never becomes a Cut of the previous selection",
          overlapPane.clipboard.moving, false)
    Ops.paste(overlapPane)
    check("hunt: Paste never moves the earlier Copy after a later Cut",
          JSON.stringify(overlapPane.asked[0]),
          JSON.stringify({ c: "transfer", op: "copy", paths: ["/d/f0"], dest: "/d" }))
    check("hunt: deferred Cut asks for its own selection", JSON.stringify(overlapSent[1]),
          JSON.stringify({ c: "paths", rows: [1] }))
    Ops.pathsResolved(overlapPane, ["/d/f1"])
    check("hunt: later Cut wins the whole clipboard", JSON.stringify(overlapPane.clipboard),
          JSON.stringify({ paths: ["/d/f1"], moving: true }))
    Ops.paste(overlapPane)
    check("hunt: Paste moves only the later Cut selection", JSON.stringify(overlapPane.asked[1]),
          JSON.stringify({ c: "transfer", op: "move", paths: ["/d/f1"], dest: "/d" }))
    var latestSent = [], latest = pathsPane(latestSent), at = 0
    latest.selectedIndices = function () { return [at] }
    Ops.clip(latest, false)
    at = 1
    Ops.clip(latest, true)
    at = 2
    Ops.clip(latest, false)
    Ops.pathsResolved(latest, ["/d/f0"])
    check("hunt: only the latest deferred selection resolves", JSON.stringify(latestSent[1].rows), "[2]")
    Ops.pathsResolved(latest, ["/d/f2"])
    check("hunt: deferred Copy retains its own verb", JSON.stringify(latest.clipboard),
          JSON.stringify({ paths: ["/d/f2"], moving: false }))
    var direct = pathsPane([])
    Ops.clip(direct, false)
    Ops.clip(direct, true, ["/d/menu-choice"])
    Ops.pathsResolved(direct, ["/d/old-copy"])
    check("hunt: old paths cannot replace a newer resolved menu choice", JSON.stringify(direct.clipboard),
          JSON.stringify({ paths: ["/d/menu-choice"], moving: true }))
    var staleSent = [], stale = pathsPane(staleSent)
    stale.backend.heldListing = 1
    Ops.clip(stale, false)
    Ops.clip(stale, true)
    stale.backend.heldListing = 2
    Ops.pathsResolved(stale, ["/d/f0"])
    check("hunt: deferred row numbers cannot follow a re-list", staleSent.length, 1)
    check("hunt: stale deferred selection leaves the earlier Copy intact", stale.clipboard.moving, false)
}
