import QtQuick
import "js/Permissions.js" as Permissions

// Read-only menu observations: a retained asked path is not a pending read, so record the backend's receipt.
QtObject {
    id: root
    property var pane: null
    property var fleaWindow: null
    property var shebangReply: ({})
    property var shebangLastReply: ({})

    property Connections replies: Connections {
        target: root.pane ? root.pane.backend : null
        function onShebang(path, hasShebang, id) {
            var reply = {path: path, hasShebang: hasShebang, id: id}
            root.shebangLastReply = reply
            if (Permissions.landsShebang(path, id, root.pane.shebangAsked, root.pane.shebangId))
                root.shebangReply = reply
        }
    }

    function state() {
        var menu = root.pane.contextMenu()
        return JSON.stringify({opened: menu.visible, entries: menu.entries, cursor: menu.cursor,
            snapshotReady: root.pane.menuActions.ready, snapshotId: root.pane.menuActions.requestId,
            shebangAsked: root.pane.shebangAsked, shebangHas: root.pane.rowHasShebang,
            shebangId: root.pane.shebangId, shebangReply: root.shebangReply, shebangLastReply: root.shebangLastReply,
            submenu: menu.submenuOpen, submenuCursor: menu.submenuCursor, submenuEntries: menu.submenuEntries,
            frame: root.fleaWindow.rectOf(menu.frameItem), flyout: root.fleaWindow.rectOf(menu.submenuFrameItem),
            workArea: menu.workArea, forHeader: menu.forHeader, forRail: menu.forRail, hasRow: menu.hasRow})
    }
}
