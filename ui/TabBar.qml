import QtQuick
import Quickshell
import Quickshell.Io
import "." as Flea
import "js/DragOut.js" as DragOut
import "js/Tabs.js" as Tabs
import "js/TabMove.js" as TabMove

// The window's tab strip. Hidden with no height until a second tab exists, so the default window
// keeps the chrome-to-list layout every existing click test and the first-paint path already have.
Item {
    id: root

    property var pane: null
    enabled: root.pane !== null && root.pane.enabled

    // pane.tabs is a replaced JS object, so these bindings have to read it directly; a helper
    // call alone would not re-run when t opens a second tab.
    readonly property var tabs: pane ? pane.tabs : null
    readonly property string path: pane ? pane.path : ""
    readonly property int tabCount: root.tabs && root.tabs.items && root.tabs.items.length > 0 ? root.tabs.items.length : 1
    readonly property int currentIndex: root.tabs ? root.tabs.index : 0
    readonly property bool open: root.tabCount > 1
    readonly property int tabWidth: {
        var n = Math.max(1, root.tabCount)
        var avail = Math.max(0, root.width - Theme.hitMin)
        var maxW = Math.round(Theme.font.caption * 12) + Theme.hitMin + 2 * Theme.spacing.rowPaddingX
        var minW = Theme.hitMin * 3
        return Math.round(Math.max(minW, Math.min(maxW, avail / n)))
    }

    // How long a drag rests on a tab before the tab is selected: long enough to cross it on the way elsewhere.
    readonly property int hoverSwitchMs: 400

    // Tabs040 callout 1: a tab drag reorders the strip. dragFrom is the tab
    // held, dropAt the insertion point (0..tabCount) its pointer names.
    property int dragFrom: -1
    property int dropAt: -1

    // xw6: a tab dragged past the window's edge leaves as a platform drag. outMime
    // carries only the private tab type, outPid names this process for the taken ack,
    // outToken names the lift the ack closes, outOutside tracks the pointer against
    // the window, and outActive owns the gesture from the first step outside until
    // the drop answers. ownAccepted marks an own-strip drop that already reordered.
    // pendingTab holds a foreign drop while the backend validates its folder.
    property var outMime: ({})
    property bool outActive: false
    property bool outOutside: false
    property bool outRefused: false
    property int outIndex: -1
    property string outPath: ""
    property string outPid: ""
    property string outToken: ""
    property bool ownAccepted: false
    property var pendingTab: null
    // The lift outlives the drag's own end, until the taken ack or this wait ends.
    property int ackWaitMs: Tabs.ACK_WAIT_MS
    property double ackLiftedAt: 0
    property var takenQueue: []
    // Stage trace, on only with FLEA_TRACE_TABDRAG=1; read once, silent otherwise.
    readonly property bool tabTrace: Quickshell.env("FLEA_TRACE_TABDRAG") === "1"
    function traceTab(stage, detail) { if (root.tabTrace) console.log("TABDRAG " + stage + " pid=" + Quickshell.processId + " " + detail) }

    Timer {
        id: ackTimer
        interval: root.ackWaitMs
        onTriggered: root.clearAck()
    }

    Process {
        id: takenAck
        onExited: function (exitCode, exitStatus) {
            root.traceTab("taken-exit", "code=" + exitCode)
            root.pumpTaken()
        }
    }

    Drag.dragType: Drag.Automatic
    // Move only, and only the private tab type: a foreign app refuses it, so a tab
    // can never move or copy the folder on disk. No proposedAction: a cross-process
    // drop answers Ignore on Hyprland, and that answer decides nothing.
    Drag.supportedActions: Qt.MoveAction
    Drag.mimeData: root.outMime
    Drag.onDragFinished: function (dropAction) { root.outFinished(dropAction) }

    function dragStarted(index) {
        root.dragFrom = index
        root.dropAt = index < 0 ? -1 : index + 1
    }
    function dragMoved(x) {
        if (root.dragFrom < 0)
            return
        root.dropAt = TabMove.insertionAt(x, root.tabWidth, root.tabCount)
    }
    function dragFinished() {
        if (root.dragFrom >= 0 && root.dropAt >= 0 && root.pane) {
            var at = root.dropAt
            Tabs.move(root.pane, root.dragFrom, at > root.dragFrom ? at - 1 : at)
        }
        root.dragFrom = -1
        root.dropAt = -1
    }

    // The lift fixes the payload; a rename open refuses the way out, not the reorder.
    // A lone tab never lifts: the strip is hidden for it, and moving a window's only
    // tab is moving the window.
    function tabLiftBegan(index) {
        if (!Tabs.canLift(root.pane)) {
            root.dragFrom = -1
            root.dropAt = -1
            return
        }
        root.dragStarted(index)
        root.outIndex = index
        var info = Tabs.tabInfo(root.pane, index)
        root.outPath = info ? info.path : ""
        root.outPid = String(Quickshell.processId)
        root.outToken = Tabs.newToken()
        // A new lift supersedes any ack still waited on.
        ackTimer.stop()
        root.ackLiftedAt = 0
        root.outMime = Tabs.tabDragMime(root.pane, index, root.outPid, root.outToken)
        root.outOutside = false
        root.outRefused = false
        root.ownAccepted = false
    }

    // Inside the strip only the reorder runs. Past the window's edge the platform drag
    // takes over; the reorder state freezes until the drop answers.
    function tabLiftMoved(stripX, winX, winY) {
        root.dragMoved(stripX)
        if (root.parent)
            root.outOutside = winX < 0 || winY < 0 || winX > root.parent.width || winY > root.parent.height
        if (root.outOutside && !root.outActive && root.outMime[Tabs.TAB_MIME]) {
            var refusal = Tabs.tearRefusal(root.pane)
            if (refusal.length > 0) {
                if (!root.outRefused && root.pane)
                    root.pane.message(refusal, false)
                root.outRefused = true
                return
            }
            root.outActive = true
            root.Drag.active = true
            root.traceTab("drag-start", "index=" + root.outIndex + " path=" + root.outPath + " mime=" + Object.keys(root.outMime).join(",") + " dragType=" + root.Drag.dragType)
        }
    }

    // The DragHandler's own release: a platform gesture in flight owns the ending, so no
    // reorder runs under it. The reset still runs, or the ghost would stand past the drop.
    function tabLiftEnded() {
        if (root.outActive || root.ownAccepted) {
            root.dragFrom = -1
            root.dropAt = -1
            return
        }
        root.dragFinished()
    }

    // The lift survives the drag's end: the ack lands after the drop action whatever it
    // reports, so clearing here would orphan it. An own-strip reorder consumed its lift.
    function holdAck() {
        root.ackLiftedAt = Date.now()
        ackTimer.restart()
    }
    function clearAck() {
        ackTimer.stop()
        root.outToken = ""
        root.outIndex = -1
        root.outPath = ""
        root.ackLiftedAt = 0
    }

    // The drop action of a cross-process drag decides nothing: on Hyprland it is always
    // Ignore, which means do nothing. A move closes here only through the taken ack, a
    // tear-off only through the panel drop, and a cancel changes nothing. An own-strip
    // drop already reordered, so this only clears, and the late handler release behind
    // it cannot reorder twice. Every end path runs here, so the panels go with it.
    function outFinished(dropAction) {
        root.traceTab("drag-finished", "action=" + dropAction)
        var consumed = root.ownAccepted
        root.dragFrom = -1
        root.dropAt = -1
        root.outActive = false
        root.ownAccepted = false
        if (consumed)
            root.clearAck()
        else if (root.outToken.length > 0)
            root.holdAck()
    }

    // The panel's Escape: ends the gesture with no move and no tear-off, the tab stays.
    // No drop follows, so no ack ever comes; the lift waits out the timer instead.
    function cancelOut() {
        if (!root.outActive)
            return
        root.Drag.cancel()
        root.dragFrom = -1
        root.dropAt = -1
        root.outActive = false
        root.ownAccepted = false
        if (root.outToken.length > 0)
            root.holdAck()
    }

    // The tear-off catcher answers in this process, so it reports exactly: open the new
    // window on the folder and close the lifted tab. The window lands where the
    // compositor puts it; Flea names no position.
    function tearOffAt() {
        if (root.outPath.length === 0)
            return
        Quickshell.execDetached([Quickshell.env("FLEA_BIN") || "flea", root.outPath])
        if (root.pane)
            Tabs.closeTabAfterMove(root.pane, Tabs.resolveMovedTab(root.pane, root.outIndex, root.outPath))
        root.dragFrom = -1
        root.dropAt = -1
        root.outActive = false
        root.ownAccepted = false
        root.clearAck()
    }

    // A tab from another Flea window lands at the drop position. Own drags reach here
    // only out and back onto this strip, where the reorder owns them; the per-tab file
    // areas refuse the tab MIME outright.
    function tabEnterOk(drag) {
        var ok = Tabs.enterAccepts(drag.formats, drag.getDataAsString(Tabs.TAB_MIME), undefined, root.pane ? Tabs.canReceive(root.pane) : false, root.outActive)
        root.traceTab("enter-strip", "formats=" + String(drag.formats) + " ok=" + ok)
        return ok
    }

    // A foreign drop waits on the backend: the folder must exist and be a directory
    // before this window opens a tab and acks. The peek asks first 2 with no hidden
    // flags, a quad no other client uses, so the reply answers this drop alone.
    function acceptTabDrop(payload, info, at) {
        if (!root.pane || !Tabs.canReceive(root.pane))
            return
        root.pendingTab = { payload: payload, pid: info.pid, token: info.token, path: info.path, at: at }
        root.traceTab("peek-sent", "path=" + info.path + " first=2 hidden=false")
        root.pane.backend.peek(info.path, 2, false, false)
    }

    // The taken ack, after this window validated the folder and opened the tab. A drop
    // never heard about sends nothing, so the source keeps its tab.
    function sendTaken(pid, token) {
        root.traceTab("taken-sent", "target=" + pid + " token=" + token)
        root.takenQueue = root.takenQueue.concat([{ pid: String(pid), token: String(token) }])
        root.pumpTaken()
    }
    // One Process runs one call, so overlapping acks queue behind it instead of vanishing inside execDetached.
    function pumpTaken() {
        if (takenAck.running || root.takenQueue.length === 0)
            return
        var next = root.takenQueue[0]
        root.takenQueue = root.takenQueue.slice(1)
        takenAck.command = ["qs", "ipc", "--pid", next.pid, "call", "fleatab", "taken", next.token]
        takenAck.running = true
    }

    Connections {
        target: root.pane ? root.pane.backend : null
        function onPeeked(path, hidden, total, rows, readFailed, mode, hiddenLast, first) {
            var pending = root.pendingTab
            if (!pending || path !== pending.path || hidden !== false || hiddenLast !== false || first !== 2)
                return
            root.traceTab("peek-answer", "path=" + path + " failed=" + readFailed + " total=" + total)
            root.pendingTab = null
            if (readFailed) {
                if (root.pane)
                    root.pane.message("That folder is no longer there.", false)
                root.traceTab("receive", "ok=false refused-missing path=" + path)
                return
            }
            var received = root.pane && Tabs.receiveTab(root.pane, pending.payload, pending.at)
            root.traceTab("receive", "ok=" + !!received + " path=" + pending.path + " at=" + pending.at)
            if (received)
                root.sendTaken(pending.pid, pending.token)
        }
    }

    visible: root.open
    implicitHeight: Theme.chromeHeight
    height: visible ? implicitHeight : 0

    function itemAt(index) {
        return repeater.itemAt(index)
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.surface
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.spacing.hairline
        color: Theme.color.foreground
        opacity: 0.12
    }

    Row {
        id: strip
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing.rowPaddingX
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        Repeater {
            id: repeater
            model: root.open ? root.tabCount : 0
            delegate: Item {
                id: tab
                required property int index
                width: root.tabWidth
                height: strip.height
                // The tab under the pointer draws ghosted while its drag runs.
                opacity: root.dragFrom === tab.index ? 0.55 : 1.0

                readonly property bool current: root.currentIndex === tab.index
                // Every input named, so the label re-reads when a tab opens or the pane navigates.
                readonly property string title: Tabs.label(
                    Tabs.pathAt(root.tabs, root.currentIndex, tab.index, root.path),
                    pane ? pane.home : "")

                Accessible.role: Accessible.PageTab
                Accessible.name: tab.title
                Accessible.onPressAction: if (pane) Tabs.selectAt(pane, tab.index)

                HoverHandler { cursorShape: Qt.PointingHandCursor }

                // GM's ruling: a drag resting on a tab selects it so the drop can land in that tab's
                // listing, and a drop on the tab itself lands there too, by path, see ui/DropInto.qml.
                Flea.DropInto {
                    anchors.fill: parent
                    pane: root.pane
                    enabled: DragOut.searchTabEnabled(root.pane ? root.pane.searchMode : "", tab.current)
                    switchesOnHover: true
                    refuseLoading: DragOut.refuseLoading(root.pane && root.pane.listInFlight, true, tab.current)
                    // The pane's drop path, not its drawn one: a tab selected by the hover switch is
                    // current before its listing lands, and until then pane.path is the tab left behind.
                    // Sidebar040: a history is not a directory, so a drop onto the tab standing on it
                    // is refused rather than landing in the root it stands on.
                    dest: root.pane && root.pane.recentMode.length > 0 && tab.current ? ""
                        : Tabs.pathAt(root.tabs, root.currentIndex, tab.index,
                                      root.pane ? root.pane.dropPath : root.path)
                    // Unknown while the listed reply is still out, because dirDev is then the directory a hover switch just left; unknown makes verbFor copy, never a move that turns into a cross-device delete.
                    destDev: Tabs.devAt(root.tabs, root.currentIndex, tab.index,
                                        root.pane && root.pane.backend && !root.pane.listInFlight ? root.pane.backend.dirDev : 0)
                    // Only an accepted enter arms the switch: Qt emits entered before it reads accepted,
                    // and a refused drag gets no exited, so the timer would otherwise never stop.
                    onEntered: function (drag) { if (drag.accepted) hoverSwitch.restart() }
                    onExited: hoverSwitch.stop()
                    onDropped: hoverSwitch.stop()
                }
                Timer {
                    id: hoverSwitch
                    interval: root.hoverSwitchMs
                    onTriggered: if (root.pane && !tab.current) Tabs.selectAt(root.pane, tab.index)
                }

                Rectangle {
                    anchors.fill: parent
                    color: tab.current ? Theme.color.background : "transparent"
                }

                // Flush on the strip's own bottom edge, replacing it rather than sitting inside the
                // plate: rendered in Quickshell on a low-chroma theme, an inset edge vanishes.
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: Theme.accentEdge
                    color: Theme.color.accent
                    visible: tab.current
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.spacing.hairline
                    height: parent.height * 0.45
                    color: Theme.color.foreground
                    opacity: 0.12
                    visible: tab.index < root.tabCount - 1 && !tab.current
                }

                Text {
                    id: titleText
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacing.rowPaddingX
                    anchors.right: closeHit.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: tab.title
                    color: tab.current ? Theme.color.foreground : Theme.color.muted
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.caption
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }

                Item {
                    id: closeHit
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.hitMin
                    height: parent.height

                    // The mark never moves and its target never shrinks; only the ink answers, so a
                    // crowded strip is no harder to hit than a tidy one.
                    Flea.Glyph {
                        anchors.centerIn: parent
                        width: Theme.chromeMarkSize
                        height: Theme.chromeMarkSize
                        name: "x"
                        color: tab.current || closeHover.hovered ? Theme.color.foreground : Theme.color.muted
                    }

                    HoverHandler { id: closeHover }
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onTapped: function (eventPoint, button) {
                        if (!pane)
                            return
                        if (button === Qt.MiddleButton) {
                            Tabs.closeAt(pane, tab.index)
                            return
                        }
                        var local = closeHit.mapFromItem(tab, eventPoint.position.x, eventPoint.position.y)
                        if (local.x >= 0 && local.x <= closeHit.width && local.y >= 0 && local.y <= closeHit.height)
                            Tabs.closeAt(pane, tab.index)
                        else
                            Tabs.selectAt(pane, tab.index)
                    }
                }

                // Tabs040 callout 1: a left-button drag reorders rather than selects.
                // A press without a move still taps above, and a file drag never
                // enters here, so DropInto's hover switch answers only files.
                // xw6: past the window's edge the same gesture leaves as a platform tab drag.
                DragHandler {
                    acceptedButtons: Qt.LeftButton
                    target: null
                    onActiveChanged: {
                        if (active)
                            root.tabLiftBegan(tab.index)
                        else
                            root.tabLiftEnded()
                    }
                    onCentroidChanged: {
                        if (active) {
                            var pos = tab.mapToItem(strip, centroid.position.x, centroid.position.y)
                            var win = root.parent ? tab.mapToItem(root.parent, centroid.position.x, centroid.position.y) : pos
                            root.tabLiftMoved(pos.x, win.x, win.y)
                        }
                    }
                }
            }
        }

        Item {
            id: addButton
            width: Theme.hitMin
            height: strip.height
            Accessible.role: Accessible.Button
            Accessible.name: "New tab"
            Accessible.onPressAction: if (pane) Tabs.openNew(pane)
            HoverHandler { cursorShape: Qt.PointingHandCursor }

            Flea.Glyph {
                anchors.centerIn: parent
                width: Theme.chromeMarkSize
                height: Theme.chromeMarkSize
                name: "plus"
                color: Theme.color.muted
            }

            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: if (pane) Tabs.openNew(pane)
            }
        }
    }

    // xw6: the strip's own tab catcher. A DropArea takes no pointer input, so this
    // never blocks a tap or a reorder; it only answers the platform tab drag, at the
    // drop position, while the per-tab file areas refuse the tab MIME outright.
    DropArea {
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing.rowPaddingX
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        keys: [Tabs.TAB_MIME]
        onEntered: function (drag) {
            if (!root.tabEnterOk(drag))
                drag.accepted = false
        }
        // An own drag out and back tracks its insertion while it is over the strip.
        onPositionChanged: function (drag) {
            var info = Tabs.parseTabMime(drag.getDataAsString(Tabs.TAB_MIME))
            if (info && Tabs.isOwnTab(info) && root.outActive)
                root.dragMoved(drag.x)
        }
        onDropped: function (drop) {
            var payload = drop.getDataAsString(Tabs.TAB_MIME)
            root.traceTab("drop-strip", "empty=" + (payload.length === 0) + " len=" + payload.length)
            var info = Tabs.parseTabMime(payload)
            if (!info)
                return
            if (Tabs.isOwnTab(info)) {
                // Out and back onto its own strip: reorder in place and accept, and
                // outFinished clears behind it so the late release reorders nothing.
                if (!root.outActive)
                    return
                var from = Tabs.resolveMovedTab(root.pane, root.outIndex, root.outPath)
                var at = Tabs.dropIndexAt(drop.x, root.tabWidth, root.tabCount)
                if (root.pane && from >= 0)
                    Tabs.move(root.pane, from, at > from ? at - 1 : at)
                root.ownAccepted = true
                drop.accept(Qt.MoveAction)
                return
            }
            // The take decision answers Move at once; the peek behind it may still refuse, and then no ack goes out.
            if (Tabs.dropDecision(info, undefined, root.outActive, root.pane ? Tabs.canReceive(root.pane) : false) !== Tabs.DROP_TAKE)
                return
            drop.accept(Qt.MoveAction)
            root.acceptTabDrop(payload, info, Tabs.dropIndexAt(drop.x, root.tabWidth, root.tabCount))
        }
    }

    // The tear-off catcher lives only while this window's tab drag is out, and goes
    // with every end path through outFinished, cancelOut and tearOffAt. It loads by
    // file URL from the boot directory, beside the entries, so the startup path that
    // avoids ui/qmldir never compiles it.
    Loader {
        id: tearPanels
        active: root.outActive
        source: "file://" + Quickshell.shellDir + "/tabtearoff.qml"
        onLoaded: {
            item.tabBar = root
            item.tabMime = Tabs.TAB_MIME
        }
    }

    Component.onCompleted: Tabs.setOwnPid(Quickshell.processId)

    // Tabs040 callout 1: the accent bar where the held tab would land, flush
    // through the strip's height the way the current tab's own edge is.
    Rectangle {
        visible: root.dragFrom >= 0 && root.dropAt >= 0
        x: Theme.spacing.rowPaddingX + root.dropAt * root.tabWidth - 1
        width: 2
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: Theme.color.accent
    }
}
