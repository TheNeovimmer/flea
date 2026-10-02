//@ pragma ShellId flea-touchpad-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Scroll.js" as Scroll

// Fake wheel objects with an injected clock into the real FastScrollHandler on a real ui/List.qml.
// Stroke, tail, stops, lane sharing and object cost; tests/touchpad.sh drives it offscreen.
ShellRoot {
    id: root

    property var failures: []
    property int rowCount: 3000
    property double fakeT: 1000
    property int livePolls: 0
    property double liveLiftY: 0
    property var liveSamples: []
    property double liveEndT: 0

    function buildRows() {
        var rows = []
        for (var i = 0; i < root.rowCount; i++) {
            var n = "item" + ("0000" + i).slice(-5) + ".txt"
            var photo = i % 5 === 0
            rows.push({ n: n, d: false, i: photo ? "image-x-generic" : "text-x-generic",
                p: 420, s: 13, m: 1758835200, t: photo, k: 0, v: 0 })
        }
        return rows
    }

    Component {
        id: backendStub
        QtObject {
            property int windowCalls: 0
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) { windowCalls += 1 }
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 3000
            property int total: 3000
            property int held: 0
            property int cursorIndex: 45
            property int renamingIndex: -1
            property string renameError: ""
            property bool renamePending: false
            property bool paneFocused: true
            property bool dualMode: false
            property var clipboard: ({ paths: [], moving: false })
            property var selected: ({})
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: []
            property string searchMode: ""
            property string searchQuery: ""
            property string recentMode: ""
            property string filterQuery: ""
            property var selectionBand: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
            property string listingState: "ready"
            property var statusBar: null
            property int visibleRows: 8
            property int cacheRows: 0
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return false }
            function commitRename(newName) {}
            function commitOpenRename() {}
            function selectOnly(index, context) {}
            function pressSlowClick() { slowClickPresses += 1 }
            function slowClickWasSole(index) { return false }
            function armSlowClick(index, modifiers, dragging, sole) {}
            function cancelSlowClick() {}
            property int slowClickPresses: 0
            function focusRequested() {}
            property string focusView: "list"
            property var listArea: null
        }
    }

    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubMenu: menuStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: root.buildRows() })

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 500
        color: Flea.Theme.color.background

        Flea.List {
            id: list
            width: 700
            height: 300
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            pane: root.stubPane
            menu: root.stubMenu
        }

        TestEvent { id: driver }
    }

    Component.onCompleted: {
        root.stubPane.visibleRows = Qt.binding(function () { return Math.max(1, Math.ceil(list.height / Flea.Theme.fileRowHeight)) })
        root.stubPane.listArea = list
    }

    Timer { interval: 800; running: true; repeat: false; onTriggered: root.beginStroke() }
    Timer { id: liveTimer; interval: 50; repeat: true; onTriggered: root.pollLive() }

    function fail(text) { root.failures.push(text) }

    function handlers() {
        var body = null, lane = null
        var kids = list.children
        for (var i = 0; i < kids.length; i++)
            if (kids[i] && kids[i].objectName === "fleaScroll" && kids[i] !== list.scrollBar)
                body = kids[i]
        var bar = list.scrollBar
        if (bar) {
            var inner = bar.children
            for (var j = 0; j < inner.length; j++)
                if (inner[j] && inner[j].objectName === "fleaScroll")
                    lane = inner[j]
        }
        return { body: body, lane: lane }
    }

    function touchWheel(py, phase) {
        return { pixelDelta: { x: 0, y: py }, angleDelta: { x: 0, y: 0 },
            phase: phase, modifiers: 0, accepted: false }
    }

    function tailActive() {
        var found = Scroll.tailState(list, false)
        return found !== null && found.active
    }

    function freeze() {
        var h = handlers()
        if (h.body) h.body.tailRunning = false
        if (h.lane) h.lane.tailRunning = false
    }

    // One flick through a handler; returns the mirrored gained samples and the End time.
    function feedStroke(handler, rawDeltas, dtMs) {
        var mirror = [{ t: root.fakeT, x: 0, y: 0 }]
        handler.handleWheel(touchWheel(0, 1))
        for (var i = 0; i < rawDeltas.length; i++) {
            root.fakeT += dtMs
            Scroll.testNowMs = root.fakeT
            mirror.push({ t: root.fakeT, x: 0, y: rawDeltas[i] * Scroll.TOUCH_GAIN })
            handler.handleWheel(touchWheel(rawDeltas[i], 2))
        }
        root.fakeT += dtMs
        Scroll.testNowMs = root.fakeT
        handler.handleWheel(touchWheel(0, 3))
        return { samples: mirror, endT: root.fakeT }
    }

    function countUnder(item) {
        var n = 0
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            n += 1
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
            var res = (o !== null && o.resources !== undefined) ? o.resources : []
            for (var j = 0; j < res.length; j++) stack.push(res[j])
        }
        return n - 1
    }

    function flickRaw(n, px) {
        var out = []
        for (var i = 0; i < n; i++) out.push(px)
        return out
    }

    // Stroke travel is the gained pixel sum; the live tail then runs on real frames.
    function beginStroke() {
        var h = handlers()
        if (!h.body || !h.lane) {
            fail("found no body or lane handler")
            root.report()
            return
        }
        if (Math.round(list.contentY) !== 0) {
            fail("starts at contentY " + Math.round(list.contentY) + ", want 0")
            root.report()
            return
        }
        root.fakeT = 1000
        Scroll.testNowMs = root.fakeT
        var fed = feedStroke(h.body, flickRaw(12, -3), 8)
        root.liveSamples = fed.samples
        root.liveEndT = fed.endT
        var want = 12 * 3 * Scroll.TOUCH_GAIN
        if (Math.abs(list.contentY - want) > 1) {
            fail("stroke travelled " + list.contentY.toFixed(2) + ", want " + want)
            root.report()
            return
        }
        if (!root.tailActive()) {
            fail("no tail after the lift")
            root.report()
            return
        }
        root.liveLiftY = list.contentY
        root.livePolls = 0
        liveTimer.start()
    }

    // The live tail travels the closed form within 1 px and ends on real frames.
    function pollLive() {
        root.livePolls += 1
        if (root.tailActive()) {
            if (root.livePolls > 60) {
                fail("live tail still runs after 3 s")
                root.report()
            }
            return
        }
        liveTimer.stop()
        var v = Scroll.liftVelocity(root.liveSamples, root.liveEndT)
        var want = Scroll.tailTotal(v.vy)
        var got = list.contentY - root.liveLiftY
        if (Math.abs(got - want) > 1) {
            fail("live tail travelled " + got.toFixed(2) + ", want " + want.toFixed(2))
            root.report()
            return
        }
        root.manualStops()
    }

    function startFrozenFlick(rawDeltas) {
        var h = handlers()
        list.contentY = 0
        root.fakeT += 1000
        Scroll.testNowMs = root.fakeT
        var fed = feedStroke(h.body, rawDeltas, 8)
        root.freeze()
        if (!root.tailActive()) {
            fail("no tail to stop")
            return null
        }
        return fed
    }

    function stoppedAtOnce(why) {
        if (root.tailActive()) {
            fail(why + " left the tail running")
            return false
        }
        var h = handlers()
        var at = list.contentY
        if (h.body.advanceTail(16.7) !== 0 || list.contentY !== at) {
            fail(why + " moved after the stop")
            return false
        }
        return true
    }

    // A press, a new Begin, a notch and an outside write each stop the tail at once.
    function manualStops() {
        var h = handlers()
        var fed = root.startFrozenFlick(flickRaw(12, -40))
        if (fed === null) { root.report(); return }
        var presses = root.stubPane.slowClickPresses
        driver.mousePress(list, 10, 10, Qt.LeftButton, Qt.NoModifier, 1)
        if (root.stubPane.slowClickPresses !== presses + 1) {
            fail("a press over a row never reached it")
            root.report()
            return
        }
        driver.mouseRelease(list, 10, 10, Qt.LeftButton, Qt.NoModifier, 1)
        if (!root.stoppedAtOnce("a press")) { root.report(); return }

        fed = root.startFrozenFlick(flickRaw(12, -40))
        if (fed === null) { root.report(); return }
        h.body.handleWheel(touchWheel(0, 1))
        if (!root.stoppedAtOnce("a new Begin")) { root.report(); return }

        fed = root.startFrozenFlick(flickRaw(12, -40))
        if (fed === null) { root.report(); return }
        var before = list.contentY
        driver.mouseWheel(list, 350, 10, Qt.NoButton, Qt.NoModifier, 0, -120, 1)
        if (!root.stoppedAtOnce("a notch")) { root.report(); return }
        if (Math.abs(list.contentY - before - 288) > 1) {
            fail("notch after momentum moved " + (list.contentY - before).toFixed(2) + ", want 288")
            root.report()
            return
        }

        fed = root.startFrozenFlick(flickRaw(12, -40))
        if (fed === null) { root.report(); return }
        list.showCursor(200, 0)
        if (!root.stoppedAtOnce("an outside write")) { root.report(); return }
        root.laneShares()
    }

    // The scrollbar lane feeds the same tail the body drains.
    function laneShares() {
        var h = handlers()
        list.contentY = 0
        root.fakeT += 1000
        Scroll.testNowMs = root.fakeT
        var fed = feedStroke(h.lane, flickRaw(12, -40), 8)
        root.freeze()
        var wantStroke = 12 * 40 * Scroll.TOUCH_GAIN
        if (Math.abs(list.contentY - wantStroke) > 1) {
            fail("lane stroke travelled " + list.contentY.toFixed(2) + ", want " + wantStroke)
            root.report()
            return
        }
        if (!root.tailActive()) {
            fail("lane stroke started no shared tail")
            root.report()
            return
        }
        var v = Scroll.liftVelocity(fed.samples, fed.endT)
        var wantTail = Scroll.tailTotal(v.vy)
        var liftY = list.contentY
        var liftObjs = countUnder(list)
        var liftDelegates = list.contentItem.children.length
        var midObjs = -1, midDelegates = -1, steps = 0
        var moved = 0, guard = 0
        while (root.tailActive() && guard < 10000) {
            moved += h.body.advanceTail(16.7)
            guard += 1
            steps += 1
            if (steps === 10) {
                midObjs = countUnder(list)
                midDelegates = list.contentItem.children.length
            }
        }
        var got = list.contentY - liftY
        if (Math.abs(got - wantTail) > 1) {
            fail("shared tail travelled " + got.toFixed(2) + ", want " + wantTail.toFixed(2))
            root.report()
            return
        }
        if (h.lane.advanceTail(16.7) !== 0) {
            fail("the lane kept stepping a drained tail")
            root.report()
            return
        }
        if (midObjs !== liftObjs) {
            fail("tail holds " + midObjs + " objects against " + liftObjs + " at lift")
            root.report()
            return
        }
        if (midDelegates !== liftDelegates) {
            fail("tail holds " + midDelegates + " delegates against " + liftDelegates + " at lift")
            root.report()
            return
        }
        console.log("TOUCHPAD PASS stroke=" + Math.round(liftY) + " lift=" + Math.round(liftY)
            + " rest=" + Math.round(liftY + got) + " tail=" + got.toFixed(1)
            + " objs=" + midObjs + " delegates=" + midDelegates)
        root.endStop()
    }

    // A flick into the last page ends the tail on the first frame that cannot move.
    function endStop() {
        var h = handlers()
        var maxY = list.contentHeight - list.height
        list.contentY = maxY - 400
        feedStroke(h.body, flickRaw(12, -40), 8)
        root.freeze()
        if (!root.tailActive()) {
            fail("no tail to end at the content edge")
            root.report()
            return
        }
        var guard = 0
        while (guard < 10000) {
            var before = list.contentY
            h.body.advanceTail(16.7)
            guard += 1
            if (list.contentY === before)
                break
        }
        if (Math.abs(list.contentY - maxY) > 1) {
            fail("tail ended at " + list.contentY.toFixed(2) + ", want the last page " + maxY.toFixed(2))
            root.report()
            return
        }
        if (root.tailActive()) {
            fail("tail still active on the first frame that could not move")
            root.report()
            return
        }
        root.angleFree()
    }

    // A sub-pixel touchpad frame carries pixels 0 with a nonzero angle and moves nothing.
    function angleFree() {
        var h = handlers()
        var before = list.contentY
        h.body.handleWheel({ pixelDelta: { x: 0, y: 0 }, angleDelta: { x: 0, y: -4 },
            phase: 2, modifiers: 0, accepted: false })
        if (list.contentY !== before) {
            fail("an angle-only touchpad frame moved the list")
            root.report()
            return
        }
        if (root.tailActive()) {
            fail("an angle-only touchpad frame started a tail")
            root.report()
            return
        }
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("TOUCHPAD FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
