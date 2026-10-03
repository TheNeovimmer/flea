import QtQml
import Quickshell
import Quickshell.Io

// Only a validated tab's matching lift acknowledgment closes its source; the window supplies Tabs because qs: cannot reach ui/js.
QtObject {
    id: root

    property var tabBar: null
    property var view: null
    property var panes: []
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
        if (!root.tabBar || !root.tabs) return false
        var lift = root.tabs.liftFor(root.tabBar.outstandingLifts, token)
        if (!lift || !root.tabs.ackCloses(lift.token, token, lift.liftedAt, Date.now())) return false
        if (root.tabs.resolveMovedTab(lift.pane, lift.identity) < 0) return false
        lift.taken = true
        root.tabBar.drainLifts()
        root.traceTab("taken-recv", "token=" + String(token) + " result=accepted")
        return true
    }

    property string launchPid: Quickshell.env("FLEA_TAB_SOURCE_PID") || ""
    property string launchToken: Quickshell.env("FLEA_TAB_TOKEN") || ""
    property string launchPath: Quickshell.env("FLEA_PATH") || ""
    function openedLaunch(path) {
        if (path !== root.launchPath || !/^[0-9]+$/.test(root.launchPid) || !root.launchToken || !root.tabBar) return
        root.tabBar.sendTaken(root.launchPid, root.launchToken)
        root.launchToken = ""
    }
    property Connections primaryAck: Connections {
        target: root.panes.length > 0 ? root.panes[0] : null
        function onOpened(path) { root.openedLaunch(path) }
    }
    property Connections secondaryAck: Connections {
        target: root.panes.length > 1 ? root.panes[1] : null
        function onOpened(path) { root.openedLaunch(path) }
    }
}
