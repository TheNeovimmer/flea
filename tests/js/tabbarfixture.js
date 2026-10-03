.import "tabsfixture.js" as Fixture
.import "../../ui/js/Tabs.js" as Tabs

function source(path) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Qt.resolvedUrl(path), false)
    xhr.send()
    return xhr.responseText
}

// Sample input: "    function cancelOut() {\n        root.Drag.cancel()\n    }".
function method(text, name, root, Quickshell, ackTimer, sourceGeometry, strip, query, takenAck, tabDropDeadline) {
    var start = text.indexOf("function " + name + "(")
    if (start < 0) throw new Error("missing shipped method " + name)
    var end = text.indexOf("{", start) + 1
    var depth = 1
    while (depth > 0) {
        if (text[end] === "{") depth++
        else if (text[end] === "}") depth--
        end++
    }
    return eval("(" + text.slice(start, end) + ")")
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

function geometry() {
    var root = { token: "", queryToken: "", queryDrained: true, rect: null, strip: null }
    var query = { running: false }
    var text = source("../../ui/TabDragGeometry.qml")
    root.begin = method(text, "begin", root, null, null, null, null, query)
    root.finish = function () {
        query.running = false
        root.queryDrained = true
        if (text.indexOf("function restartLatest(") >= 0)
            method(text, "restartLatest", root, null, null, null, null, query)()
    }
    return root
}
