//@ pragma ShellId flea-rowscroll-test

import QtQuick
import Quickshell
import "flea" as Flea

// Rowscroll: a real ui/List.qml over a counting stub pane, scrolled by ten wheel notches, counts what the rows that enter the view cost.
ShellRoot {
    id: root

    readonly property int rowTotal: 400
    readonly property int notches: 10
    readonly property int sweeps: 3
    // Measured the same on 0.3.7 ae9419c8 and 0.3.8 9e7090cc: 22 objects a row, 12 rows at rest plus 17 built by the first sweep, 222 rowFor reads a sweep.
    readonly property int objectsPerRowMax: 22
    readonly property int objectsPerRowMin: 22
    readonly property int builtAtRestMin: 12
    readonly property int builtMin: 29
    readonly property int builtMax: 29
    readonly property int rowForPerSweepMin: 222
    readonly property int rowForPerSweepMax: 222
    // The settle timer is one debounce, so a sweep sends at most one thumb ask, one cancel and one size ask.
    readonly property int settleAsksMax: 1
    property var failures: []
    // Plain fields of one object notify nothing, so a counting call inside a binding never loops it.
    property var tally: ({ rowFor: 0, isSelected: 0, window: 0, thumb: 0, thumbcancel: 0, dirsize: 0, other: 0 })
    property var seen: []

    property var sampleRows: {
        var out = []
        for (var i = 0; i < root.rowTotal; i++)
            out.push({ n: "f" + i + ".txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
        return out
    }

    Component {
        id: backendStub
        QtObject {
            function peek(path, size, hidden) { root.tally.other += 1 }
            function thumb(rows, cacheOnly) { root.tally.thumb += 1 }
            function thumbcancel(rows) { root.tally.thumbcancel += 1 }
            function dirsize(rows) { root.tally.dirsize += 1 }
            function dirsizecancel() { root.tally.other += 1 }
            function window(start, count) { root.tally.window += 1 }
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: root.rowTotal
            property int total: root.rowTotal
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property bool paneFocused: true
            property bool dualMode: false
            property var clipboard: ({ paths: [], moving: false })
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
            property int visibleRows: 8
            property int cacheRows: 4
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { root.tally.rowFor += 1; var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { root.tally.isSelected += 1; return false }
            function commitRename(newName) {}
            function pressSlowClick() {}
            function slowClickWasSole(index) { return false }
            function cancelSlowClick() {}
            function armSlowClick(index, modifiers, dragging, sole) {}
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
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: root.sampleRows })

    Flea.List {
        id: list
        width: 700
        height: 300
        pane: root.stubPane
        menu: menuStub.createObject(root)
    }

    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.begin()
    }

    // Past a named timer's interval by this much, so the timer has fired before the next step reads or writes.
    readonly property int timerMarginMs: 20
    readonly property int coalesceWaitMs: root.stubPane.coalesceMs + root.timerMarginMs
    readonly property int settleWaitMs: Math.max(root.stubPane.settleMs, root.stubPane.firstSettleMs) + root.timerMarginMs

    // One notch as the wheel delivers it: 120 units of angleDelta, no pixel delta, no phase, no modifier.
    function wheelNotch() {
        return { angleDelta: { x: 0, y: -120 }, pixelDelta: { x: 0, y: 0 }, modifiers: 0, phase: Qt.NoScrollPhase, accepted: false }
    }

    // The list's own FastScrollHandler, the item a wheel event reaches, found by its object name.
    function wheelHandler() {
        for (var i = 0; i < list.children.length; i++) {
            var c = list.children[i]
            if (c && c.objectName === "fleaScroll" && c.handleWheel !== undefined)
                return c
        }
        return null
    }

    // Delegates ever built: a row object seen once is one build, however often it is re-bound after.
    function noteDelegates() {
        var kids = list.contentItem.children
        for (var i = 0; i < kids.length; i++) {
            var k = kids[i]
            if (k && k.listingIndex !== undefined && root.seen.indexOf(k) < 0)
                root.seen.push(k)
        }
    }

    // Children and resources under every live delegate, recursively.
    function objectsUnder(item) {
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

    function liveObjects() {
        var kids = list.contentItem.children
        var n = 0
        for (var i = 0; i < kids.length; i++)
            if (kids[i] && kids[i].listingIndex !== undefined) n += root.objectsUnder(kids[i])
        return n
    }

    property var handler: null
    property string phase: "notch"
    property int notch: 0
    property int sweep: 0
    property int builtAtRest: 0
    property real perRow: NaN
    property int builtAfterFirst: -1
    property var sweepStart: null
    property var sweepTotals: []

    function snapshot() {
        return { rowFor: root.tally.rowFor, window: root.tally.window, thumb: root.tally.thumb, thumbcancel: root.tally.thumbcancel, dirsize: root.tally.dirsize, other: root.tally.other }
    }

    function begin() {
        root.noteDelegates()
        root.handler = root.wheelHandler()
        if (root.handler === null) { root.fail("no wheel handler found on the list"); root.report(); return }
        root.builtAtRest = root.seen.length
        if (root.builtAtRest < root.builtAtRestMin) {
            root.fail("the list builds " + root.builtAtRest + " delegates at rest, want at least " + root.builtAtRestMin)
            root.report()
            return
        }
        root.perRow = root.liveObjects() / root.builtAtRest
        if (!isFinite(root.perRow) || root.perRow < root.objectsPerRowMin || root.perRow > root.objectsPerRowMax)
            root.fail("a delegate holds " + root.perRow + " objects, want " + root.objectsPerRowMin + " to " + root.objectsPerRowMax)
        root.sweepStart = root.snapshot()
        pace.interval = root.coalesceWaitMs
        pace.start()
    }

    // One step a timer turn: a notch through the wheel handler each coalesce interval, then the settle wait, then the reset.
    Timer {
        id: pace
        repeat: false
        onTriggered: root.advance()
    }

    function advance() {
        if (root.phase === "notch") {
            if (root.notch < root.notches) {
                root.handler.handleWheel(root.wheelNotch())
                list.forceLayout()
                root.noteDelegates()
                root.notch += 1
                pace.interval = root.coalesceWaitMs
            } else {
                root.phase = "settle"
                pace.interval = root.settleWaitMs
            }
            pace.start()
            return
        }
        if (root.phase === "settle") {
            var now = root.snapshot()
            var d = {}
            for (var k in now) d[k] = now[k] - root.sweepStart[k]
            root.sweepTotals.push(d)
            if (root.sweep === 0)
                root.builtAfterFirst = root.seen.length
            list.contentY = 0
            list.forceLayout()
            root.noteDelegates()
            root.phase = "reset"
            pace.interval = root.settleWaitMs
            pace.start()
            return
        }
        root.sweep += 1
        root.notch = 0
        root.phase = "notch"
        root.sweepStart = root.snapshot()
        if (root.sweep < root.sweeps) {
            pace.interval = root.coalesceWaitMs
            pace.start()
            return
        }
        root.finish()
    }

    function finish() {
        if (root.seen.length < root.builtMin)
            root.fail("ten notches build " + root.seen.length + " delegates, want at least " + root.builtMin + ", so the rows never entered")
        if (root.seen.length > root.builtMax)
            root.fail("ten notches build " + root.seen.length + " delegates over the " + root.builtMax + " ceiling")
        if (root.seen.length !== root.builtAfterFirst)
            root.fail("later sweeps build " + (root.seen.length - root.builtAfterFirst) + " more delegates, so the pool is not reused")
        for (var i = 0; i < root.sweepTotals.length; i++) {
            var d = root.sweepTotals[i]
            if (d.rowFor < root.rowForPerSweepMin || d.rowFor > root.rowForPerSweepMax)
                root.fail("sweep " + i + " reads rowFor " + d.rowFor + " times, want " + root.rowForPerSweepMin + " to " + root.rowForPerSweepMax)
            if (d.window !== 0)
                root.fail("sweep " + i + " asks the backend for " + d.window + " windows inside a held window, want 0")
            if (d.other !== 0)
                root.fail("sweep " + i + " sends " + d.other + " peeks or size cancels, want 0")
            if (d.thumb > root.settleAsksMax || d.thumbcancel > root.settleAsksMax || d.dirsize > root.settleAsksMax)
                root.fail("sweep " + i + " asks for thumbs " + d.thumb + ", cancels " + d.thumbcancel + ", sizes " + d.dirsize + ", want at most " + root.settleAsksMax + " each, one per settle")
        }
        if (root.failures.length === 0)
            console.log("ROWSCROLL PASS perRow=" + root.perRow + " built=" + root.seen.length + " rowFor=" + root.sweepTotals[0].rowFor + " thumb=" + root.sweepTotals[0].thumb)
        root.report()
    }

    function fail(text) { root.failures.push(text) }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("ROWSCROLL FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
