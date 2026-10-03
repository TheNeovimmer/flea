.import "../../ui/js/Anchor.js" as Anchor
.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/RecentMode.js" as RecentMode
.import "../../ui/js/Permissions.js" as Permissions
.import "../../ui/js/Ops.js" as Ops
.import "xwwatch.js" as Fixture
.import "sourcefixture.js" as Source

var CURSOR = 3
var MARKS = [1, 3]
var ROW_HEIGHT = 37
var DEEP_START = 350
var APPLY_ID = 7
var INSPECT_STRIDE = 1000

// Sample input: body("function f(x) { return x }", "f") returns the outer braces.
function body(source, name) {
    var marker = "function " + name + "("
    var at = source.indexOf(marker)
    if (at < 0) throw new Error("Missing function " + name)
    var start = source.indexOf("{", at), depth = 0
    for (var i = start; i < source.length; i++) {
        if (source[i] === "{") depth += 1
        if (source[i] === "}") depth -= 1
        if (depth === 0) return source.substring(start, i + 1)
    }
    throw new Error("Unclosed function " + name)
}

function pane(mode, recent, deferred) {
    var names = recent ? ["d/a", "elsewhere/b", "d/c", "other/d", "d/e"] : ["a", "b", "c", "d", "e"]
    var p = Fixture.staged(names, CURSOR, MARKS)
    p.viewMode = mode
    p.recentMode = recent ? "results" : ""
    p.recentFrom = "/d"
    p.recentPaths = names.map(function(name) { return "/" + name })
    p.recentVisits = {}
    p.anchorRowHeight = ROW_HEIGHT
    p.listArea.contentY = ROW_HEIGHT
    p.listArea.columns = 2
    p.listArea.cellHeightPx = ROW_HEIGHT * 2
    p.sticky = function () {}
    p.wire = {anchor: null, stale: false}
    Object.defineProperty(p.wire, "watchBusy", {get: function () { return Anchor.busy(p, p.wire.anchor) }})
    var reread = new Function("root", "pane", "Anchor", "Theme", body(Source.source("ui/PaneWire.qml"), "reread"))
    p.wire.reread = function () { reread(p.wire, p, Anchor, {fileRowHeight: ROW_HEIGHT}) }
    var refresh = new Function("root", "Nav", "RecentMode", "selectPath", "keepSelection", body(Source.source("ui/Pane.qml"), "refresh"))
    p.refresh = function (selectPath, keepSelection) { refresh(p, Nav, RecentMode, selectPath, keepSelection) }
    p.backend.listPaths = function (paths) { p.sent.push("listpaths:" + paths.join(",")) }
    if (recent) {
        p.path = "/"
        if (deferred) p.sidebar = {waiting: false, readRecent: function () { p.sidebar.waiting = true }}
    }
    return p
}

function land(p, names, held) {
    p.rows = names.map(function(name) { return {n: name} })
    p.held = held || 0
    p.total = Math.max(p.total, p.held + names.length)
    p.wire.anchor = Anchor.apply(p, p.wire.anchor, ROW_HEIGHT)
    p.listInFlight = false
}

// The real WindowBody callback receives the real dialog handler's success or partial refusal.
function apply(p, kind) {
    var source = Source.source("ui/WindowBody.qml")
    var changed = new Function("permissionsDialog", "bar", "note", body(source, "onChanged"))
    var needed = new Function("permissionsDialog", body(source, "onRefreshNeeded"))
    var card = {opened: true, transportFailed: false, requestId: APPLY_ID, busy: true, facts: {ok: true},
        multiPaths: ["/d/b", "/d/d"], multiBase: APPLY_ID, inspectStride: INSPECT_STRIDE,
        applyingMany: true, multiApplySent: MARKS.length, multiApplySkipped: [], errorText: "",
        cancelFocus: {forceActiveFocus: function () {}}, requested: function () {}, close: function () { card.opened = false }}
    card.changed = function (note) { changed({owner: p}, {say: function () {}}, note) }
    card.refreshNeeded = function () { needed({owner: p}) }
    card.isMulti = kind !== "single"
    var dialogSource = Source.source("ui/PermissionsDialog.qml")
    var receiveMany = new Function("root", "Permissions", "message", "with(root) " + body(dialogSource, "receiveMany"))
    card.receiveMany = function (message) { receiveMany(card, Permissions, message) }
    if (kind === "single") {
        var receive = new Function("root", "message", "with(root) " + body(dialogSource, "receive"))
        receive(card, {id: APPLY_ID, op: "apply", ok: true})
    } else receiveMany(card, Permissions, {id: APPLY_ID, op: "applyMany", ok: kind !== "partial", error: "One file refused."})
}

