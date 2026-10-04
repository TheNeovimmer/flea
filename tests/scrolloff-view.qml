//@ pragma ShellId flea-scrolloff-view-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/ScrollOff.js" as ScrollOff

// F4 scrolloff-view: the real List and ColumnPane prove the scrolloff wiring offscreen.
ShellRoot {
    id: root

    property var failures: []
    property int rowCount: 80
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
            property int dirDev: 0
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
            property int shownTotal: 80
            property int total: 80
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
            property var trash: ({ opened: false })
            property string dropPath: "/probe"
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

    Flea.List {
        id: endList
        y: 540
        width: 700
        height: 700
        pane: root.stubPane
        menu: root.stubMenu
    }

    Flea.ColumnPane {
        id: endCol
        x: 720
        y: 540
        width: 400
        height: 700
        rows: root.stubPane.rows
        selectedIndex: -1
    }

    Flea.ColumnPane {
        id: endColPane
        x: 1140
        y: 540
        width: 400
        height: 700
        pane: root.stubPane
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

        // End parks on the true end, a second End and three Ups keep it, Home returns; at a non-multiple, an exact-multiple and a short-remainder height.
        if (700 % rowH === 0)
            root.fail("the 700 px fixture is a multiple of the row height " + rowH)
        root.endChecks("list", endList, endList, 700)
        root.endChecks("list exact", endList, endList, 22 * rowH)
        root.endChecks("list short remainder", endList, endList, 22 * rowH + 5)
        root.endChecks("column", endCol, endCol.viewport, 700)
        root.endChecks("column exact", endCol, endCol.viewport, 22 * rowH)
        root.endChecks("column pane", endColPane, endColPane.viewport, 700)
        root.endChecks("column pane exact", endColPane, endColPane.viewport, 22 * rowH)
        root.endChecks("column pane short remainder", endColPane, endColPane.viewport, 22 * rowH + 2)

        if (root.failures.length === 0)
            console.log("SCROLLOFFVIEW PASS rows=" + root.rowCount + " listV=" + listV + " colV=" + colV)
        root.report()
    }

    // End parks the last row flush on the view's bottom edge and whole; the footer's bare ground stays one wheel step beyond.
    function endChecks(label, pane, view, height) {
        var rowH = Flea.Theme.fileRowHeight
        var last = root.rowCount - 1
        pane.height = height
        view.contentY = view.originY
        pane.showCursor(last, 3)
        var tail = view.contentHeight - root.rowCount * rowH
        var flushY = view.originY + root.rowCount * rowH - view.height
        var lastBottom = view.originY + root.rowCount * rowH - view.contentY
        if (Math.abs(view.contentY - flushY) > 0.5)
            root.fail(label + " End contentY " + view.contentY + ", want the last row flush at " + flushY)
        if (Math.abs(lastBottom - view.height) > 0.5)
            root.fail(label + " End last row bottom " + lastBottom + ", want the view's bottom " + view.height)
        if (tail === 0 && Math.abs(view.contentY + view.height - (view.originY + view.contentHeight)) > 0.5)
            root.fail(label + " End is short of the true end by " + (view.originY + view.contentHeight - view.contentY - view.height))
        console.log("SCROLLOFFVIEW INFO " + label + " rowH=" + rowH + " height=" + view.height + " footer=" + tail + " flush=" + flushY)
        var atEnd = view.contentY
        for (var up = 1; up <= 3; up++) {
            pane.showCursor(last - up, 3)
            if (Math.abs(view.contentY - atEnd) > 0.01)
                root.fail(label + " Up " + up + " moved the view from " + atEnd + " to " + view.contentY)
        }
        pane.showCursor(last, 3)
        pane.showCursor(last, 3)
        if (Math.abs(view.contentY - atEnd) > 0.01)
            root.fail(label + " a second End moved the view from " + atEnd + " to " + view.contentY)
        pane.showCursor(0, 3)
        if (Math.abs(view.contentY - view.originY) > 0.5)
            root.fail(label + " Home contentY " + view.contentY + ", want " + view.originY)
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("SCROLLOFFVIEW FAIL " + root.failures[f])
        console.log("SCROLLOFFVIEW DONE failures=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
