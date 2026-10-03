import QtQuick
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
    readonly property int dragTo: root.dropAt > root.dragFrom ? root.dropAt - 1 : root.dropAt
    readonly property var layoutOrder: {
        var order = []
        for (var i = 0; i < root.tabCount; i++) order.push(i)
        if (root.dragFrom >= 0 && root.dropAt >= 0)
            TabMove.reorder(order, root.dragFrom, root.dragTo, root.currentIndex)
        return order
    }

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

    Item {
        id: strip
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing.rowPaddingX
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.tabCount * root.tabWidth + Theme.hitMin

        Repeater {
            id: repeater
            model: root.open ? root.tabCount : 0
            delegate: Item {
                id: tab
                required property int index
                readonly property int slot: root.layoutOrder.indexOf(tab.index)
                x: tab.slot * root.tabWidth
                width: root.tabWidth
                height: strip.height
                // The tab under the pointer draws ghosted while its drag runs.
                opacity: root.dragFrom === tab.index ? Theme.disabledOpacity : 1

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
                    visible: tab.slot < root.tabCount - 1 && !tab.current
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

                // A left-button drag reorders; a press without a move still taps above.
                // A file drag never enters here, so the hover switch answers only files.
                DragHandler {
                    acceptedButtons: Qt.LeftButton
                    target: null
                    function updateDrop() {
                        // Scene coordinates stay fixed while the preview moves the delegate beneath the pointer.
                        var pos = strip.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y)
                        root.dragMoved(pos.x)
                    }
                    onActiveChanged: {
                        // The threshold move precedes activation, so its centroid must be sampled here.
                        if (active) {
                            root.dragStarted(tab.index)
                            updateDrop()
                        }
                    }
                    onCentroidChanged: if (active) updateDrop()
                    onGrabChanged: function (transition, point) {
                        if (transition !== PointerDevice.UngrabExclusive) return
                        // Qt deactivates before updating the centroid on release; the event point holds the release position.
                        var pos = strip.mapFromItem(null, point.scenePosition.x, point.scenePosition.y)
                        root.dragMoved(pos.x)
                        root.dragFinished()
                    }
                    onCanceled: { root.dragFrom = -1; root.dropAt = -1 }
                }
            }
        }

        Item {
            id: addButton
            x: root.tabCount * root.tabWidth
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

    // Tabs040 callout 1: the accent bar borders the ghost's leading edge through the strip's height.
    Rectangle {
        visible: root.dragFrom >= 0 && root.dropAt >= 0
        x: strip.x + root.dragTo * root.tabWidth - Theme.spacing.hairline
        width: 2 * Theme.spacing.hairline
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: Theme.color.accent
    }
}
