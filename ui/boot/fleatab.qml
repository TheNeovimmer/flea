import QtQml
import Quickshell
import Quickshell.Io

// The taken ack a receiving Flea calls after it validated the folder and opened the
// tab: qs ipc --pid <pid> call fleatab taken <token>. A drop this window never hears
// about changes nothing here; only a matching outstanding token closes the lifted tab.
// The boot directory cannot reach ui/js through qs:, so the window hands the Tabs
// library in with the Loader. See ui/boot/shell.qml on the same rule.
QtObject {
    id: root

    property var tabBar: null
    property var view: null
    property var tabs: null
    // Stage trace, on only with FLEA_TRACE_TABDRAG=1; read once, silent otherwise.
    readonly property bool tabTrace: Quickshell.env("FLEA_TRACE_TABDRAG") === "1"
    function traceTab(stage, detail) { if (root.tabTrace) console.log("TABDRAG " + stage + " pid=" + Quickshell.processId + " " + detail) }

    property IpcHandler ack: IpcHandler {
        target: "fleatab"
        function taken(token: string): bool { return root.take(token) }
    }

    function take(token) {
        root.traceTab("taken-call", "token=" + String(token) + " outToken=" + String(root.tabBar ? root.tabBar.outToken : "") + " outActive=" + String(root.tabBar ? root.tabBar.outActive : ""))
        if (!root.tabBar || !root.view || !root.view.currentPane || !root.tabs) {
            root.traceTab("taken-refused", "reason=missing-ref")
            return false
        }
        if (!root.tabs.ackCloses(root.tabBar.outToken, token, root.tabBar.ackLiftedAt, Date.now())) {
            root.traceTab("taken-refused", "reason=" + (!root.tabs.takeToken(root.tabBar.outToken, token) ? "token-mismatch" : "expired"))
            return false
        }
        var pane = root.view.currentPane
        var index = root.tabs.resolveMovedTab(pane, root.tabBar.outIndex, root.tabBar.outPath)
        var result = root.tabs.closeTabAfterMove(pane, index)
        root.traceTab("taken-recv", "token=" + String(token) + " result=" + result)
        root.tabBar.clearAck()
        root.tabBar.outActive = false
        root.tabBar.dragFrom = -1
        root.tabBar.dropAt = -1
        root.tabBar.ownAccepted = false
        return result === "closed"
    }
}
