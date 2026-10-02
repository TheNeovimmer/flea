//@ pragma ShellId flea-pane-states-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/pane-states.sh's harness: at most one pane-state overlay draws per listing state.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0
    property int states: 0

    function log(line) { console.log("PANESTATES " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        shell.states += 1
        if (!cond) shell.failures.push(name + " got " + detail)
    }
    function isType(o, name) {
        var s = String(o)
        return s.indexOf(name) === 0 || s.indexOf("QQuick" + name) === 0
    }
    function findFirst(item, name) {
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o !== item && shell.isType(o, name)) return o
            var kids = (o && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return null
    }

    // The smallest stub PaneStates binds against: geometry, state and the swap flag.
    Item {
        id: stubPane
        property string listingState: "loading"
        property string stateMessage: ""
        property int total: 0
        property string filterQuery: ""
        property int shownTotal: 0
        property string searchMode: ""
        property int lockedMode: 0
        property bool listInFlight: true
        property string viewMode: "list"
        property var columnsArea: null
        property var swap: ({ fellBack: false })
        Item {
            id: stubSlot
            x: 0
            y: 100
            width: 600
            height: 400
        }
        property var listSlot: stubSlot
        Item {
            id: stubHeader
            y: 60
        }
        property var header: stubHeader
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        Flea.PaneStates {
            id: states
            pane: stubPane
        }
    }

    function crawlShown() {
        var load = shell.findFirst(states, "LoadingState")
        return load ? load.visible : false
    }
    function markName() {
        var glyph = shell.findFirst(states.messageItem, "Glyph")
        return glyph ? String(glyph.name) : ""
    }
    function markShown() {
        var glyph = shell.findFirst(states.messageItem, "Glyph")
        return glyph ? glyph.visible : false
    }
    // Empty hero, crawl and sentence: the gate is that no state lights two of them.
    function overlays() {
        var n = 0
        if (states.emptyItem.visible) n += 1
        if (shell.crawlShown()) n += 1
        if (states.messageItem.visible) n += 1
        return n
    }
    function describe() {
        return "empty=" + states.emptyItem.visible + " crawl=" + shell.crawlShown()
            + " msg=" + states.messageItem.visible + " mark=" + shell.markName()
            + "/" + shell.markShown()
    }
    // One listing state per call, so every check reads the bindings the state settled.
    function setState(state, message, total, query, shown, mode) {
        stubPane.listingState = state
        stubPane.stateMessage = message
        stubPane.total = total
        stubPane.filterQuery = query
        stubPane.shownTotal = shown
        stubPane.lockedMode = mode
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function advance() {
        shell.ticks += 1
        if (shell.ticks < 2) return
        if (shell.phase === 0) {
            shell.setState("loading", "", 0, "", 0, 0)
            shell.check("loading-single", shell.overlays() === 1 && shell.crawlShown(), shell.describe())
            shell.phase = 1
        } else if (shell.phase === 1) {
            shell.setState("waiting", "That folder is not responding.", 0, "", 0, 0)
            shell.check("waiting-single", shell.overlays() === 1 && !shell.crawlShown()
                && states.messageItem.visible, shell.describe())
            shell.check("waiting-alert", shell.markShown() && shell.markName() === "alert"
                && states.messageItem.message === "That folder is not responding.", shell.describe())
            shell.phase = 2
        } else if (shell.phase === 2) {
            shell.setState("error", "That directory could not be read.", 0, "", 0, 0)
            shell.check("error-single", shell.overlays() === 1 && !shell.crawlShown()
                && states.messageItem.visible, shell.describe())
            shell.check("error-alert", shell.markShown() && shell.markName() === "alert", shell.describe())
            shell.phase = 3
        } else if (shell.phase === 3) {
            shell.setState("locked", "Permission denied", 0, "", 0, 16877)
            shell.check("locked-single", shell.overlays() === 1 && !shell.crawlShown()
                && states.messageItem.visible, shell.describe())
            shell.check("locked-mark", shell.markShown() && shell.markName() === "lock", shell.describe())
            shell.phase = 4
        } else if (shell.phase === 4) {
            stubPane.listInFlight = false
            shell.setState("empty", "", 0, "", 0, 0)
            shell.check("empty-single", shell.overlays() === 1 && states.emptyItem.visible, shell.describe())
            shell.phase = 5
        } else if (shell.phase === 5) {
            shell.setState("ready", "", 5, "zzz", 0, 0)
            shell.check("nomatch-single", shell.overlays() === 1 && states.messageItem.visible, shell.describe())
            shell.check("nomatch-mark", shell.markShown() && shell.markName() === "search", shell.describe())
            shell.phase = 6
        } else if (shell.phase === 6) {
            shell.setState("ready", "", 5, "", 0, 0)
            shell.check("ready-quiet", shell.overlays() === 0, shell.describe())
            shell.phase = 7
        } else if (shell.phase === 7) {
            for (var i = 0; i < shell.failures.length; i++) shell.log("FAIL " + shell.failures[i])
            if (shell.failures.length === 0) shell.log("PASS states=" + shell.states + " overlays-gated")
            shell.log("DONE failures=" + shell.failures.length)
            shell.phase = 8
            shell.quit()
        }
    }
}
