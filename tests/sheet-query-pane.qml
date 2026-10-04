//@ pragma ShellId flea-sheet-query-pane-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/SheetQuery.js" as SheetQuery

// tests/sheet-query.sh's pane half: the real WindowBody, Pane, ContextMenu and PaneMenuActions behind the real sheet.
// A menu-only row Enter runs must reach the surface the menu row reaches, with no menu ever opened.
ShellRoot {
    id: root
    readonly property var pane: body.currentPane
    readonly property var sheet: pane.keymapSheet.item
    readonly property string fixture: Quickshell.env("FLEA_PATH")
    readonly property int fixtureRows: 4
    readonly property int cursorRow: 1
    readonly property int pollMs: 20
    readonly property int stageLimitMs: 8000
    // Compress runs last: its archive joins the listing and moves the cursor row.
    readonly property var cases: [
        { name: "Permissions", query: "perm", label: "Permissions" },
        { name: "Move to", query: "move to", label: "Move to" },
        { name: "Delete permanently confirm", action: "deletePermanently" },
        { name: "Compress leaf", query: ".", where: "Compress" }
    ]
    property int caseIndex: 0
    property string stage: "ready"
    property int checks: 0
    property int failures: 0
    property bool finished: false
    property bool executing: false
    property double started: Date.now()
    property int archiveStarts: 0
    property int archiveDones: 0
    property int startsBefore: 0
    property string lastMessage: ""
    readonly property var current: cases[caseIndex]

    function check(name, actual, expected) {
        checks += 1
        var equal = actual === expected
        if (!equal) failures += 1
        console.log("SHEETPANE " + (equal ? "ok " : "FAIL ") + current.name + " " + name + ": got " + actual + ", expected " + expected)
    }
    function ipcObject() {
        for (var i = 0; i < body.data.length; i++)
            if (String(body.data[i]).indexOf("Ipc_") === 0) return body.data[i]
        throw new Error("WindowBody has no IPC seam")
    }
    function permissionsOpen() {
        var state = JSON.parse(ipcObject().seam.permissionsState())
        return state.opened === true && state.busy !== true
    }
    // True once the case's own surface is up: the Permissions dialog, a started compress, or the menu's dialog card.
    function observed() {
        if (current.name === "Permissions") return permissionsOpen()
        if (current.name === "Compress leaf") return archiveStarts > startsBefore
        if (current.name === "Move to") return pane.menuActions.opened && pane.menuActions.dialogFor === "moveTo"
        return pane.menuActions.opened && pane.menuActions.dialogFor === "deletePermanently"
    }
    function idle() {
        return !pane.listInFlight && !pane.menuActions.opened && !permissionsOpen() && !pane.keymapSheet.opened
            && archiveDones >= archiveStarts
    }
    function typeQuery(word) {
        for (var i = 0; i < word.length; i++) driver.keyClickChar(word.charAt(i), Qt.NoModifier, -1)
    }
    function pressKey(key) { driver.keyClick(key, Qt.NoModifier, -1) }
    function pickIndex() {
        var results = sheet.queryResults
        for (var i = 0; i < results.length; i++)
            if ((current.label !== undefined && results[i].label === current.label)
                    || (current.where !== undefined && results[i].where === current.where && results[i].menuAction !== undefined))
                return i
        return -1
    }
    function next(stageName) { stage = stageName; started = Date.now() }
    function finish() {
        finished = true
        console.log("SHEETPANE DONE checks=" + checks + " failed=" + failures)
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
        var timedOut = Date.now() - started > stageLimitMs
        if (stage === "ready") {
            if (timedOut) { check("fixture listed", false, true); finish(); return }
            if (pane.listInFlight || pane.path !== fixture || pane.total < fixtureRows || !pane.visibleItemFor(cursorRow)) return
            next("open")
        } else if (stage === "open") {
            if (!idle() && !timedOut) return
            pane.setCursor(cursorRow)
            pane.listArea.forceActiveFocus()
            lastMessage = ""
            startsBefore = archiveStarts
            // Opened as Focus.windowAction opens it: the sheet is the only thing the cursor row's menu was ever asked for.
            pane.keymapSheet.open(pane)
            if (current.action !== undefined) {
                // A confirm row has a key in every preset, so the row the sheet's dispatch would hand runMenu is run directly.
                SheetQuery.runMenu(pane, current.action, function () { sheet.close() })
                next("ran")
                return
            }
            typeQuery(current.query)
            next("typed")
        } else if (stage === "typed") {
            if (sheet.query !== current.query && !timedOut) return
            check("the query reads back whole", sheet.query, current.query)
            var pickAt = pickIndex()
            check("the row is listed", pickAt >= 0, true)
            if (pickAt < 0) {
                sheet.close()
                next("settle")
                return
            }
            // Down moves the real cursor; reading its row first makes a ranking change fail by name.
            for (var step = 0; step < pickAt; step++) pressKey(Qt.Key_Down)
            check("the highlighted row is the one picked", sheet.queryResults[sheet.resultCursor].label, sheet.queryResults[pickAt].label)
            pressKey(Qt.Key_Return)
            next("ran")
        } else if (stage === "ran") {
            if (!observed() && !timedOut) return
            check("Enter reached the menu's own surface (last message '" + lastMessage + "')", observed(), true)
            check("and the sheet closed", pane.keymapSheet.opened, false)
            // Escape dismisses the card the row opened; a compress needs only to finish.
            if (current.name !== "Compress leaf") pressKey(Qt.Key_Escape)
            next("settle")
        } else if (stage === "settle") {
            if (!idle() && !timedOut) return
            check("the pane came back to idle", idle(), true)
            caseIndex += 1
            if (caseIndex === cases.length) finish()
            else next("open")
        }
    }

    Connections {
        target: root.pane
        function onMessage(text, isError) { root.lastMessage = text }
    }
    Connections {
        target: root.pane.backend
        function onArchiveStarted(id) { root.archiveStarts += 1 }
        function onArchiveDone(id, ok, verified, err) { root.archiveDones += 1 }
    }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 800
        // The IPC seam's permissionsState reads the dialog's rectangle and centre through the window it lives in.
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
