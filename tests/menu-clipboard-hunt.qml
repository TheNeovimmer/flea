//@ pragma ShellId flea-menu-clipboard-hunt-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Keymap.js" as Keymap
import "flea/js/Menu.js" as Menu

// Real window body and backend. Each invocation owns a fresh process; the shell driver
// supplies a shared clipboard-helper double and checks publication between invocations.
ShellRoot {
    id: shell
    property int stage: 0
    property int ticks: 0
    property string action: Quickshell.env("FLEA_HUNT_ACTION")
    property string destination: Quickshell.env("FLEA_HUNT_DEST")
    property var messages: []
    property bool quitting: false
    property int leafIndex: 0
    readonly property var copyLeaves: ["copyPath", "copyName", "copyStem", "copydirpath", "copyUri", "copyQuoted"]
    readonly property var pane: body.currentPane

    function log(line) { console.log("CLIPHUNT " + line) }
    function quit() {
        if (quitting) return
        quitting = true
        body.quitBackends()
    }

    FloatingWindow {
        id: window
        implicitWidth: 900
        implicitHeight: 600
        color: "#303030"
        Flea.WindowBody { id: body; host: window }
    }
    Connections {
        target: shell.pane
        function onMessage(text, isError) { shell.messages.push({text: text, error: isError}) }
    }
    Timer {
        interval: 100
        repeat: true
        running: !shell.quitting
        onTriggered: shell.advance()
    }
    function advance() {
        ticks += 1
        if (ticks > 200) { log("FAIL timeout waiting for stage " + stage); quit(); return }
        if (stage === 0 && action === "terminal" && !pane.listInFlight && pane.sidebar) {
            pane.contextMenu().openBackground(Qt.point(100, 100))
            pane.contextMenu().choose("openTerminal")
            log((pane.opener.terminalCurrent === pane.path ? "PASS" : "FAIL")
                + " background-terminal-path actual=" + pane.opener.terminalCurrent + " expected=" + pane.path)
            stage = 10
            ticks = 0
        } else if (stage === 10 && ticks >= 5) {
            // This is the same rail menu and chosen signal the real Places row raises.
            var entries = Menu.placeEntries({hiddenActions: [], placeFavourite: true})
            pane.contextMenu().openForRail("place:0:" + destination, entries, Qt.point(100, 100))
            pane.contextMenu().choose("openTerminal")
            log((pane.opener.terminalCurrent === destination ? "PASS" : "FAIL")
                + " place-terminal-path actual=" + pane.opener.terminalCurrent + " expected=" + destination)
            stage = 11
            ticks = 0
        } else if (stage === 11 && ticks >= 5) {
            log("DONE action=" + action)
            quit()
        } else if (stage === 0 && action === "original" && !pane.listInFlight && pane.total === 2 && pane.visibleItemFor(0)) {
            pane.cursorIndex = 0
            pane.openCursorMenu()
            stage = 15
            ticks = 0
        } else if (stage === 15 && pane.menuActions.ready) {
            pane.contextMenu().choose("showOriginal")
            stage = 16
            ticks = 0
        } else if (stage === 16 && !pane.listInFlight && pane.path !== destination && pane.cursorRow && pane.cursorRow.n === "alpha.txt") {
            log("PASS show-original-file-control path=" + pane.path + " cursor=" + pane.cursorRow.n)
            pane.open(destination)
            stage = 17
            ticks = 0
        } else if (stage === 17 && !pane.listInFlight && pane.path === destination && pane.visibleItemFor(1)) {
            pane.cursorIndex = 1
            pane.openCursorMenu()
            stage = 18
            ticks = 0
        } else if (stage === 18 && pane.menuActions.ready) {
            pane.contextMenu().choose("showOriginal")
            stage = 19
            ticks = 0
        } else if (stage === 19 && ticks >= 10) {
            log((pane.path === "/" ? "PASS" : "FAIL") + " show-original-root-target path="
                + pane.path + " messages=" + JSON.stringify(messages))
            log("DONE action=" + action)
            quit()
        } else if (stage === 0 && action.indexOf("copyas-") === 0 && !pane.listInFlight && pane.total === 2) {
            pane.chooseView(action.substring("copyas-".length))
            stage = 6
            ticks = 0
        } else if (stage === 6 && ticks >= 5 && pane.visibleItemFor(0)) {
            pane.selectAll()
            if (leafIndex === 0) {
                var invert = Keymap.lookup(Qt.Key_V, "V", Qt.ShiftModifier, "listing")
                pane.act(invert)
                log((pane.selectedIndices().length === 0 ? "PASS" : "FAIL")
                    + " " + action + " invert-clears-all action=" + invert + " count=" + pane.selectedIndices().length)
                pane.act(invert)
                log((pane.selectedIndices().length === 2 ? "PASS" : "FAIL")
                    + " " + action + " invert-marks-all count=" + pane.selectedIndices().length)
            }
            pane.act(Keymap.lookup(Qt.Key_C, "c", 0, "listing"))
            stage = 7
            ticks = 0
        } else if (stage === 7 && pane.menuActions.ready && pane.contextMenu().submenuOpen) {
            pane.contextMenu().chooseSub(copyLeaves[leafIndex])
            stage = 8
            ticks = 0
        } else if (stage === 8 && ticks >= 5) {
            log("INFO " + action + " dispatched=" + copyLeaves[leafIndex] + " messages=" + JSON.stringify(messages))
            leafIndex += 1
            if (leafIndex < copyLeaves.length) stage = 6
            else {
                pane.act(Keymap.lookup(Qt.Key_C, "", Qt.ControlModifier | Qt.ShiftModifier, "listing"))
                stage = 9
            }
            ticks = 0
        } else if (stage === 9 && ticks >= 5) {
            log("DONE action=" + action)
            quit()
        } else if (stage === 0 && action === "paste" && !pane.listInFlight && pane.path === destination) {
            pane.act(Keymap.lookup(Qt.Key_V, "", Qt.ControlModifier, "listing"))
            stage = 5
            ticks = 0
        } else if (stage === 5 && ticks >= 15) {
            log((pane.total === 2 ? "PASS" : "FAIL") + " fresh-window-system-paste-files total="
                + pane.total + " pending=" + JSON.stringify(pane.collide.pending) + " messages=" + JSON.stringify(messages))
            log("DONE action=" + action)
            quit()
        } else if (stage === 0 && pane.total === 2 && !pane.listInFlight && pane.visibleItemFor(0)) {
            pane.selectAll()
            var key = action === "cut" ? Qt.Key_X : Qt.Key_C
            var resolved = Keymap.lookup(key, "", Qt.ControlModifier, "listing")
            var expected = action === "cut" ? "cut" : "copy"
            if (resolved !== expected) { log("FAIL key resolved " + resolved + ", want " + expected); quit(); return }
            pane.act(resolved)
            stage = 1
            ticks = 0
        } else if (stage === 1 && pane.clipboard.paths.length === 2) {
            log("PASS local-" + action + " paths=" + pane.clipboard.paths.join("|") + " moving=" + pane.clipboard.moving)
            // Publication may be asynchronous. Wait a full second after paths have resolved.
            stage = 2
            ticks = 0
        } else if (stage === 2 && ticks >= 10) {
            pane.open(destination)
            stage = 3
            ticks = 0
        } else if (stage === 3 && !pane.listInFlight && pane.path === destination) {
            // P must offer the link flyout in an empty destination as well as over a row.
            var linkAction = Keymap.lookup(Qt.Key_P, "P", Qt.ShiftModifier, "listing")
            pane.act(linkAction)
            log((pane.contextMenu().opened && pane.contextMenu().submenuOpen ? "PASS" : "FAIL")
                + " paste-as-destination action=" + linkAction + " opened=" + pane.contextMenu().opened
                + " flyout=" + pane.contextMenu().submenuOpen + " messages=" + JSON.stringify(messages))
            pane.contextMenu().close()
            if (action === "pasteas") {
                pane.act("pasteAs")
                stage = 12
                ticks = 0
                return
            }
            // Positive control: the clipboard filled by this window reaches the real collision
            // and transfer path, proving the fresh-window failure is not a broken backend.
            pane.act("paste")
            log((pane.collide.pending ? "PASS" : "FAIL") + " local-paste-asks-for-files pending="
                + JSON.stringify(pane.collide.pending))
            stage = 4
            ticks = 0
        } else if (stage === 4 && ticks >= 10) {
            log((pane.total === 2 ? "PASS" : "FAIL") + " local-paste-lands-files total=" + pane.total)
            log("DONE action=" + action)
            quit()
        } else if (stage === 12 && pane.menuActions.ready && pane.contextMenu().submenuOpen) {
            pane.contextMenu().chooseSub("pasteLink")
            stage = 13
            ticks = 0
        } else if (stage === 13 && ticks >= 10) {
            log((pane.total === 3 || pane.collide.pending ? "PASS" : "FAIL")
                + " hidden-paste-as-links total=" + pane.total + " messages=" + JSON.stringify(messages))
            if (pane.total !== 3 && !pane.collide.pending) pane.pasteLink("relative", null)
            stage = 14
            ticks = 0
        } else if (stage === 14 && ticks >= 10) {
            log((pane.total === 3 ? "PASS" : "FAIL") + " direct-paste-link-control total=" + pane.total)
            log("DONE action=" + action)
            quit()
        }
    }
}
