//@ pragma ShellId flea-rename-scroll-origin-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Filter.js" as Filter

// The real ui/List.qml over the stub pane: an expanded rename delegate discarded by a scroll shifts originY, and one Home action must land on the first row.
ShellRoot {
    id: root

    readonly property string mode: "origin"
    readonly property int totalRows: 1202
    readonly property int stepTicks: 100
    property int checks: 0
    property int failures: 0
    property Item view: null
    property int step: 0
    property int waited: 0

    function check(ok, label) {
        root.checks += 1
        if (!ok) {
            root.failures += 1
            console.log("RENAMESCROLL FAIL origin " + label)
        }
    }

    function finish(note) {
        originTimer.stop()
        if (note.length > 0) {
            root.failures += 1
            console.log("RENAMESCROLL FAIL origin " + note)
        }
        console.log("RENAMESCROLL MODE origin checks=" + root.checks + " failed=" + root.failures)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Component { id: paneStub; RenamePaneStub {} }
    property var stubPane: paneStub.createObject(root, { mode: "origin", totalRows: root.totalRows })

    Window {
        id: win
        width: 1000
        height: 700
        visible: true
        Component.onCompleted: {
            root.view = listComponent.createObject(win.contentItem, { pane: root.stubPane, menu: root.stubPane.menu, width: 1000, height: 619 })
            root.stubPane.listArea = root.view
            originTimer.start()
        }
    }

    // Pane.qml wires the list's cursorClamped to Filter.clampCursor the same way.
    Connections {
        target: root.view
        function onCursorClamped(first, last) { Filter.clampCursor(root.stubPane, first, last) }
    }

    Component { id: listComponent; Flea.List {} }

    function cellNow() { return root.view ? root.view.currentItem : null }
    function editorOf(cell) { return cell ? cell.editorField : null }
    function editorBegun() { var e = root.editorOf(root.cellNow()); return e !== null && e.begun }

    // The origin mode: an expanded delegate discarded by a scroll shifts originY, then one Home action must land on the first row.
    function geometryLine(label) {
        console.log("RENAMESCROLL ORIGIN " + label + " contentY=" + root.view.contentY + " originY=" + root.view.originY
            + " first=" + root.view.visibleRange().first + " cursor=" + root.stubPane.cursorIndex
            + " row0=" + (root.view.itemAtIndex(0) ? root.view.itemAtIndex(0).y : "discarded"))
    }

    readonly property var origin: [
        [function () { return root.cellNow() !== null }, function () {
            root.check(root.view.visibleRange().first === 0 && root.view.coversCursor(0), "plain origin covers first row")
            root.stubPane.renamingIndex = 0
        }],
        [function () { return root.editorBegun() }, function () {
            root.check(root.editorBegun(), "field began")
            root.editorOf(root.cellNow()).inputItem.text = "b-existing.md"
            root.stubPane.renameError = "b-existing.md already exists."
        }],
        [function () { return root.cellNow() !== null && root.cellNow().height > Flea.Theme.fileRowHeight }, function () {
            root.check(root.cellNow().height > Flea.Theme.fileRowHeight, "error expanded row")
            root.geometryLine("expanded")
            root.view.contentY = Math.max(root.view.originY, root.view.originY + root.view.contentHeight - root.view.height)
        }],
        [function () { return root.stubPane.renamingIndex === -1 }, function () {
            root.check(root.stubPane.renamingIndex === -1 && root.stubPane.renameError === "", "offscreen edit released")
            root.geometryLine("discarded")
            // The Home action from Focus.js, through the real Filter and the stub's showRow.
            Filter.setCursorView(root.stubPane, 0)
        }],
        [function () { return root.view.itemAtIndex(0) !== null && root.view.originY !== 0 }, function () {
            root.geometryLine("home")
            root.check(root.view.originY !== 0, "control produced shifted Qt origin")
            root.check(root.stubPane.cursorIndex === 0 && root.view.itemAtIndex(0) !== null && root.view.itemAtIndex(0).height > 0, "one Home restores first cursor row")
            root.check(root.view.coversCursor(0), "restore coverage includes shifted first row")
            root.check(root.view.visibleRange().first === 0, "visible work starts at first row")
            root.view.requestIfDrifted()
            root.check(root.stubPane.backend.asked === 0, "held-window request starts at first row")
            root.view.contentY = root.view.originY + Flea.Theme.fileRowHeight + 1
        }],
        [function () { return root.stubPane.cursorIndex === 1 }, function () {
            root.check(root.stubPane.cursorIndex === 1 && root.view.visibleRange().first === 1, "ordinary scroll follows relative row offset")
            root.view.requestIfDrifted()
            root.check(root.stubPane.backend.asked === 1 && root.view.coversCursor(1), "scroll keeps held work and restore coverage aligned")
            Filter.setCursorView(root.stubPane, root.stubPane.shownTotal - 1)
        }],
        [function () { return root.view.itemAtIndex(root.totalRows - 1) !== null }, function () {
            root.geometryLine("end")
            root.check(root.stubPane.cursorIndex === root.totalRows - 1 && root.view.itemAtIndex(root.totalRows - 1) !== null, "one End restores last cursor row")
            root.finish("")
        }]
    ]

    Timer {
        id: originTimer
        interval: 20
        repeat: true
        onTriggered: {
            var entry = root.origin[root.step]
            if (!entry[0]()) {
                root.waited += 1
                if (root.waited > root.stepTicks) { originTimer.stop(); root.finish("step " + root.step + " never became ready") }
                return
            }
            root.waited = 0
            entry[1]()
            root.step += 1
        }
    }
}
