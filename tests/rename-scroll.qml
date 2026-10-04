//@ pragma ShellId flea-rename-scroll-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Filter.js" as Filter

// The real ui/List.qml and its Row editor, or ui/GridArea.qml and its GridTile editor (RENAME_SCROLL_MODE), over a stub pane in a real Window.
ShellRoot {
    id: root

    readonly property string mode: Quickshell.env("RENAME_SCROLL_MODE")
    readonly property int totalRows: 1202
    readonly property int stepTicks: 100
    // Loop turns a step waits when its result is an absence no state change announces, as the old probe's 80 ms tick did.
    readonly property int settleTicks: 4
    property int checks: 0
    property int failures: 0
    property var request: ({ source: "/fixture/a-original.md", destination: "/fixture/pending.md" })
    property Item view: null
    property real baseGeometry: -1

    function check(ok, label) {
        root.checks += 1
        if (!ok) {
            root.failures += 1
            console.log("RENAMESCROLL FAIL " + root.mode + " " + label)
        }
    }

    function finish(note) {
        flowTimer.stop()
        if (note.length > 0) {
            root.failures += 1
            console.log("RENAMESCROLL FAIL " + root.mode + " " + note)
        }
        console.log("RENAMESCROLL MODE " + root.mode + " checks=" + root.checks + " failed=" + root.failures)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Component { id: paneStub; RenamePaneStub {} }

    // A field in a hidden parent that never began, which must not abandon the live editor.
    Component {
        id: ghostField
        Flea.RenameField {}
    }

    property var stubPane: paneStub.createObject(root, { mode: root.mode, totalRows: root.totalRows })

    Window {
        id: win
        width: 1000
        height: 700
        visible: true
        Component.onCompleted: {
            var props = { pane: root.stubPane, menu: root.stubPane.menu, width: 1000, height: 619 }
            if (root.mode === "grid") root.view = gridComponent.createObject(win.contentItem, props)
            else root.view = listComponent.createObject(win.contentItem, props)
            root.stubPane.listArea = root.view
            flowTimer.start()
        }
    }

    // Pane.qml wires the list's cursorClamped to Filter.clampCursor the same way; the grid has no such signal.
    Connections {
        target: root.mode === "grid" ? null : root.view
        function onCursorClamped(first, last) { Filter.clampCursor(root.stubPane, first, last) }
    }

    Component { id: listComponent; Flea.List {} }
    Component { id: gridComponent; Flea.GridArea {} }

    // Qt retains one delegate for the current index, the cell the checks read.
    function cellNow() { return root.view ? root.view.currentItem : null }
    function editorOf(cell) { return cell ? cell.editorField : null }
    function editorBegun() { var e = root.editorOf(root.cellNow()); return e !== null && e.begun }
    function scrollEnd() { root.view.contentY = Math.max(root.view.originY, root.view.originY + root.view.contentHeight - root.view.height) }
    function geometryNow() { return root.mode === "grid" ? root.view.cellHeight : (root.cellNow() ? root.cellNow().height : -1) }

    property int step: 0
    property int waited: 0
    function settled() { return root.waited >= root.settleTicks }

    // Each entry is [ready, run]: run fires once ready answers true, and a step that never gets ready fails by name.
    readonly property var flow: root.baseFlow.concat(root.mode === "grid" ? root.parkedTail : []).concat([[function () { return true }, function () { root.finish("") }]])
    readonly property var baseFlow: [
        [function () { return root.cellNow() !== null }, function () {
            root.baseGeometry = root.geometryNow()
            root.view.forceActiveFocus()
            root.stubPane.renamingIndex = 0
        }],
        [function () { return root.editorBegun() }, function () {
            root.check(root.editorBegun(), "real field began")
            root.editorOf(root.cellNow()).inputItem.text = "b-existing.md"
            root.stubPane.renameError = "b-existing.md already exists."
        }],
        [function () { var e = root.editorOf(root.cellNow()); return e !== null && e.errorHeight > 0 }, function () {
            var editor = root.editorOf(root.cellNow())
            root.check(editor.errorHeight > 0 && editor.inputItem.activeFocus, "expanded error retains focus")
            var hidden = Qt.createQmlObject("import QtQuick; Item { visible: false }", root.view)
            var ghost = ghostField.createObject(hidden, { pane: root.stubPane, viewport: root.view })
            root.check(ghost !== null && !ghost.begun && root.stubPane.renamingIndex === 0, "unbegun hidden field cannot abandon the live editor")
            hidden.destroy()
            root.view.contentY = root.view.originY + 1
        }],
        [function () { return root.settled() }, function () {
            root.check(root.stubPane.renamingIndex === 0 && root.editorOf(root.cellNow()) !== null
                && root.editorOf(root.cellNow()).current === "b-existing.md", "partial editor stays editable")
            root.scrollEnd()
        }],
        [function () { return root.stubPane.renamingIndex === -1 }, function () {
            root.check(root.view.itemAtIndex(0) === null && root.cellNow() !== null, "Qt retains currentItem outside held viewport")
            root.check(root.stubPane.renamingIndex === -1 && root.stubPane.renameError === "", "released editor clears ownership and error")
            root.check(root.view.activeFocus, "listing recovers focus")
            root.view.positionViewAtBeginning()
        }],
        [function () { return root.cellNow() !== null && root.editorOf(root.cellNow()) === null && root.geometryNow() === root.baseGeometry }, function () {
            root.check(root.editorOf(root.cellNow()) === null && root.geometryNow() === root.baseGeometry, "plain geometry recovers")
            root.stubPane.renamingIndex = 0
        }],
        [function () { return root.editorBegun() }, function () {
            root.editorOf(root.cellNow()).inputItem.text = "pending.md"
            root.stubPane.renameRequest = root.request
            root.scrollEnd()
        }],
        [function () { return root.view.itemAtIndex(0) === null }, function () {
            root.check(root.stubPane.renamingIndex === 0 && root.stubPane.renameRequest === root.request, "scroll preserves pending ownership")
            var editor = root.editorOf(root.cellNow())
            root.check(editor !== null && editor.current === "pending.md" && !editor.commit(), "pending draft and submit guard survive scroll")
            root.view.visible = false
            root.view.contentY = root.view.originY
        }],
        [function () { return root.settled() }, function () {
            root.check(root.stubPane.renamingIndex === 0 && root.stubPane.renameRequest === root.request, "hidden geometry retains pending ownership")
            root.check(root.editorOf(root.cellNow()) !== null && root.editorOf(root.cellNow()).current === "pending.md", "hidden geometry keeps the pending draft alive")
            root.stubPane.renameRequest = null
            root.stubPane.renamingIndex = -1
            root.view.visible = true
            root.view.positionViewAtBeginning()
        }],
        [function () { return root.cellNow() !== null && root.view.visible }, function () { root.stubPane.renamingIndex = 0 }],
        [function () { return root.editorBegun() }, function () { root.view.visible = false }],
        [function () { return root.settled() }, function () {
            root.check(root.stubPane.renamingIndex === -1 && root.stubPane.renameError === "", "nonpending hide still abandons")
            root.view.visible = true
        }]
    ]

    // End parks the last tile row flush with the viewport bottom, footer hidden; a cursor move inside that row must not scroll it.
    readonly property int lastTile: root.totalRows - 1
    property real parkedY: -1
    readonly property var parkedTail: [
        [function () { return root.view.visible && root.view.count > 0 }, function () {
            root.stubPane.setCursor(root.lastTile, 0)
        }],
        [function () { return root.settled() }, function () {
            root.parkedY = root.view.contentY
            var maxY = root.view.originY + root.view.contentHeight - root.view.height
            root.check(root.parkedY === maxY - Flea.Theme.chromeHeight, "end parks the last tile row flush with the bottom, footer hidden")
            root.check(root.view.itemAtIndex(root.lastTile) !== null, "the last tile is held")
            root.stubPane.cursorIndex = root.lastTile - 1
        }],
        [function () { return root.settled() }, function () {
            root.check(root.view.currentIndex === root.lastTile - 1, "the cursor moved to the neighbouring tile")
            root.check(root.view.contentY === root.parkedY, "a cursor move inside the parked row leaves the view where it was")
            root.stubPane.cursorIndex = 0
        }],
        [function () { return root.settled() }, function () {
            var tile = root.view.itemAtIndex(0)
            root.check(tile !== null && root.view.contentY <= root.view.originY, "a cursor change to an unseen tile reveals it without the pane's help")
            root.stubPane.setCursor(root.lastTile, 0)
        }],
        [function () { return root.settled() }, function () {
            root.check(root.view.contentY === root.parkedY, "the pane's own reveal parks the last row again")
        }]
    ]

    Timer {
        id: flowTimer
        interval: 20
        repeat: true
        onTriggered: {
            var entry = root.flow[root.step]
            if (!entry[0]()) {
                root.waited += 1
                if (root.waited > root.stepTicks) { flowTimer.stop(); root.finish("step " + root.step + " never became ready") }
                return
            }
            root.waited = 0
            entry[1]()
            root.step += 1
        }
    }
}
