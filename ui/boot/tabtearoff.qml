import QtQuick
import Quickshell
import Quickshell.Wayland

// The tear-off catcher: one transparent Bottom-layer panel per screen, alive only
// while the source tab drag is out (the Loader owning this unloads on every end
// path). A drop here runs in the source process, so it reports exactly, where a
// cross-process drop action reports Ignore for every landing. Below windows and
// above the wallpaper, so only empty desktop reaches it. The boot directory cannot
// reach ui/js through qs:, so the strip hands the tab MIME in with the Loader.
Item {
    id: root

    // Loader assigns this after creation, so required can never hold here.
    property var tabBar: null
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
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.exclusiveZone: 0
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            DropArea {
                anchors.fill: parent
                keys: [root.tabMime]
                onDropped: function (drop) {
                    // A drop landing before onLoaded assigned tabBar is dropped.
                    if (root.tabBar !== null && drop.getDataAsString(root.tabMime) !== "")
                        root.tabBar.tearOffAt()
                }
            }
            Keys.onEscapePressed: { if (root.tabBar !== null) root.tabBar.cancelOut() }
        }
    }
}
