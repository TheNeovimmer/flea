//@ pragma ShellId flea-scrolloff-view-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/ScrollOff.js" as ScrollOff

// F4 scrolloff-view: the real List and ColumnPane prove the wiring behaviourally.
// A keyboard move carries context 3 through firstFor, a pointer move carries context 0
// through containY; reading contentY after each tells which path the view took.
ShellRoot {
    id: root

    property var failures: []
    property int rowCount: 60
    function fail(text) { root.failures.push(text) }
    function near(a, b) { return Math.abs(Number(a) - Number(b)) <= 1 }

    function buildRows() {
        var rows = []
        for (var i = 0; i < root.rowCount; i++) {
            var n = "item" + (i < 10 ? "0" + i : i) + ".txt"
            rows.push({ n: n, d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
        }
        return rows
    }

    Component {
        id: backendStub
        QtObject {
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 60
            property int total: 60
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property string renameError: ""
            property bool renamePending: false
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
            property int cacheRows: 0
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            property var statusBar: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return false }
            function commitRename(newName) {}
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

    Flea.List {
        id: list
        width: 700
        height: 300
        pane: root.stubPane
        menu: root.stubMenu
    }

    Flea.ColumnPane {
        id: col
        x: 0
        y: 320
        width: 400
        height: 200
        rows: root.stubPane.rows
        selectedIndex: -1
    }

    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.measure()
    }

    // A keyboard move keeps three rows of context; a pointer move never scrolls under the pointer.
    function measure() {
        var rowH = Flea.Theme.fileRowHeight
        if (!(rowH > 0)) { root.fail("no row height"); root.report(); return }
        var listV = ScrollOff.fullyVisible(list.height, rowH)
        var colViewH = 200
        var colV = ScrollOff.fullyVisible(colViewH, rowH)
        if (listV < 5 || colV < 3) { root.fail("viewport too short"); root.report(); return }

        // List keyboard: the last fully visible row keeps three rows below it.
        list.contentY = list.originY
        list.showCursor(listV - 1, 3)
        var wantList = ScrollOff.firstFor(0, listV, listV - 1, root.rowCount, 3)
        if (!root.near(list.contentY - list.originY, wantList * rowH))
            root.fail("list keyboard contentY " + list.contentY + ", want " + (wantList * rowH))
        if (wantList <= 0)
            root.fail("list keyboard moved nothing, want a three-row push")

        // List pointer: a fully visible row moves nothing.
        list.contentY = list.originY
        list.showCursor(listV - 1, 0)
        if (!root.near(list.contentY - list.originY, 0))
            root.fail("list pointer moved under the pointer: " + list.contentY)

        // List pointer: a cut row moves just enough to show it whole.
        list.contentY = list.originY
        list.showCursor(listV, 0)
        var cutTop = listV * rowH
        var wantPx = ScrollOff.containY(cutTop, rowH, 0, list.height)
        if (!root.near(list.contentY - list.originY, wantPx))
            root.fail("list pointer cut contentY " + list.contentY + ", want " + wantPx)
        var keyGrid = ScrollOff.firstFor(0, listV, listV, root.rowCount, 0) * rowH
        if (root.near(wantPx, keyGrid) && wantPx !== 0)
            root.fail("list pointer answered the row grid, want pixels")

        // Columns pointer: a fully visible row moves nothing, taken before any scroll.
        col.showCursor(0, 0)
        if (!root.near(col.contentY(), 0))
            root.fail("columns pointer moved under the pointer: " + col.contentY())

        // Columns pointer: a cut row moves just enough to show it whole.
        col.showCursor(colV, 0)
        var colCutTop = colV * rowH
        var colWantPx = ScrollOff.containY(colCutTop, rowH, 0, colViewH)
        if (!root.near(col.contentY(), colWantPx))
            root.fail("columns pointer cut contentY " + col.contentY() + ", want " + colWantPx)

        // Columns keyboard: same three-row rule in the neighbour column.
        col.positionViewAtIndex(0, ListView.Beginning)
        col.showCursor(colV - 1, 3)
        var wantCol = ScrollOff.firstFor(0, colV, colV - 1, root.rowCount, 3)
        if (wantCol <= 0)
            root.fail("columns keyboard moved nothing")
        if (!root.near(col.contentY(), wantCol * rowH))
            root.fail("columns keyboard contentY " + col.contentY() + ", want " + (wantCol * rowH))

        if (root.failures.length === 0)
            console.log("SCROLLOFFVIEW PASS rows=" + root.rowCount + " listV=" + listV + " colV=" + colV)
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("SCROLLOFFVIEW FAIL " + root.failures[f])
        console.log("SCROLLOFFVIEW DONE failures=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
