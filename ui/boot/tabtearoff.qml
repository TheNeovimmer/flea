import QtQuick
import Quickshell
import Quickshell.Wayland

// The tear-off catcher: one transparent Bottom-layer panel per screen, alive only while the source
// tab drag is out; the Loader that owns it unloads it on every end path.
Item {
    id: root

    // Loader assigns this after creation, so required can never hold here.
    property var tabBar: null
    // The boot directory cannot reach ui/js through qs:, so the strip hands the tab MIME in.
    property string tabMime: ""

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            WlrLayershell.namespace: "flea-tab-tearoff"
            WlrLayershell.layer: WlrLayer.Bottom
            // Ignore reserved bars so catcher-local origin is exactly the screen origin.
            exclusionMode: ExclusionMode.Ignore
            // Hyprland focuses an interactive layer on map and releases held buttons,
            // stealing drag focus from the target window. Escape stays with Qt's source.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            DropArea {
                anchors.fill: parent
                keys: [root.tabMime]
                onEntered: function (drag) {
                    if (root.tabBar !== null)
                        root.tabBar.traceTab("catcher-enter", "global=" + (modelData.x + drag.x) + "," + (modelData.y + drag.y))
                }
                onDropped: function (drop) {
                    // The full-screen catcher starts at the screen's compositor position.
                    if (root.tabBar !== null && drop.getDataAsString(root.tabMime) !== "") {
                        drop.accept(Qt.MoveAction)
                        root.tabBar.catcherDrop(modelData.x + drop.x, modelData.y + drop.y)
                    }
                }
            }
        }
    }
}
