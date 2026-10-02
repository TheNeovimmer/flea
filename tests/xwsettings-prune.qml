import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    readonly property int pollMs: 50
    readonly property int deadlineMs: 30000
    readonly property string refusedPatch: '{"columns":["name","size","bogus"],"density":"normal"}'
    property bool queued: false
    property int pruneRuns: 0

    Component.onCompleted: ViewState.applyShared("{}")

    property var arrival: Process {
        command: ["sh", "-c", "while [ ! -e \"$PROBE_ENTERED\" ]; do sleep \"$PROBE_POLL_S\"; done"]
        running: true
        onExited: {
            ViewState.unsaved = JSON.parse(root.refusedPatch)
            ViewState.writeBook = { saved: "", inflight: root.refusedPatch, pending: "", start: "" }
            ViewState.wrote(2)
            ViewState.settleNext()
            console.log("PROBE busy-kept=" + ViewState.pruneQueued)
            console.log("PROBE busy-inflight=" + ViewState.pruneInflight)
            console.log("PROBE busy-running=" + ViewState.settler.running)
            root.queued = true
            release.running = true
        }
    }
    property var release: Process {
        command: ["sh", "-c", "printf 'land\\n' > \"$PROBE_GATE\""]
    }
    property var observer: Connections {
        target: ViewState.settler
        function onStarted() {
            if (ViewState.settleMode === "prune") root.pruneRuns += 1
        }
    }
    property var done: Timer {
        interval: root.pollMs
        repeat: true
        running: true
        onTriggered: {
            if (!root.queued || root.pruneRuns === 0 || ViewState.settler.running
                    || ViewState.settleMode.length > 0 || ViewState.writeBook.inflight.length > 0
                    || ViewState.patch() !== "{}") return
            console.log("PROBE drained runs=" + root.pruneRuns + " inflight=" + ViewState.pruneInflight
                        + " queued=" + ViewState.pruneQueued + " patch=" + ViewState.patch())
            Qt.quit()
        }
    }
    property var backstop: Timer {
        interval: root.deadlineMs
        running: true
        onTriggered: {
            console.log("PROBE stalled runs=" + root.pruneRuns + " inflight=" + ViewState.pruneInflight
                        + " queued=" + ViewState.pruneQueued + " patch=" + ViewState.patch())
            Qt.quit()
        }
    }
}
