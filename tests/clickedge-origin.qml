//@ pragma ShellId flea-clickedge-origin-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Filter.js" as Filter

// Context-0 click on a whole row leaves contentY unchanged under shifted originY; driven offscreen over real ui/List.qml.
ShellRoot {
    id: root

    property var failures: []
    property int rowCount: 60
    property int step: 0
    property int wholeRow: -1
    property real wantY: 0
    property real beforeClick: -1

    function buildRows() {
        var rows = []
        for (var i = 0; i < root.rowCount; i++) {
            var n = "item" + (i < 10 ? "0" + i : i) + ".txt"
            rows.push({ n: n, d: false, i: "text-x-generic",
                p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
        }
        return rows
    }

    Component {
        id: backendStub
        QtObject {
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
            // The rename reveal's own cursor move is not under test; the probe
            // drives list.showCursor directly, so this stays a no-op.
            function setCursor(index, context) {}
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

    Component.onCompleted: {
        root.stubPane.visibleRows = Qt.binding(function () { return Math.max(1, Math.ceil(list.height / Flea.Theme.fileRowHeight)) })
    }

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
            onCursorClamped: function (first, last) { Filter.clampCursor(root.stubPane, first, last) }
        }
    }

    Timer {
        interval: 350
        running: true
        repeat: true
        onTriggered: {
            if (root.step === 0) root.openRename()
            else if (root.step === 1) root.expandAndScroll()
            else if (root.step === 2) root.collapseAndAim()
            else if (root.step === 3) root.clickWholeRow()
            root.step++
        }
    }

    function fail(text) { root.failures.push(text) }

    function openRename() {
        if (list.count !== root.rowCount) {
            root.fail("setup lists " + list.count + " rows, want " + root.rowCount)
            root.report()
            return
        }
        root.stubPane.renamingIndex = 0
    }

    function expandAndScroll() {
        var cell = list.itemAtIndex(0)
        if (cell === null || cell.renaming !== true || cell.editorField === null) {
            root.fail("rename builds no real editor on row 0")
            root.report()
            return
        }
        cell.editorField.inputItem.text = "item00-taken.txt"
        root.stubPane.renameError = "item00-taken.txt already exists in this folder, pick another name."
        var grown = list.itemAtIndex(0)
        if (grown === null || grown.height <= Flea.Theme.fileRowHeight) {
            root.fail("the error did not expand row 0")
            root.report()
            return
        }
        list.contentY = Math.max(list.originY, list.originY + list.contentHeight - list.height)
    }

    function collapseAndAim() {
        // Scrolled out, the editor abandons itself; a manual clear covers a Qt
        // that kept it, either way the delegate collapses here.
        if (root.stubPane.renamingIndex >= 0)
            root.stubPane.renamingIndex = -1
        if (root.stubPane.renamingIndex !== -1) {
            root.fail("the rename did not release")
            root.report()
            return
        }
        var oy = list.originY
        if (!(Math.abs(oy) >= 2)) {
            root.fail("control produced no shifted Qt origin, originY=" + oy)
            root.report()
            return
        }
        var rowH = Flea.Theme.fileRowHeight
        var H = list.height
        // A window the old row-grid code misreads: the row is truly whole in the
        // origin space and cut without it, which is F7 in either shift direction.
        // A negative shift cuts the row's naive bottom, a positive one its naive top.
        var i = 10
        var d = Math.min(rowH / 2, Math.abs(oy) / 2)
        if (oy < 0)
            root.wantY = (i + 1) * rowH - H - d
        else
            root.wantY = i * rowH + d
        root.wholeRow = i
        list.contentY = root.wantY
        if (Math.abs(list.contentY - root.wantY) >= 1) {
            root.fail("the aim landed at " + list.contentY + ", want " + root.wantY)
            root.report()
            return
        }
        var top = i * rowH
        // The cut the old row-grid code would take: below the window for a
        // negative shift, above it for a positive one.
        if (oy < 0) {
            if (!(top + rowH > list.contentY + H)) {
                root.fail("row " + i + " is naive-whole, the old code would not move either")
                root.report()
                return
            }
        } else {
            if (!(top < list.contentY)) {
                root.fail("row " + i + " is naive-whole, the old code would not move either")
                root.report()
                return
            }
        }
        if (!(top >= list.contentY - oy && top + rowH <= list.contentY - oy + H)) {
            root.fail("row " + i + " is not truly whole under originY=" + oy)
            root.report()
            return
        }
    }

    function clickWholeRow() {
        if (root.wholeRow < 0) {
            root.report()
            return
        }
        root.beforeClick = list.contentY
        list.showCursor(root.wholeRow, 0)
        if (Math.abs(list.contentY - root.beforeClick) >= 0.5) {
            root.fail("a click on whole row " + root.wholeRow + " scrolled "
                + root.beforeClick + " to " + list.contentY + " under originY=" + list.originY)
        }
        if (root.failures.length === 0)
            console.log("CLICKEDGE_ORIGIN PASS row=" + root.wholeRow + " contentY=" + list.contentY + " originY=" + list.originY)
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("CLICKEDGE_ORIGIN FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
