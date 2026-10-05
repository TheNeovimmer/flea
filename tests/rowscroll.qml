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
    readonly property int builtMax: 29
    readonly property int rowForPerSweepMax: 222
    property var failures: []
    // Plain fields of one object notify nothing, so a counting call inside a binding never loops it.
    property var tally: ({ rowFor: 0, isSelected: 0, backend: 0 })
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
            function peek(path, size, hidden) { root.tally.backend += 1 }
            function thumb(rows, cacheOnly) { root.tally.backend += 1 }
            function thumbcancel(rows) { root.tally.backend += 1 }
            function dirsize(rows) { root.tally.backend += 1 }
            function dirsizecancel() { root.tally.backend += 1 }
            function window(start, count) { root.tally.backend += 1 }
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
        onTriggered: root.run()
    }

    // The notch is the handler's own distance for one wheel click, found by its distance function.
    function notchPx() {
        for (var i = 0; i < list.children.length; i++) {
            var c = list.children[i]
            if (c && c.scrollDistance !== undefined)
                return Math.abs(c.scrollDistance(0, -120))
        }
        return -1
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

    function run() {
        root.noteDelegates()
        var px = root.notchPx()
        if (px <= 0) { root.failures.push("no scroll handler found"); root.report(); return }
        var builtAtRest = root.seen.length
        var perRow = root.liveObjects() / builtAtRest
        if (perRow > root.objectsPerRowMax)
            root.fail("a delegate holds " + perRow + " objects over the " + root.objectsPerRowMax + " ceiling")
        // Each sweep goes down ten notches and back to the top, so the first lands rows the view never drew.
        var rowForMax = 0
        var builtAfterFirst = -1
        for (var s = 0; s < root.sweeps; s++) {
            var r0 = root.tally.rowFor, b0 = root.tally.backend
            for (var n = 0; n < root.notches; n++) {
                list.contentY = Math.min(list.contentHeight - list.height, list.contentY + px)
                list.forceLayout()
                root.noteDelegates()
            }
            rowForMax = Math.max(rowForMax, root.tally.rowFor - r0)
            if (root.tally.backend !== b0)
                root.fail("a wheel scroll asks the backend " + (root.tally.backend - b0) + " times before it settles")
            if (s === 0)
                builtAfterFirst = root.seen.length
            list.contentY = 0
            list.forceLayout()
            root.noteDelegates()
        }
        if (root.seen.length > root.builtMax)
            root.fail("ten notches build " + root.seen.length + " delegates over the " + root.builtMax + " ceiling")
        if (root.seen.length !== builtAfterFirst)
            root.fail("later sweeps build " + (root.seen.length - builtAfterFirst) + " more delegates, so the pool is not reused")
        if (rowForMax > root.rowForPerSweepMax)
            root.fail("a ten notch sweep reads rowFor " + rowForMax + " times over the " + root.rowForPerSweepMax + " ceiling")
        if (root.failures.length === 0)
            console.log("ROWSCROLL PASS perRow=" + perRow + " built=" + root.seen.length + " rowFor=" + rowForMax)
        root.report()
    }

    function fail(text) { root.failures.push(text) }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("ROWSCROLL FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
