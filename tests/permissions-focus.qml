//@ pragma ShellId flea-permissions-focus-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea

// Real menu dispatch, Permissions and row input, with no focus repair before the tested input.
ShellRoot {
    id: root
    readonly property var pane: body.currentPane
    readonly property string fixture: Quickshell.env("FLEA_PATH")
    readonly property int fixtureRows: 4
    readonly property string draftMode: "0777"
    readonly property int pollMs: 20
    readonly property int stageLimitMs: 5000
    readonly property int pointerEventMs: 1
    readonly property var cases: [
        {dismiss: "Escape", input: "Down"}, {dismiss: "Cancel", input: "Down"},
        {dismiss: "Escape", input: "Right"}, {dismiss: "Cancel", input: "Right"},
        {dismiss: "Apply", input: "Down"}, {dismiss: "Apply", input: "Right"}
    ]
    property int caseIndex: 0
    property string stage: "ready"
    property int checks: 0
    property int failures: 0
    property int oldCursor: 0
    property double started: Date.now()
    property bool executing: false
    property bool finished: false
    readonly property var current: cases[caseIndex]

    function label() { return current.dismiss + "/" + current.input }
    function check(name, actual, expected) {
        checks += 1
        var equal = actual === expected
        if (!equal) failures += 1
        console.log("PERMFOCUS " + (equal ? "ok " : "FAIL ") + label() + " " + name
                    + ": got " + actual + ", expected " + expected)
    }
    function ipcObject() {
        for (var i = 0; i < body.data.length; i++)
            if (String(body.data[i]).indexOf("Ipc_") === 0) return body.data[i]
        throw new Error("WindowBody has no IPC seam")
    }
    function dialog() { return ipcObject().permissionsDialog }
    function control(name) {
        var controls = dialog().controls()
        for (var i = 0; i < controls.length; i++)
            if (controls[i].name === name) return controls[i].item
        throw new Error("Permissions has no " + name)
    }
    function press(key) { driver.keyClick(key, Qt.NoModifier, -1) }
    function click(item, button) {
        driver.mousePress(item, item.width / 2, item.height / 2, button, Qt.NoModifier, pointerEventMs)
        driver.mouseRelease(item, item.width / 2, item.height / 2, button, Qt.NoModifier, pointerEventMs)
    }
    function next(stage) { root.stage = stage; started = Date.now() }
    function finish() {
        finished = true
        console.log("PERMFOCUS DONE checks=" + checks + " failed=" + failures)
        body.quitBackends()
    }
    function advance() {
        if (executing || finished) return
        executing = true
        try { runStage() }
        catch (error) { check("harness error", String(error), "none"); finish() }
        executing = false
    }
    function runStage() {
        if (Date.now() - started > stageLimitMs) {
            check("stage " + stage + " completed", false, true)
            finish()
            return
        }
        if (stage === "ready") {
            if (pane.listInFlight || pane.path !== fixture || pane.total !== fixtureRows || !pane.visibleItemFor(1)) return
            pane.clearSelection()
            pane.setCursor(current.dismiss === "Cancel" ? 0 : 1)
            pane.listArea.forceActiveFocus()
            if (current.dismiss === "Escape") {
                click(pane.visibleItemFor(pane.cursorIndex), Qt.LeftButton)
                driver.keyClickChar("m", Qt.NoModifier, -1)
            } else click(pane.visibleItemFor(pane.cursorIndex), Qt.RightButton)
            check("native gesture opens menu", pane.contextMenu().opened, true)
            next("menu")
        } else if (stage === "menu") {
            var menu = pane.contextMenu()
            if (menu.pointerSettling || menu.providersRefreshing) return
            var at = menu.entries.findIndex(function(entry) { return entry.action === "permissions" })
            if (at >= 0 && menu.cursor !== at) { menu.cursor = at; return }
            var row = at >= 0 ? menu.itemFor(at) : null
            // Reveal and provider replies can move or replace a menu row before its next painted frame.
            if (row && !menu.frameItem.contains(menu.frameItem.mapFromItem(row, row.width / 2, row.height / 2))) return
            check("menu offers Permissions", at >= 0 && !menu.entries[at].disabled, true)
            if (current.dismiss === "Escape") press(Qt.Key_Return)
            else click(row, Qt.LeftButton)
            next("dialog")
        } else if (stage === "dialog") {
            var card = dialog()
            if (!card || !card.opened || card.busy) return
            check("menu closes before dialog", pane.contextMenu().opened, false)
            check("fixture editability", card.editable, current.dismiss !== "Cancel")
            check("open dialog refuses input readiness", JSON.parse(ipcObject().seam.permissionsState()).inputReady, false)
            if (current.dismiss === "Escape") {
                click(control("Octal"), Qt.LeftButton)
                driver.keyClick(Qt.Key_A, Qt.ControlModifier, -1)
                for (var digit = 0; digit < draftMode.length; digit++)
                    driver.keyClickChar(draftMode.charAt(digit), Qt.NoModifier, -1)
                press(Qt.Key_Escape)
            } else click(control(current.dismiss), Qt.LeftButton)
            next("dismissed")
        } else if (stage === "dismissed") {
            if (dialog().opened || pane.listInFlight) return
            check("dialog is hidden", dialog().visible, false)
            console.log("PERMFOCUS focus " + label() + " " + ipcObject().seam.keyDeliveryState())
            check("listing owns keyboard", pane.listArea.activeFocus, true)
            check("dismissal reports actual input readiness", JSON.parse(ipcObject().seam.permissionsState()).inputReady, true)
            oldCursor = pane.cursorIndex
            if (current.input === "Down") press(Qt.Key_Down)
            else click(pane.visibleItemFor(oldCursor), Qt.RightButton)
            next("input")
        } else if (stage === "input") {
            if (current.input === "Down") check("first Down moves cursor", pane.cursorIndex, oldCursor + 1)
            else check("first right press/release opens menu", pane.contextMenu().opened, true)
            pane.contextMenu().close()
            caseIndex += 1
            if (caseIndex === cases.length) finish()
            else next("ready")
        }
    }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 800
        function centreOf(item) {
            if (!item) return ""
            var rect = window.itemRect(item)
            return Math.round(rect.x + rect.width / 2) + " " + Math.round(rect.y + rect.height / 2)
        }
        function rectOf(item) {
            if (!item) return ""
            var rect = window.itemRect(item)
            var left = Math.round(rect.x), top = Math.round(rect.y)
            return left + " " + top + " " + (Math.round(rect.x + rect.width) - left) + " " + (Math.round(rect.y + rect.height) - top)
        }
        Flea.WindowBody { id: body; host: window }
        Item { anchors.fill: parent; TestEvent { id: driver } }
    }
    Timer { interval: root.pollMs; repeat: true; running: !root.finished; onTriggered: root.advance() }
}
