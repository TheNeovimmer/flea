.import "../../ui/js/Anchor.js" as Anchor
.import "../../ui/js/Ops.js" as Ops
.import "../../ui/js/Swap.js" as Swap
.import "../../ui/js/Errors.js" as Errors
.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/Tabs.js" as Tabs
.import "xwwatch.js" as Fixture

var DEEP_START = 350
var DIRECTORY_COUNT = 500
var OUTSIDE_INDEX = 499
var RETRY_INDEX = 450
var RETRY_ID = 77
var ROW_HEIGHT = 37
var QML_INT_MAX = 2147483647

function wireSource() {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("../../ui/PaneWire.qml"), false)
    request.send()
    return request.responseText
}

// Sample source: function onLocated(message) { ... } ends at the Connections member's indentation.
function handler(source, name, indent, parameters) {
    var pattern = new RegExp("function " + name + "\\([^)]*\\) \\{([\\s\\S]*?)\\n" + indent + "\\}")
    var match = source.match(pattern)
    if (!match)
        throw new Error("PaneWire handler missing: " + name)
    return new Function(parameters || "root,pane,Anchor,Theme,Ops,message,Tabs", match[1])
}

function rows(p, names, held) {
    p.rows = names.map(function (name) { return { n: name } })
    p.held = held
    p.total = DIRECTORY_COUNT + 1
}

function deepPane() {
    var p = Fixture.staged(["deep-a", "deep-b", "deep-c"], DEEP_START + 1, [])
    p.held = DEEP_START
    p.total = DIRECTORY_COUNT
    p.selection.toggle(DEEP_START + 1)
    return p
}

function listCount(p) {
    return p.sent.filter(function (command) { return command === "list " + p.path }).length
}

function windowRefusal(check, source, reread, busy, theme) {
    var failed = handler(source, "onFailed", "        ",
                         "root,pane,Anchor,Theme,Ops,Swap,Errors,Nav,where,input,message,mode")
    var p = deepPane()
    var cursor = p.cursorIndex
    var notices = []
    p.message = function (text, error) { notices.push({ text: text, error: error }) }
    var wire = { pane: p, anchor: Anchor.watched(p), stale: true }
    rows(p, ["head-a", "head-b", "head-c"], 0)
    wire.anchor = Anchor.apply(p, wire.anchor)
    p.listInFlight = false
    var pending = wire.anchor
    var lists = listCount(p)
    check("F19 deep window starts with an unfinished anchor", !!pending, true)
    wire.watchBusy = busy(wire, p, Anchor)
    check("F19 deep window holds the owed reread", wire.watchBusy, true)
    reread(wire, p, Anchor, theme, Ops)
    check("F19 waiting for deep rows retains refresh debt", wire.stale, true)
    check("F19 waiting for deep rows sends no second list", listCount(p), lists)
    failed(wire, p, Anchor, theme, Ops, Swap, Errors, Nav, "window", "/other", "Other mount is not responding.", 0)
    check("F19 another directory's window refusal leaves the anchor", wire.anchor === pending, true)
    failed(wire, p, Anchor, theme, Ops, Swap, Errors, Nav, "stale", "/d", "Listing changed.", 0)
    check("F19 stale refusal leaves the anchor", wire.anchor === pending, true)
    p.path = "/away"
    failed(wire, p, Anchor, theme, Ops, Swap, Errors, Nav, "window", "/d", "Mount is not responding.", 0)
    check("F19 a window refusal after navigation leaves the old anchor", wire.anchor === pending, true)
    p.path = "/d"
    failed(wire, p, Anchor, theme, Ops, Swap, Errors, Nav, "window", "/d", "Mount is not responding.", 0)
    check("F19 refused deep window ends the anchor", wire.anchor, null)
    check("F19 refused deep window keeps the cursor's place", p.cursorIndex, cursor)
    check("F19 refused deep window keeps the error line", notices[notices.length - 1].text, "Mount is not responding.")
    check("F19 refused deep window keeps the error role", notices[notices.length - 1].error, true)
    wire.watchBusy = busy(wire, p, Anchor)
    check("F19 refused deep window releases watchBusy", wire.watchBusy, false)
    check("F19 refused deep window retains debt until reread", wire.stale, true)
    reread(wire, p, Anchor, theme, Ops)
    check("F19 refused deep window sends exactly one second list", listCount(p), lists + 1)
    check("F19 refused deep window pays refresh debt", wire.stale, false)
    check("F19 reread leaves the refusal line visible", notices[notices.length - 1].text, "Mount is not responding.")
    wire.watchBusy = busy(wire, p, Anchor)
    reread(wire, p, Anchor, theme, Ops)
    check("F19 an in-flight reread sends no third list", listCount(p), lists + 1)
}

