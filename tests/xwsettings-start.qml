import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    readonly property int pollMs: 50
    readonly property int deadlineMs: 30000
    readonly property int expectedTotal: 3
    readonly property int heldCursor: 1
    readonly property bool staying: Quickshell.env("PROBE_ROLE") === "A"
    property bool captured: false
    property bool checking: false
    property var heldPane: null
    property var heldFocus: null
    property int heldLists: 0
    property int settles: 0
    property var failures: []
    readonly property var body: bodyLoader.item
    readonly property var stateHelper: Qt.createComponent("file://" + Quickshell.env("PROBE_STATE_HELPER")).createObject(root)
    readonly property var sharedState: root.stateHelper.sharedState

    function check(label, ok) {
        if (!ok) root.failures.push(label)
        console.log("PROBE " + (ok ? "PASS " : "FAIL ") + label)
    }
    FloatingWindow {
        id: win
        implicitWidth: 900
        implicitHeight: 600
        function centreOf(item) { return "" }
        function rectOf(item) { return "" }
        function boxOf(item) { return "" }
        Loader {
            id: bodyLoader
            anchors.fill: parent
            focus: true
            Component.onCompleted: setSource("file://" + Quickshell.env("PROBE_BODY"), { host: win })
        }
    }
    property var observer: Connections {
        target: root.sharedState.settler
        function onStarted() {
            if (root.captured) root.settles += 1
        }
    }
    property var drainObserver: Connections {
        target: root.body ? root.body.currentPane.backend : null
        function onQuitReady() { console.log("PROBE " + Quickshell.env("PROBE_ROLE") + " backend drained") }
    }
    property var announce: Process {
        command: ["touch", Quickshell.env("PROBE_READY")]
    }
    property var arrival: Process {
        command: ["sh", "-c", "while [ ! -e \"$PROBE_DONE\" ]; do sleep \"$PROBE_POLL_S\"; done"]
        onExited: root.checking = true
    }
    property var done: Timer {
        interval: root.pollMs
        repeat: true
        running: true
        onTriggered: {
            if (!root.body) return
            var pane = body.currentPane
            if (body.closing || pane.listInFlight || pane.total !== root.expectedTotal
                    || root.sharedState.writeBook.inflight.length > 0 || root.sharedState.settler.running
                    || root.sharedState.settleMode.length > 0 || root.sharedState.settleDirty) return
            if (!root.staying) {
                console.log("PROBE B drained path=" + pane.path)
                body.quitBackends()
                return
            }
            if (!root.captured) {
                pane.cursorIndex = root.heldCursor
                pane.listArea.forceActiveFocus()
                win.contentItem.Window.window.requestActivate()
                if (!win.contentItem.Window.window.activeFocusItem) return
                root.heldPane = pane
                root.heldFocus = win.contentItem.Window.window.activeFocusItem
                root.heldLists = pane.backend.listRequests
                root.captured = true
                console.log("PROBE A ready focus=" + root.heldFocus + " cursor=" + pane.cursorIndex)
                announce.running = true
                arrival.running = true
                return
            }
            if (!root.checking || root.settles === 0) return
            // Sample ui.json: {"lastPath":"/files-b"} proves A read B's startup write before checking its pane.
            var stored = JSON.parse(root.sharedState.store.text())
            if (stored.lastPath !== Quickshell.env("PROBE_OTHER_PATH")) return
            root.check("second startup keeps A's pane", pane === root.heldPane)
            root.check("second startup keeps A's focus item", win.contentItem.Window.window.activeFocusItem === root.heldFocus)
            root.check("second startup keeps A's cursor", pane.cursorIndex === root.heldCursor)
            root.check("second startup keeps A's path", pane.path === Quickshell.env("FLEA_PATH"))
            root.check("second startup never relists A", pane.backend.listRequests === root.heldLists)
            console.log("PROBE A done failures=" + root.failures.length + " settles=" + root.settles)
            body.quitBackends()
        }
    }
    property var backstop: Timer {
        interval: root.deadlineMs
        running: true
        onTriggered: {
            console.log("PROBE FAIL startup stalled role=" + Quickshell.env("PROBE_ROLE"))
            body.quitBackends()
        }
    }
}
