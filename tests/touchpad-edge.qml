//@ pragma ShellId flea-touchpad-edge-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Scroll.js" as Scroll
import "flea/js/Filter.js" as Filter

// tp2-r2: elastic-edge review findings on the real ui/List.qml over 3000 rows, offscreen.
// Fake wheel objects into the real FastScrollHandler, the way tests/touchpad.qml does; real
// ListView delivery, real frames, real cursor clamp. tests/touchpad-edge.sh drives it.
ShellRoot {
    id: root

    property var failures: []
    property int rowCount: 3000
    property double fakeT: 1000
    // Real-frame wait for the view fixup to carry a held overscroll home, in milliseconds.
    property int fixupWaitMs: 500
    property int pressCase: 0
    property real pressShown: 0
    property int pressWant: 0
    // Both held-overscroll pins: a deep stroke and a shallow one, each with its tap height.
    property var pressCases: [{ updates: 8, py: 24, y: 300 }, { updates: 2, py: 12, y: 100 }]

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
        list.cursorClamped.connect(function (first, last) { Filter.clampCursor(root.stubPane, first, last) })
    }

    Timer { interval: 800; running: true; repeat: false; onTriggered: root.checkReturn() }
    // The view's own release fixup runs on real frames, so the held-overscroll pin waits for it.
    Timer { id: fixupWait; interval: root.fixupWaitMs; repeat: false; onTriggered: root.checkPressRested() }

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

    function touchWheelXY(px, py, phase) {
        return { pixelDelta: { x: px, y: py }, angleDelta: { x: 0, y: 0 },
            phase: phase, modifiers: 0, accepted: false }
    }

    function reset() {
        var h = handlers()
        if (h.body) { h.body.stopTail(); h.body.stopReturn(true) }
        if (h.lane) { h.lane.stopTail(); h.lane.stopReturn(true) }
        Scroll.tailState(list, true).samples = []
        list.contentX = 0
        list.contentY = 0
        root.fakeT += 1000
        Scroll.testNowMs = root.fakeT
    }

    function freeze() {
        var h = handlers()
        if (h.body) { h.body.tailRunning = false; h.body.returnRunning = false }
        if (h.lane) { h.lane.tailRunning = false; h.lane.returnRunning = false }
    }

    function returnActive() {
        var found = Scroll.tailState(list, false)
        return found !== null && found.retActive
    }

    function tailActive() {
        var found = Scroll.tailState(list, false)
        return found !== null && found.active
    }

    function strokeTop(handler, updates, py) {
        handler.handleWheel(touchWheelXY(0, 0, 1))
        for (var i = 0; i < updates; i++) {
            root.fakeT += 8
            Scroll.testNowMs = root.fakeT
            handler.handleWheel(touchWheelXY(0, py, 2))
        }
        root.fakeT += 8
        Scroll.testNowMs = root.fakeT
        var end = touchWheelXY(0, 0, 3)
        handler.handleWheel(end)
        return end
    }

    function settleReturn(handler) {
        var frames = 0
        while (root.returnActive() && frames < 10000) { handler.advanceReturn(16.7); frames += 1 }
        return frames
    }

    // Finding 1: the lift's own End is accepted when overscrolled, so the view's own wheel
    // handler never snaps to the bound in the same delivery and the return plays its frames.
    function checkReturn() {
        var h = handlers()
        if (!h.body) { fail("found no body handler"); root.checkCursor(); return }
        root.reset()
        var end = root.strokeTop(h.body, 8, 24)
        var peak = list.contentY
        if (peak > -1) { fail("stroke never overscrolled, peak " + peak.toFixed(1)); root.checkCursor(); return }
        if (end.accepted !== true) {
            fail("lift End left unaccepted while overscrolled at " + peak.toFixed(1))
            // The scene contract: an unaccepted End reaches the view, which snaps to the
            // bound in the same delivery (Flickable.returnToBounds) and stops our return.
            list.contentY = 0
        } else if (Math.abs(list.contentY - peak) > 0.01) {
            fail("accepted End moved the content in its own delivery")
        }
        root.freeze()
        var frames = 0
        var last = Math.abs(list.contentY)
        var backed = false
        while (root.returnActive() && frames < 10000) {
            h.body.advanceReturn(16.7)
            frames += 1
            var now = Math.abs(list.contentY)
            if (now > last + 0.01)
                backed = true
            last = now
        }
        if (end.accepted === true) {
            if (frames < 5 || frames > 25)
                fail("return played " + frames + " frames, want a ~200 ms OutCubic")
            if (backed)
                fail("return moved away from its bound mid-flight")
            if (Math.abs(list.contentY) > 1)
                fail("return rested " + list.contentY.toFixed(2) + ", want the bound 0")
        } else if (frames !== 0 || Math.abs(list.contentY) > 1) {
            fail("unaccepted End still animated")
        }
        console.log("EDGE return peak=" + peak.toFixed(1) + " accepted=" + end.accepted + " frames=" + frames)
        root.checkCursor()
    }

    // Finding 4: a bounce never moves the list cursor; the clamp reads the bounded view.
    function checkCursor() {
        var h = handlers()
        root.reset()
        root.stubPane.cursorIndex = 15
        h.body.handleWheel(touchWheelXY(0, 0, 1))
        root.fakeT += 8
        Scroll.testNowMs = root.fakeT
        h.body.handleWheel(touchWheelXY(0, 1, 2))
        var peak = list.contentY
        root.fakeT += 8
        Scroll.testNowMs = root.fakeT
        h.body.handleWheel(touchWheelXY(0, 0, 3))
        root.freeze()
        root.settleReturn(h.body)
        if (Math.abs(peak + Scroll.overResist(2.5, list.height)) > 1)
            fail("small bounce peaked " + peak.toFixed(2))
        if (root.stubPane.cursorIndex !== 15)
            fail("a 1.37 px bounce moved the cursor 15 to " + root.stubPane.cursorIndex)
        root.reset()
        root.stubPane.cursorIndex = 12
        var end = root.strokeTop(h.body, 8, 24)
        peak = list.contentY
        root.freeze()
        root.settleReturn(h.body)
        if (Math.abs(peak + Scroll.overResist(480, list.height)) > 1.5)
            fail("large bounce peaked " + peak.toFixed(2))
        if (root.stubPane.cursorIndex !== 12)
            fail("a 140 px bounce moved the cursor 12 to " + root.stubPane.cursorIndex)
        console.log("EDGE cursor peak=" + peak.toFixed(1) + " cursor=" + root.stubPane.cursorIndex)
        // F5: a sub-row move and back pulls an offscreen cursor in; the range dedupe never did.
        root.reset()
        root.stubPane.cursorIndex = 15
        var rowH = Flea.Theme.fileRowHeight
        list.contentY = rowH * 0.4
        var wantLast = Math.min(root.stubPane.shownTotal - 1, root.stubPane.visibleRows - 1)
        if (root.stubPane.cursorIndex !== wantLast)
            fail("a sub-row move left the cursor 15 offscreen, want " + wantLast)
        root.checkPress()
    }

    // Finding 5: a press during a return stops it where the pointer picked its row, never snapping.
    function checkPress() {
        root.pressCase = 0
        root.pressOne()
    }

    function pressAdvance() {
        root.pressCase += 1
        if (root.pressCase >= root.pressCases.length)
            root.checkTailPeak()
        else
            root.pressOne()
    }

    function pressOne() {
        var h = handlers()
        var cases = root.pressCases
        var c = root.pressCase
        root.reset()
        root.strokeTop(h.body, cases[c].updates, cases[c].py)
        var shown = -list.contentY
        root.pressShown = shown
        root.freeze()
        if (!root.returnActive()) {
            fail("press case " + c + " started no return")
            root.pressAdvance()
            return
        }
        var rowH = Flea.Theme.fileRowHeight
        var want = Math.floor((list.contentY + cases[c].y - list.originY) / rowH)
        root.pressWant = want
        var press = { accepted: true }
        h.body.handlePress(press)
        if (press.accepted !== false) {
            fail("press case " + c + " was consumed instead of reaching the row")
            root.pressAdvance()
            return
        }
        if (root.returnActive() || root.tailActive()) {
            fail("press case " + c + " left the return running")
            root.pressAdvance()
            return
        }
        // No snap: the layout the pointer picked from is still the layout on screen.
        if (Math.abs(list.contentY + shown) > 0.01) {
            fail("press case " + c + " snapped " + shown.toFixed(1) + " to " + (-list.contentY).toFixed(1))
            root.pressAdvance()
            return
        }
        var tapped = list.indexAt(100, list.contentY + cases[c].y)
        if (tapped !== want) {
            fail("press case " + c + " picked row " + tapped + ", want the row under the pointer " + want)
            root.pressAdvance()
            return
        }
        // The dead release settle stays gone: an unaccepted press takes no grab, so prod never reaches it.
        if (typeof h.body.handleRelease !== "undefined") {
            fail("press case " + c + " still carries the dead release settle")
            root.pressAdvance()
            return
        }
        // The held overscroll settles through the view's own release fixup onto the bound.
        if (!h.body.overscrolled()) {
            fail("press case " + c + " held nothing past the bound")
            root.pressAdvance()
            return
        }
        list.returnToBounds()
        if (root.returnActive()) {
            fail("press case " + c + " left the handler return running past the view fixup")
            root.pressAdvance()
            return
        }
        fixupWait.start()
    }

    function checkPressRested() {
        var c = root.pressCase
        if (root.returnActive()) {
            fail("press case " + c + " restarted the handler return during the view fixup")
            root.pressAdvance()
            return
        }
        if (Math.abs(list.contentY) > 1) {
            fail("press case " + c + " rested " + list.contentY.toFixed(2) + ", want the bound 0")
            root.pressAdvance()
            return
        }
        console.log("EDGE press overscroll=" + root.pressShown.toFixed(1) + " row=" + root.pressWant)
        root.pressAdvance()
    }

    // Finding 6: a momentum tail past the bound integrates frame by frame with the stroke's
    // own resistance and a hard brake: no frame jumps, the peak stays under a quarter viewport.
    function checkTailPeak() {
        var h = handlers()
        root.reset()
        // The last page in the old spelling, so this check runs on the old tree too.
        var limMax = Math.max(list.originY, list.originY + list.contentHeight - list.height)
        list.contentY = limMax - 1500
        var st = Scroll.tailState(list, true)
        st.vy = -6
        st.vx = 0
        st.active = true
        st.samples = []
        st.lastY = list.contentY
        h.body.tailRunning = false
        var prev = list.contentY
        var maxIn = 0, maxPast = 0, peak = list.contentY, frames = 0
        while (st.active && frames < 10000) {
            h.body.advanceTail(16.7)
            frames += 1
            var step = Math.abs(list.contentY - prev)
            if (prev <= limMax + 0.01) {
                if (step > maxIn)
                    maxIn = step
            } else if (step > maxPast) {
                maxPast = step
            }
            prev = list.contentY
            if (list.contentY > peak)
                peak = list.contentY
        }
        var past = peak - limMax
        if (past <= 5)
            fail("tail never reached the edge, peak past end " + past.toFixed(1))
        if (maxPast > maxIn + 0.5)
            fail("a past-bound frame stepped " + maxPast.toFixed(1) + " past in-bound " + maxIn.toFixed(1))
        if (past >= 0.25 * list.height)
            fail("tail peaked " + past.toFixed(1) + " past the end in a " + list.height + " view")
        root.freeze()
        root.settleReturn(h.body)
        if (Math.abs(list.contentY - limMax) > 1)
            fail("tail rested " + (list.contentY - limMax).toFixed(2) + " past the end")
        console.log("EDGE tail maxIn=" + maxIn.toFixed(1) + " maxPast=" + maxPast.toFixed(1)
            + " peakPast=" + past.toFixed(1) + " viewport=" + list.height)
        root.report()
    }

    function report() {
        if (root.failures.length === 0)
            console.log("TOUCHPAD_EDGE PASS return cursor press tailpeak")
        for (var f = 0; f < root.failures.length; f++)
            console.log("TOUCHPAD_EDGE FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