function run(check) {
    var source = wireSource()
    var located = handler(source, "onLocated", "        ")
    var locateRetry = handler(source, "locateRetry", "    ")
    var reread = handler(source, "reread", "    ")
    // Sample binding: readonly property bool watchBusy: Anchor.busy(pane, root.anchor).
    var binding = source.match(/readonly property bool watchBusy: ([^\n]+)/)
    var busy = new Function("root", "pane", "Anchor", "return " + binding[1])
    var theme = { fileRowHeight: ROW_HEIGHT }
    var p = deepPane()
    p.selection.toggle(OUTSIDE_INDEX)
    p.menuSelectionIdentity = "new-listing"
    var commands = []
    var send = p.backend.send
    p.backend.send = function (command) {
        commands.push(command)
        send(command)
    }
    var wire = { pane: p, anchor: Anchor.watched(p), retryId: RETRY_ID,
                 retryPaths: ["/d/retry-file"], retryFolder: "/d", retryListing: "", retrySelectionText: "" }
    wire.anchor = Anchor.fillPaths(p, wire.anchor, ["/d/outside"])
    rows(p, ["head-a", "head-b", "head-c"], 0)
    wire.anchor = Anchor.apply(p, wire.anchor)
    p.listInFlight = false
    locateRetry(wire, p, Anchor, theme, Ops)
    rows(p, ["new-deep", "deep-a", "deep-b"], DEEP_START)
    wire.anchor = Anchor.apply(p, wire.anchor)
    var pending = wire.anchor
    var retry = commands[commands.length - 2]
    var own = commands[commands.length - 1]
    check("F10 retry locate precedes anchor locate", retry.transferId, RETRY_ID)
    check("F17 anchor locate meets its reserved ID floor", own.id >= Anchor.LOCATE_ID_FLOOR, true)
    check("F17 anchor locate exceeds QML's largest menu ID", own.id > QML_INT_MAX, true)
    located(wire, p, Anchor, theme, Ops, { directory: "/d", id: 0, transferId: RETRY_ID,
            ok: true, matches: [{ path: "/d/retry-file", index: RETRY_INDEX }] }, Tabs)
    check("F10 retry reply reaches its handler and clears retry bookkeeping", wire.retryId, 0)
    check("F10 retry reply reselects its file", p.selectedIndices().join(","), String(RETRY_INDEX))
    check("F10 retry reply leaves anchor locate pending", wire.anchor === pending, true)
    var wrong = Anchor.takeLocated(p, pending, { directory: "/d", id: own.id + 1,
            transferId: 0, ok: true, matches: [] })
    check("F10 same-directory reply with another request identity takes nothing", wrong.handled, false)
    located(wire, p, Anchor, theme, Ops, { directory: "/d", id: own.id, transferId: 0,
            ok: true, matches: [{ path: "/d/outside", index: OUTSIDE_INDEX + 1 }] }, Tabs)
    check("F10 anchor's own reply finishes the anchor", wire.anchor, null)
    check("F10 held and unheld marks survive beside retry selection", p.selectedIndices().join(","),
          [DEEP_START + 2, RETRY_INDEX, OUTSIDE_INDEX + 1].join(","))

    // Both pending schedules run the real reread handler after listInFlight clears.
    for (var schedule = 0; schedule < 2; schedule++) {
        p = deepPane()
        if (schedule === 0)
            p.selection.toggle(OUTSIDE_INDEX)
        wire = { pane: p, anchor: Anchor.watched(p), stale: true, watchBusy: false }
        if (schedule === 0)
            wire.anchor = Anchor.fillPaths(p, wire.anchor, ["/d/outside"])
        rows(p, ["head-a", "head-b", "head-c"], 0)
        wire.anchor = Anchor.apply(p, wire.anchor)
        if (schedule === 0) {
            rows(p, ["new-deep", "deep-a", "deep-b"], DEEP_START)
            wire.anchor = Anchor.apply(p, wire.anchor)
        }
        p.listInFlight = false
        pending = wire.anchor
        var sent = p.sent.length
        var label = schedule === 0 ? "F12 locate pending" : "F12 deep window pending"
        check(label + " starts with selection cleared by Nav", p.selectionCount(), 0)
        wire.watchBusy = busy(wire, p, Anchor)
        check(label + " holds the next watched reread", wire.watchBusy, true)
        reread(wire, p, Anchor, theme, Ops)
        check(label + " preserves the unfinished anchor", wire.anchor === pending, true)
        check(label + " retains refresh debt", wire.stale, true)
        check(label + " sends no second listing", p.sent.length, sent)
        if (schedule === 0) {
            wire.anchor = Anchor.takeLocated(p, wire.anchor, { directory: "/d", id: pending.locateId,
                    transferId: 0, ok: true, matches: [{ path: "/d/outside", index: OUTSIDE_INDEX + 1 }] }).anchor
        } else {
            rows(p, ["new-deep", "deep-a", "deep-b"], DEEP_START)
            wire.anchor = Anchor.apply(p, wire.anchor)
        }
        var expected = schedule === 0 ? [DEEP_START + 2, OUTSIDE_INDEX + 1].join(",") : String(DEEP_START + 2)
        check(label + " restores original file identities", p.selectedIndices().join(","), expected)
        p.listInFlight = false
        wire.watchBusy = busy(wire, p, Anchor)
        check(label + " releases the hold after completion", wire.watchBusy, false)
        reread(wire, p, Anchor, theme, Ops)
        check(label + " pays the retained refresh debt", wire.stale, false)
        check(label + " captures the restored marks on next reread", !!(wire.anchor && wire.anchor.hadMarks), true)
    }
    windowRefusal(check, source, reread, busy, theme)
}
