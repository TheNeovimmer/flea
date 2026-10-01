import QtQuick
import Quickshell
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

    // xw6: a tab dragged past the window's edge leaves as a platform drag. outMime is
    // fixed at the lift, outOutside tracks the pointer against the window, and outActive
    // owns the gesture from the first step outside until the drop answers. allowWindowClose
    // is false where the pane shares its window, so a last tab moved there is refused.
    property var outMime: ({})
    property bool outActive: false
    property bool outOutside: false
    property bool outRefused: false
    property int outIndex: -1
    property string outPath: ""
    property bool allowWindowClose: true
    signal closeRequested()

    Drag.dragType: Drag.Automatic
    // Copy and Move both offered with Copy proposed, so a foreign app takes the folder
    // reference while a Flea window takes the tab with an explicit Move accept. The source
    // closes its tab only on that Move, which is how a foreign copy keeps the tab standing.
    Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
    Drag.proposedAction: Qt.CopyAction
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
    function tabLiftBegan(index) {
        root.dragStarted(index)
        root.outIndex = index
        var info = Tabs.tabInfo(root.pane, index)
        root.outPath = info ? info.path : ""
        root.outMime = Tabs.tabDragMime(root.pane, index)
        root.outOutside = false
        root.outRefused = false
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
        }
    }

    // The DragHandler's own release: a platform gesture in flight owns the ending, so no
    // reorder runs under it. The reset still runs, or the ghost would stand past the drop.
    function tabLiftEnded() {
        if (root.outActive) {
            root.dragFrom = -1
            root.dropAt = -1
            return
        }
        root.dragFinished()
    }

    // Move means a Flea window took the tab: close it here, or close the window when it
    // was the last. Copy means a foreign app took the folder reference and the tab stays.
    // Ignore past the edge is Finder's tear-off, a new window on the folder; Ignore inside
    // is a cancel or a refused drop and changes nothing. The clear is deferred past the
    // DragHandler's own release, whichever answers first, so neither reorders under the other.
    function outFinished(dropAction) {
        if (!root.outActive)
            return
        if (dropAction === Qt.MoveAction) {
            root.finishMove()
        } else if (dropAction === Qt.IgnoreAction && root.outOutside) {
            root.tearOff()
        }
        Qt.callLater(function () { root.outActive = false })
    }

    function finishMove() {
        if (!root.pane)
            return
        var result = Tabs.closeTabAfterMove(root.pane, Tabs.resolveMovedTab(root.pane, root.outIndex, root.outPath))
        if (result === "window") {
            if (root.allowWindowClose)
                root.closeRequested()
            else
                root.pane.message("Can't close the last tab.", false)
        }
    }

    // The same launch Ctrl+N uses, on the tab's folder rather than the standing path.
    function tearOff() {
        if (root.outPath.length === 0)
            return
        Quickshell.execDetached([Quickshell.env("FLEA_BIN") || "flea", root.outPath])
        root.finishMove()
    }

    // A tab from another Flea window lands at the drop position. Own drags never reach
    // here: the reorder owns those, and the per-tab areas below refuse the tab MIME too.
    function tabEnterOk(drag) {
        var info = Tabs.parseTabMime(drag.getDataAsString(Tabs.TAB_MIME))
        if (!info || Tabs.isOwnTab(info))
            return false
        return root.pane ? Tabs.canReceive(root.pane) : false
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
        onDropped: function (drop) {
            var payload = drop.getDataAsString(Tabs.TAB_MIME)
            var info = Tabs.parseTabMime(payload)
            if (!info || Tabs.isOwnTab(info))
                return
            var at = Tabs.dropIndexAt(drop.x, root.tabWidth, root.tabCount)
            if (root.pane && Tabs.receiveTab(root.pane, payload, at))
                drop.accept(Qt.MoveAction)
        }
    }

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
