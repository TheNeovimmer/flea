.import "tabsfixture.js" as Fixture
.import "../../ui/js/Tabs.js" as Tabs

function source(path) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Qt.resolvedUrl(path), false)
    xhr.send()
    return xhr.responseText
}

// Sample input: closing("a { b { c } d }", 2, "method x") answers 15, and closing('f { "{" }', 2, "method x") throws.
function closing(text, open, label) {
    var end = open + 1
    var depth = 1
    while (depth > 0 && end < text.length) {
        if (text[end] === "{") depth++
        else if (text[end] === "}") depth--
        end++
    }
    if (depth !== 0) throw new Error("unterminated shipped " + label)
    return end
}

// Sample input: "    function cancelOut() {\n        root.Drag.cancel()\n    }".
function method(text, name, root, Quickshell, ackTimer, sourceGeometry, strip, query, takenAck, tabDropDeadline) {
    var start = text.indexOf("function " + name + "(")
    if (start < 0) throw new Error("missing shipped method " + name)
    var end = closing(text, text.indexOf("{", start), "method " + name)
    return eval("(" + text.slice(start, end) + ")")
}

// Sample input: "onExited: Qt.callLater(root.restartLatest)" is a one-line hook, "onStreamFinished: {\n    root.x = 1\n}" a block hook.
function hook(text, name) {
    var start = text.indexOf(name + ":")
    if (start < 0) return null
    var body = start + name.length + 1
    var end = text.indexOf("\n", body)
    if (end < 0) end = text.length
    if (text.slice(body, end).trim().charAt(0) === "{") end = closing(text, text.indexOf("{", body), "hook " + name)
    return eval("(function (root, Qt, Quickshell, text) {" + text.slice(body, end) + "})")
}

function bar(pane, shell) {
    var root = { pane: pane, outToken: "", outIndex: -1, outPath: "", outPid: "111",
        outMime: {}, outActive: false, ownAccepted: false, ackLiftedAt: 0,
        dragFrom: -1, dropAt: -1, pendingTab: null, takenQueue: [], outstandingLifts: [],
        traceTab: function () {}, width: 500, height: 30, ackWaitMs: Tabs.ACK_WAIT_MS,
        acks: [], spawns: [], Drag: { cancel: function () {} } }
    var ackTimer = { stop: function () {}, restart: function () {} }
    var sourceGeometry = { begin: function () {} }
    var strip = { x: 0, mapToItem: function () { return { x: 0, y: 30 } } }
    var takenAck = { running: false }
    var Quickshell = shell || { processId: 111, env: function () { return "/stub/exits" },
        execDetached: function (argv) { root.spawns.push(argv); return false } }
    var text = source("../../ui/TabBar.qml")
    // Sample input: "readonly property int tabDropPeekFirst: 2".
    root.tabDropPeekFirst = eval(text.match(/readonly property int tabDropPeekFirst: ([^\n]+)/)[1])
    var tabDropDeadline = { stop: function () {}, restart: function () {} }
    var names = ["dragStarted", "dragFinished", "tabLiftBegan", "tabLiftEnded", "holdAck",
        "clearAck", "outFinished", "cancelOut", "returnAt", "tearOffAt", "acceptTabDrop",
        "onPeeked"]
    if (text.indexOf("function drainLifts(") >= 0) names.push("drainLifts")
    for (var i = 0; i < names.length; i++)
        root[names[i]] = method(text, names[i], root, Quickshell, ackTimer, sourceGeometry, strip, null, takenAck, tabDropDeadline)
    root.sendTaken = function (pid, token) { root.acks.push(token) }
    var ackRoot = { tabBar: root, view: { currentPane: pane }, tabs: Tabs, traceTab: function () {} }
    root.take = method(source("../../ui/boot/fleatab.qml"), "take", ackRoot)
    root.focus = function (pane) { ackRoot.view.currentPane = pane; root.pane = pane }
    return root
}

function pair(path) {
    var pane = Fixture.pane(path || "/tmp/duplicate")
    Tabs.openNew(pane)
    return pane
}

// The shipped exit and stream-finished hooks run as written; skip names one hook to leave out for a control.
function geometry(skip) {
    var root = { token: "", queryToken: "", queryDrained: true, rect: null, strip: null }
    var query = { running: false }
    var queued = []
    var later = { callLater: function (fn) { queued.push(fn) } }
    var shell = { processId: 111 }
    var text = source("../../ui/TabDragGeometry.qml")
    var hooks = { onExited: hook(text, "onExited"), onStreamFinished: hook(text, "onStreamFinished") }
    root.hooks = { onExited: hooks.onExited !== null, onStreamFinished: hooks.onStreamFinished !== null }
    root.begin = method(text, "begin", root, null, null, null, null, query)
    root.restartLatest = method(text, "restartLatest", root, null, null, null, null, query)
    function run(name, stdout) {
        if (hooks[name] && skip !== name) hooks[name](root, later, shell, stdout)
        while (queued.length > 0) queued.shift()()
    }
    root.exit = function () {
        query.running = false
        run("onExited", "")
    }
    root.stream = function (stdout) { run("onStreamFinished", stdout) }
    return root
}
