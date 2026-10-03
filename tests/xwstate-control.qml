import QtQuick
import Quickshell
import Quickshell.Io
import "." as Flea
import "js/ClipMarks.js" as ClipMarks
import "js/Tabs.js" as Tabs

Item {
    id: root
    property var view: null
    // Test-only controls in a private copy of the shipped boot entry. Product objects,
    // action routing, backend processes and reply handlers remain the shipped ones.
    Component.onCompleted: console.log("HUNT pid=" + Quickshell.processId)
    IpcHandler {
        target: "hunt"
        function ready(): bool {
            var view = root.view
            return !!view && view.initialized && !view.currentPane.listInFlight
                && view.currentPane.total >= 2 && view.currentPane.rows.length >= 2
        }
        function selectSource(): bool { root.view.currentPane.act("toggleSelect"); return true }
        function cutSource(): bool { root.view.currentPane.act("cut"); return true }
        function pasteCut(): bool { root.view.currentPane.act("paste"); return true }
        function undoLast(): bool { root.view.currentPane.act("undo"); return true }
        function newFolder(): bool { root.view.currentPane.act("newFolder"); return true }
        function closeTab(): bool { root.view.currentPane.act("tabClose"); return true }
        function changeKeys(): bool { Flea.ViewState.changeSetting("keys", "windows"); return true }
        function changeFavourites(): bool {
            Flea.ViewState.changeSetting("places.favourites", [{label: "Shared", path: "/tmp/shared"}])
            return true
        }
        function seedCut(): bool {
            root.view.currentPane.clipboard = {paths: [Quickshell.env("FLEA_HUNT_ROOT") + "/a/alpha.txt"], moving: true}
            return true
        }
        function receiveCursor(): bool {
            var payload = JSON.stringify(["999999", "cursor-hunt", Quickshell.env("FLEA_HUNT_ROOT") + "/a", "list", "zulu.txt"])
            return Tabs.receiveTab(root.view.currentPane, payload, -1)
        }
        function state(): string {
            var pane = root.view.currentPane
            return JSON.stringify({path: pane.path, loading: pane.listInFlight,
                clipboard: pane.clipboard, cursor: pane.cursorIndex,
                cursorName: pane.cursorRow ? pane.cursorRow.n : "",
                mark: ClipMarks.markForRow(pane, "alpha.txt", pane.clipboard),
                keys: Flea.ViewState.keysPreset,
                favourites: (Flea.ViewState.state.places || {}).favourites || [],
                message: pane.statusBar.transient_, error: pane.statusBar.transientIsError})
        }
        function close(): bool { root.view.quitBackends(); return true }
    }
}
