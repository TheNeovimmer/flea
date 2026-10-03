//@ pragma ShellId flea-menu-snapshot-retire-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/menu-snapshot-retire.sh's harness: a snapshot reply after its dismissed menu retires silently.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0
    property int expectId: 0

    function log(line) { console.log("SNAPRETIRE " + line) }
    // A snapshot over the identity, answered ok, with the editor state and messages cleared.
    function readyRename(identity) {
        stubPane.messages = []
        stubPane.renamingIndex = -1
        stubPane.renameSource = ""
        stubPane.menuSelectionIdentity = identity
        actions.snapshot([stubPane.cursorIndex])
        stubBackend.menuResult({op: "snapshot", id: actions.requestId, ok: true})
    }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        if (cond) shell.log("PASS " + name)
        else shell.failures.push(name + " got " + detail)
    }

    Item {
        // Sample reply: {op:"snapshot", id:1, ok:true}; a refusal carries ok:false with its error.
        Item {
            id: stubBackend
            signal menuResult(var message)
            signal formatsResult(var message)
            signal changed(string path)
            signal located(var message)
            signal localSendPeers(var peers, string reason)
            signal localSendSent(bool ok, string reason)
            signal failed(string where, string input, string message, int mode)
            property var sent: []
            function send(m) { sent.push(m) }
            function askFormats() { return 0 }
        }

        Item {
            id: stubMenu
            property bool opened: false
            property bool hasRow: true
            function refreshProviderRows() {}
            function providersSettled() {}
            function validateChoice(action, subId) { return true }
        }

        Item {
            id: stubPane
            property string menuSelectionIdentity: "ID-A"
            property string path: "/payload"
            property int cursorIndex: 2
            property bool renamePending: false
            property string renameError: ""
            property string renameSource: ""
            property int renameMenuId: 0
            property int renamingIndex: -1
            property var shown: null
            property bool listInFlight: false
            property var backend: stubBackend
            property var taildropService: null
            property var dropboxService: null
            property var messages: []
            function contextMenu() { return stubMenu }
            function message(text, isError) { messages.push(text + "|" + isError) }
            function rowFor(index) { return index >= 0 ? { n: "row" + index } : null }
            function setCursor(index, context) { cursorIndex = index }
            function join(folder, name) { return folder + "/" + name }
        }
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        Flea.PaneMenuActions {
            id: actions
            pane: stubPane
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    // Each phase snapshots, reorders the reply behind a refresh, then delivers it explicitly.
    function advance() {
        shell.ticks += 1
        if (shell.ticks < 2) return
        if (shell.phase === 0) {
            stubMenu.opened = true
            actions.snapshot([0])
            shell.expectId = actions.requestId
            stubMenu.opened = false
            stubPane.menuSelectionIdentity = "ID-B"
            stubBackend.menuResult({op: "snapshot", id: shell.expectId, ok: true})
            shell.check("dismissed-stale-silent", stubPane.messages.length === 0 && !actions.ready,
                stubPane.messages.join(";") + " ready=" + actions.ready)
            shell.phase = 1
        } else if (shell.phase === 1) {
            stubPane.messages = []
            stubPane.menuSelectionIdentity = "ID-A"
            stubMenu.opened = true
            actions.snapshot([0])
            shell.expectId = actions.requestId
            stubPane.menuSelectionIdentity = "ID-B"
            stubBackend.menuResult({op: "snapshot", id: shell.expectId, ok: true})
            shell.check("open-stale-refuses", stubPane.messages.length === 1
                && stubPane.messages[0] === "Selected items changed; reopen the menu.|true",
                stubPane.messages.join(";"))
            stubMenu.opened = false
            shell.phase = 2
        } else if (shell.phase === 2) {
            stubPane.messages = []
            stubPane.menuSelectionIdentity = "ID-A"
            actions.snapshot([0])
            shell.expectId = actions.requestId
            stubBackend.menuResult({op: "snapshot", id: shell.expectId, ok: false, error: "backend broke"})
            shell.check("dismissed-refusal-reports", stubPane.messages.length === 1
                && stubPane.messages[0] === "backend broke|true", stubPane.messages.join(";"))
            shell.phase = 3
        } else if (shell.phase === 3) {
            stubPane.messages = []
            stubPane.menuSelectionIdentity = "ID-A"
            actions.snapshot([0])
            shell.expectId = actions.requestId
            stubBackend.menuResult({op: "snapshot", id: shell.expectId, ok: true, count: 2})
            shell.check("dismissed-fresh-readies", stubPane.messages.length === 0 && actions.ready,
                stubPane.messages.join(";") + " ready=" + actions.ready)
            shell.phase = 4
        } else if (shell.phase === 4) {
            stubPane.messages = []
            stubPane.menuSelectionIdentity = "ID-A"
            actions.snapshot([0])
            shell.expectId = actions.requestId
            actions.open("copyTo")
            stubMenu.opened = false
            stubPane.menuSelectionIdentity = "ID-B"
            stubBackend.menuResult({op: "snapshot", id: shell.expectId, ok: true})
            shell.check("waiting-action-refuses", stubPane.messages.length === 1
                && stubPane.messages[0] === "Selected items changed; reopen the menu.|true",
                stubPane.messages.join(";"))
            shell.phase = 5
        } else if (shell.phase === 5) {
            // openRenameFromMenu over a moved identity: refused, no editor, no snapshot request, no F2 route.
            shell.readyRename("ID-A")
            stubPane.menuSelectionIdentity = "ID-B"
            var movedSent = stubBackend.sent.length
            actions.openRenameFromMenu()
            shell.check("rename-moved-refuses", stubPane.messages.length === 1
                && stubPane.messages[0] === "Selected items changed; reopen the menu.|true", stubPane.messages.join(";"))
            shell.check("rename-moved-opens-no-editor", stubPane.renamingIndex === -1 && stubPane.renameSource === "",
                "index=" + stubPane.renamingIndex + " source=" + stubPane.renameSource)
            shell.check("rename-moved-sends-nothing", stubBackend.sent.length === movedSent && actions.pendingAction === "",
                "sent=" + (stubBackend.sent.length - movedSent) + " pending=" + actions.pendingAction)
            shell.phase = 6
        } else if (shell.phase === 6) {
            // An unchanged identity with a ready snapshot opens the editor at once over the cursor row.
            shell.readyRename("ID-A")
            var nowSent = stubBackend.sent.length
            actions.openRenameFromMenu()
            shell.check("rename-ready-opens-at-once", stubPane.renamingIndex === stubPane.cursorIndex
                && stubPane.renameMenuId === actions.requestId && stubPane.messages.length === 0,
                "index=" + stubPane.renamingIndex + " menuId=" + stubPane.renameMenuId + " said=" + stubPane.messages.join(";"))
            shell.check("rename-ready-sends-nothing", stubBackend.sent.length === nowSent, "sent=" + (stubBackend.sent.length - nowSent))
            shell.phase = 7
        } else if (shell.phase === 7) {
            // An unchanged identity whose snapshot is still in flight takes the F2 route: a fresh snapshot for the cursor row.
            shell.readyRename("ID-A")
            stubPane.renamingIndex = -1
            actions.snapshot([0])
            var f2Sent = stubBackend.sent.length
            actions.openRenameFromMenu()
            var request = stubBackend.sent[stubBackend.sent.length - 1]
            shell.check("rename-in-flight-takes-f2", stubBackend.sent.length === f2Sent + 1 && request.op === "snapshot"
                && request.rows.length === 1 && request.rows[0] === stubPane.cursorIndex && actions.pendingAction === "rename"
                && stubPane.renamingIndex === -1, "sent=" + (stubBackend.sent.length - f2Sent) + " pending=" + actions.pendingAction)
            for (var i = 0; i < shell.failures.length; i++)
                shell.log("FAIL " + shell.failures[i])
            shell.log("DONE failures=" + shell.failures.length)
            shell.phase = 8
            shell.quit()
        }
    }
}
