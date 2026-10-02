//@ pragma ShellId flea-touchpad-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Scroll.js" as Scroll

// tp1: fake wheel objects with an injected clock into the real FastScrollHandler on a real
// ui/List.qml over 3000 rows. Stroke travel is the gained pixel sum, the tail travels the closed
// form and ends, each stop lands at once, the scrollbar lane shares the tail, and a tail adds no
// objects. tests/touchpad.sh drives it offscreen.
ShellRoot {
    id: root

    property var failures: []
    property int rowCount: 3000
    property double fakeT: 1000
    property int livePolls: 0
    property double liveLiftY: 0
    property var liveSamples: []
    property double liveEndT: 0
    // Real-frame wait for the view fixup to carry a held overscroll home, in milliseconds.
    property int fixupWaitMs: 500
    property var fixupArgs: null

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
    }

    Component.onCompleted: {
        root.stubPane.visibleRows = Qt.binding(function () { return Math.max(1, Math.ceil(list.height / Flea.Theme.fileRowHeight)) })
        root.stubPane.listArea = list
    }

    Timer { interval: 800; running: true; repeat: false; onTriggered: root.beginStroke() }
    Timer { id: liveTimer; interval: 50; repeat: true; onTriggered: root.pollLive() }
    // The view's own release fixup runs on real frames, so the held-overscroll pin waits for it.
    Timer { id: fixupWait; interval: root.fixupWaitMs; repeat: false; onTriggered: root.checkFixupRested() }

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

    function notchWheel() {
        return { pixelDelta: { x: 0, y: 0 }, angleDelta: { x: 0, y: -120 },
            phase: 0, modifiers: 0, accepted: false }
    }

    function tailActive() {
        var found = Scroll.tailState(list, false)
        return found !== null && found.active
    }

    function freeze() {
        var h = handlers()
        if (h.body) { h.body.tailRunning = false; h.body.returnRunning = false }
        if (h.lane) { h.lane.tailRunning = false; h.lane.returnRunning = false }
    }

    // One flick through a handler; returns the mirrored gained samples and the End time.
    function feedStroke(handler, rawDeltas, dtMs) {
        var mirror = []
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
        var press = { accepted: true }
        h.body.handlePress(press)
        if (press.accepted !== false) {
            fail("press was consumed instead of reaching the row")
            root.report()
            return
        }
        if (!root.stoppedAtOnce("a press")) { root.report(); return }

        fed = root.startFrozenFlick(flickRaw(12, -40))
        if (fed === null) { root.report(); return }
        h.body.handleWheel(touchWheel(0, 1))
        if (!root.stoppedAtOnce("a new Begin")) { root.report(); return }

        fed = root.startFrozenFlick(flickRaw(12, -40))
        if (fed === null) { root.report(); return }
        var before = list.contentY
        h.body.handleWheel(notchWheel())
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

    // Qt delivers an unaccepted wheel to the next handler, so the lane runs first.
    function propagateToBody(ev) {
        var h = handlers()
        h.lane.handleWheel(ev)
        if (!ev.accepted)
            h.body.handleWheel(ev)
        return ev
    }
    // One flick delivered the way Qt propagates it: lane first, body only if unaccepted.
    function feedPropagated(rawDeltas, dtMs) {
        var mirror = []
        propagateToBody(touchWheel(0, 1))
        for (var i = 0; i < rawDeltas.length; i++) {
            root.fakeT += dtMs
            Scroll.testNowMs = root.fakeT
            mirror.push({ t: root.fakeT, x: 0, y: rawDeltas[i] * Scroll.TOUCH_GAIN })
            propagateToBody(touchWheel(rawDeltas[i], 2))
        }
        root.fakeT += dtMs
        Scroll.testNowMs = root.fakeT
        propagateToBody(touchWheel(0, 3))
        return { samples: mirror, endT: root.fakeT }
    }
    // The lift End reaches two handlers on one view; the flick must still coast.
    function propagatedFlick(liftObjs, liftDelegates, liftY, liftGot) {
        var h = handlers()
        list.contentY = 0
        root.fakeT += 1000
        Scroll.testNowMs = root.fakeT
        var fed = root.feedPropagated(flickRaw(12, -40), 8)
        if (!root.tailActive()) {
            fail("a propagated End started no tail")
            root.report()
            return
        }
        var v = Scroll.liftVelocity(fed.samples, fed.endT)
        var wantTail = Scroll.tailTotal(v.vy)
        var at = list.contentY
        var guard = 0
        while (root.tailActive() && guard < 10000) {
            h.body.advanceTail(16.7)
            guard += 1
        }
        var got = list.contentY - at
        if (Math.abs(got - wantTail) > 1) {
            fail("a propagated tail travelled " + got.toFixed(2) + ", want " + wantTail.toFixed(2))
            root.report()
            return
        }
        root.edgeTop(liftObjs, liftDelegates, liftY, liftGot)
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
        root.propagatedFlick(liftObjs, liftDelegates, liftY, got)
    }

    function returnActive() {
        var found = Scroll.tailState(list, false)
        return found !== null && found.retActive
    }

    // Elastic edges on the real List: resisted peaks within 1 px, tails overshoot and return,
    // no extra objects while past the bound, and a press stops the return where its row was picked.
    function edgeTop(liftObjs, liftDelegates, liftY, liftGot) {
        var h = handlers()
        list.contentY = 0
        root.fakeT += 1000
        Scroll.testNowMs = root.fakeT
        feedStroke(h.body, flickRaw(12, 3), 8)
        root.freeze()
        var want = Scroll.overResist(12 * 3 * Scroll.TOUCH_GAIN, list.height)
        var peak = list.contentY
        if (Math.abs(peak + want) > 1) {
            fail("top edge peaked " + peak.toFixed(2) + ", want " + (-want).toFixed(2))
            root.report()
            return
        }
        if (!root.returnActive()) {
            fail("top edge started no return")
            root.report()
            return
        }
        if (countUnder(list) !== liftObjs || list.contentItem.children.length !== liftDelegates) {
            fail("overscroll built objects past a plain stroke")
            root.report()
            return
        }
        var guard = 0
        while (root.returnActive() && guard < 10000) { h.body.advanceReturn(16.7); guard += 1 }
        if (Math.abs(list.contentY) > 1) {
            fail("top edge rested " + list.contentY.toFixed(2) + ", want 0")
            root.report()
            return
        }
        root.edgeBottom(liftObjs, liftDelegates, liftY, liftGot, peak)
    }

    function edgeBottom(liftObjs, liftDelegates, liftY, liftGot, topPeak) {
        var h = handlers()
        var lim = Scroll.limitsY(list)
        list.contentY = lim.max
        root.fakeT += 1000
        Scroll.testNowMs = root.fakeT
        feedStroke(h.body, flickRaw(12, -3), 8)
        root.freeze()
        var want = Scroll.overResist(12 * 3 * Scroll.TOUCH_GAIN, list.height)
        var peak = list.contentY
        if (Math.abs(peak - (lim.max + want)) > 1) {
            fail("bottom edge peaked " + peak.toFixed(2) + ", want " + (lim.max + want).toFixed(2))
            root.report()
            return
        }
        if (!root.returnActive()) {
            fail("bottom edge started no return")
            root.report()
            return
        }
        var guard = 0
        while (root.returnActive() && guard < 10000) { h.body.advanceReturn(16.7); guard += 1 }
        if (Math.abs(list.contentY - lim.max) > 1) {
            fail("bottom edge rested " + list.contentY.toFixed(2) + ", want " + lim.max.toFixed(2))
            root.report()
            return
        }
        root.tailEdge(liftObjs, liftDelegates, liftY, liftGot, topPeak, peak, lim.max)
    }

    function tailEdge(liftObjs, liftDelegates, liftY, liftGot, topPeak, bottomPeak, maxY) {
        var h = handlers()
        list.contentY = Math.max(0, maxY - 1500)
        root.fakeT += 1000
        Scroll.testNowMs = root.fakeT
        feedStroke(h.body, flickRaw(12, -40), 8)
        root.freeze()
        if (!root.tailActive() && !root.returnActive()) {
            fail("tail edge started neither tail nor return")
            root.report()
            return
        }
        var peak = list.contentY
        var guard = 0
        while (root.tailActive() && guard < 10000) {
            h.body.advanceTail(16.7)
            guard += 1
            if (list.contentY > peak)
                peak = list.contentY
        }
        guard = 0
        while (root.returnActive() && guard < 10000) { h.body.advanceReturn(16.7); guard += 1 }
        if (!(peak > maxY && peak < maxY + list.height)) {
            fail("tail edge peaked " + peak.toFixed(2) + ", want past " + maxY.toFixed(2) + " under one viewport")
            root.report()
            return
        }
        if (Math.abs(list.contentY - maxY) > 1) {
            fail("tail edge rested " + list.contentY.toFixed(2) + ", want " + maxY.toFixed(2))
            root.report()
            return
        }
        root.pressReturn(topPeak, bottomPeak, peak, liftY, liftGot, liftObjs, liftDelegates)
    }

    function pressReturn(topPeak, bottomPeak, tailPeak, liftY, liftGot, liftObjs, liftDelegates) {
        var h = handlers()
        list.contentY = 0
        root.fakeT += 1000
        Scroll.testNowMs = root.fakeT
        feedStroke(h.body, flickRaw(12, 3), 8)
        root.freeze()
        if (!root.returnActive()) {
            fail("press case started no return")
            root.report()
            return
        }
        h.body.advanceReturn(50)
        h.body.advanceReturn(50)
        var held = list.contentY
        if (Math.abs(held) < 1) {
            fail("return already home before the press")
            root.report()
            return
        }
        var press = { accepted: true }
        h.body.handlePress(press)
        if (press.accepted !== false) {
            fail("press was consumed instead of reaching the row")
            root.report()
            return
        }
        if (root.returnActive() || root.tailActive()) {
            fail("a press left the return running")
            root.report()
            return
        }
        // The press stops the return where it is instead of snapping to the bound: the row
        // under the pointer is picked from this layout, so the tap still lands on it.
        if (Math.abs(list.contentY - held) > 0.01) {
            fail("a press snapped " + held.toFixed(2) + " to " + list.contentY.toFixed(2))
            root.report()
            return
        }
        var at = list.contentY
        if (h.body.advanceReturn(16.7) !== 0 || list.contentY !== at) {
            fail("a stopped return moved after the press")
            root.report()
            return
        }
        // The dead release settle stays gone: an unaccepted press takes no grab, so prod never reaches it.
        if (typeof h.body.handleRelease !== "undefined") {
            fail("the dead release settle is back")
            root.report()
            return
        }
        // The held overscroll settles through the view's own release fixup onto the bound.
        if (!h.body.overscrolled()) {
            fail("a press held nothing past the bound")
            root.report()
            return
        }
        list.returnToBounds()
        if (root.returnActive()) {
            fail("the view fixup left the handler return running")
            root.report()
            return
        }
        root.fixupArgs = { top: topPeak, bottom: bottomPeak, tail: tailPeak,
            liftY: liftY, liftGot: liftGot, objs: liftObjs, delegates: liftDelegates }
        fixupWait.start()
    }

    function checkFixupRested() {
        var a = root.fixupArgs
        if (root.returnActive()) {
            fail("the handler return restarted during the view fixup")
            root.report()
            return
        }
        if (Math.abs(list.contentY) > 1) {
            fail("the view fixup rested " + list.contentY.toFixed(2) + ", want the bound 0")
            root.report()
            return
        }
        console.log("TOUCHPAD PASS stroke=1200 lift=" + Math.round(root.liveLiftY)
            + " rest=" + Math.round(a.liftY + a.liftGot) + " tail=" + a.liftGot.toFixed(1)
            + " objs=" + a.objs + " delegates=" + a.delegates
            + " edgeTop=" + a.top.toFixed(1) + " edgeBottom=" + a.bottom.toFixed(1)
            + " tailPeak=" + a.tail.toFixed(1))
        console.log("TOUCHPAD EDGE PASS top=" + a.top.toFixed(1) + " bottom=" + a.bottom.toFixed(1)
            + " tailPeak=" + a.tail.toFixed(1) + " rest=bound")
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("TOUCHPAD FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
