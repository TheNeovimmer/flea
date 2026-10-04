//@ pragma ShellId flea-rename-scroll-far-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Anchor.js" as Anchor

// The real ui/List.qml, ui/GridArea.qml or ui/ColumnPane.qml (RENAME_SCROLL_MODE) over the stub pane: a renamed row located far from the held window is revealed whole, the way a keyboard jump reveals it.
ShellRoot {
    id: root

    readonly property string mode: Quickshell.env("RENAME_SCROLL_MODE")
    readonly property string tag: "far-" + root.mode
    readonly property int totalRows: 1202
    readonly property int viewHeight: 619
    readonly property int stepTicks: 100
    // Loop turns a step waits for a layout or a delegate to settle, as rename-scroll.qml does.
    readonly property int settleTicks: 4
    // The row the cursor stood on before the rename, deep in the list.
    readonly property int oldRow: 600
    // Where the renamed file sorted: past the end, then to the top.
    readonly property var landings: [root.totalRows - 1, 0]
    property int checks: 0
    property int failures: 0
    property Item view: null
    property int step: 0
    property int waited: 0
    property int target: 0
    property var rowList: []

    function check(ok, label) {
        root.checks += 1
        if (!ok) {
            root.failures += 1
            console.log("RENAMESCROLL FAIL " + root.tag + " " + label)
        }
    }

    function finish(note) {
        farTimer.stop()
        if (note.length > 0) {
            root.failures += 1
            console.log("RENAMESCROLL FAIL " + root.tag + " " + note)
        }
        console.log("RENAMESCROLL MODE " + root.tag + " checks=" + root.checks + " failed=" + root.failures)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Component { id: paneStub; RenamePaneStub {} }
    property var stubPane: paneStub.createObject(root, { mode: root.mode, totalRows: root.totalRows })

    Component { id: listComponent; Flea.List {} }
    Component { id: gridComponent; Flea.GridArea {} }
    Component { id: columnComponent; Flea.ColumnPane {} }

    // The columns view's area as AnchorHold.viewport and Pane.showRow reach it.
    QtObject {
        id: columnsStub
        function activeColumn() { return root.view }
    }

    Window {
        id: win
        width: 1000
        height: 700
        visible: true
        Component.onCompleted: {
            var rows = []
            for (var i = 0; i < root.totalRows; i++)
                rows.push({ n: "f" + i + ".txt", d: false, i: "text-x-generic", p: 420, s: 13 })
            root.rowList = rows
            var props = { width: 1000, height: root.viewHeight }
            if (root.mode === "grid") {
                props.pane = root.stubPane
                props.menu = root.stubPane.menu
                root.view = gridComponent.createObject(win.contentItem, props)
            } else if (root.mode === "columns") {
                // A peek-shaped column (no pane) keeps the real ListView, footer and showCursor without the pane's trash and drop surface.
                props.width = 400
                props.rows = rows
                root.view = columnComponent.createObject(win.contentItem, props)
                root.stubPane.columnsArea = columnsStub
            } else {
                props.pane = root.stubPane
                props.menu = root.stubPane.menu
                root.view = listComponent.createObject(win.contentItem, props)
            }
            root.stubPane.listArea = root.view
            farTimer.start()
        }
    }

    function scroller() { return root.mode === "columns" ? root.view.viewport : root.view }
    function rowHeightNow() { return root.mode === "grid" ? root.view.cellHeight : Flea.Theme.fileRowHeight }
    function settled() { return root.waited >= root.settleTicks }
    // The count as the views see it: the stub's total drives the list and the grid, the column's own rows drive the column.
    function setCount(n) {
        root.stubPane.totalRows = n
        if (root.mode === "columns")
            root.view.rows = n === 0 ? [] : root.rowList
    }
    function countNow() { return root.mode === "columns" ? root.view.rows.length : root.view.count }

    // What a rows reply does after the backend answers the locate: the anchor takes the matches, as ui/PaneWire.qml hands them over.
    function landFar(found) {
        var anchor = { name: "zzz.txt", renamed: true, index: root.oldRow, select: true, marks: [], kept: [], hadMarks: false, locateSent: true, locateId: 7 }
        var taken = Anchor.takeLocated(root.stubPane, anchor, { directory: root.stubPane.path, id: 7, transferId: 0, ok: true,
            matches: [{ path: root.stubPane.path + "/zzz.txt", index: found }] }, root.rowHeightNow())
        root.check(taken.handled && taken.anchor === null, "the located reply is taken and the anchor is spent")
    }

    // The delegate for a row, or null while the view has not built it.
    function itemFor(index) { return root.scroller().itemAtIndex(index) }

    function rowWhole(index) {
        var item = root.itemFor(index)
        var view = root.scroller()
        return item !== null && item.y >= view.contentY && item.y + item.height <= view.contentY + view.height
    }

    // Past the end the content has nothing to scroll to, so a landing must not leave a blank strip under the last row.
    function noBlankStrip() {
        var view = root.scroller()
        return view.contentY >= view.originY - (typeof view.topMargin === "number" ? view.topMargin : 0)
            && view.contentY <= Math.max(view.originY, view.contentHeight - view.height + view.originY)
    }

    // Each entry is [ready, run]: run fires once ready answers true, and a step that never gets ready fails by name.
    function caseSteps(found) {
        var label = "a renamed row located at " + found
        return [
            [function () { return root.countNow() === root.totalRows && root.settled() }, function () {
                var view = root.scroller()
                // The cursor stood deep in the list, so the view is scrolled there before the re-list.
                view.positionViewAtIndex(root.oldRow, ListView.Beginning)
                root.stubPane.cursorIndex = root.oldRow
            }],
            [function () { return root.settled() }, function () { root.setCount(0) }],
            [function () { return root.countNow() === 0 }, function () {
                // The re-list's count is back and the view has not laid out yet when the located reply lands, as in the pane.
                root.setCount(root.totalRows)
                root.landFar(found)
            }],
            [function () { return root.countNow() === root.totalRows && root.settled() }, function () {
                root.check(root.stubPane.cursorIndex === found, label + ": the cursor is on the renamed row")
                root.check(root.stubPane.selectedAt === found, label + ": and the selection is")
                root.check(root.rowWhole(found), label + ": and the row is whole inside the viewport")
                root.check(root.noBlankStrip(), label + ": and the view shows no blank strip")
            }]
        ]
    }

    readonly property var flow: root.caseSteps(root.landings[0]).concat(root.caseSteps(root.landings[1])).concat([[function () { return true }, function () { root.finish("") }]])

    Timer {
        id: farTimer
        interval: 20
        repeat: true
        onTriggered: {
            var entry = root.flow[root.step]
            if (!entry[0]()) {
                root.waited += 1
                if (root.waited > root.stepTicks) { farTimer.stop(); root.finish("step " + root.step + " never became ready") }
                return
            }
            root.waited = 0
            entry[1]()
            root.step += 1
        }
    }
}