function undo(p, op, redo) {
    var handler = new Function("pane", "Ops", "Status", "op", "ok", body(Source.source("ui/PaneWire.qml"), redo ? "onRedone" : "onUndone"))
    handler(p, Ops, {UNDO_HINT: ""}, op, true)
}

function run(check) {
    var modes = ["list", "grid", "columns", "dual"]
    var kinds = ["single", "batch", "partial", "undo", "redo"]
    for (var m = 0; m < modes.length; m++) {
        for (var k = 0; k < kinds.length; k++) {
            var p = pane(modes[m], false, false)
            if (kinds[k] === "single") p.selection.only(CURSOR)
            var marks = p.selectedIndices().join(","), cursor = p.cursorIndex, y = p.listArea.contentY
            if (kinds[k] === "undo" || kinds[k] === "redo") undo(p, "permissions", kinds[k] === "redo")
            else apply(p, kinds[k])
            land(p, ["a", "b", "c", "d", "e"])
            var label = modes[m] + " " + kinds[k]
            check(label + " reread keeps marks", p.selectedIndices().join(","), marks)
            check(label + " reread keeps cursor", p.cursorIndex, cursor)
            check(label + " reread keeps viewport", p.listArea.contentY, y)
        }
    }
    for (var deferred = 0; deferred < 2; deferred++) {
        var recent = pane("list", true, deferred === 1)
        apply(recent, "batch")
        if (recent.sidebar && recent.sidebar.waiting) RecentMode.run(recent, recent.recentPaths, recent.recentVisits)
        land(recent, ["d/a", "elsewhere/b", "d/c", "other/d", "d/e"])
        check("Recent " + deferred + " Apply keeps marks", recent.selectedIndices().join(","), MARKS.join(","))
        check("Recent " + deferred + " Apply keeps cursor", recent.cursorIndex, CURSOR)
        check("Recent " + deferred + " uses history path", recent.sent[0].indexOf("listpaths:"), 0)
    }
    var ordinary = pane("list", false, false)
    undo(ordinary, "copy", false)
    check("unrelated Undo keeps ordinary refresh", ordinary.selectedIndices().length, 0)
    var busy = pane("list", false, false)
    busy.renamingIndex = CURSOR
    apply(busy, "batch")
    check("row interaction holds permissions reread", busy.sent.length, 0)
    check("held permissions reread retains debt", busy.wire.stale, true)
    busy.renamingIndex = -1
    busy.wire.reread()
    land(busy, ["a", "b", "c", "d", "e"])
    check("deferred permissions reread keeps marks", busy.selectedIndices().join(","), MARKS.join(","))
    var deep = pane("list", true, true)
    deep.held = DEEP_START
    deep.total = DEEP_START + deep.rows.length
    deep.cursorIndex = DEEP_START + CURSOR
    deep.selection.clear()
    deep.selection.toggle(DEEP_START + 1)
    deep.selection.toggle(1)
    apply(deep, "batch")
    var paths = deep.wire.anchor ? Anchor.fillPaths(deep, deep.wire.anchor, ["/d/unheld"]) : null
    deep.wire.anchor = paths
    check("Recent paths resolve keeps complete row name", paths ? paths.marks[0].name : "missing", "d/unheld")
    check("Recent waits for history before window", deep.sent.some(function(command) { return command.indexOf("window ") === 0 }), false)
    if (deep.sidebar && deep.sidebar.waiting) RecentMode.run(deep, deep.recentPaths, deep.recentVisits)
    check("Recent asks deep window after listpaths", deep.sent[deep.sent.length - 1], "window " + DEEP_START)
}
