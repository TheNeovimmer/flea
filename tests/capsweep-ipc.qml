import QtQuick
import Quickshell
import Quickshell.Io

// A bounded offscreen probe distinguishes a truncated IPC answer from a truncated file read.
ShellRoot {
    id: root

    QtObject {
        id: pane
        property var columnsArea: null
        property var previewColumnItem: null
        property string dropPath: "/destination"
        property var swap: QtObject {
            property var wire: Item {
                Item {
                    id: floor
                    property string dest: pane.dropPath
                    property bool containsDrag: false
                }
            }
        }
        property var preview: QtObject {
            property bool active: true
            property string kind: "text"
            readonly property string status: textLoader.item ? textLoader.item.status : "loading"
            property int position: 0
            property int duration: 0
            property var pdfItem: null
            property bool isMedia: false
            property bool isImage: false
            function textShown() { return textLoader.item ? textLoader.item.shownText() : "" }
            function markdownView() { return "" }
            function mediaLoaded() { return false }
            function archiveNames() { return "" }
            function swapState() { return {active: true} }
        }
    }
    Loader {
        id: previewLoader
        width: 640
        height: 480
    }
    Loader {
        id: textLoader
        width: 640
        height: 480
        source: "file://" + Quickshell.env("SWEEPIPC_UI") + "/PreviewText.qml"
        onLoaded: {
            item.size = Number(Quickshell.env("SWEEPIPC_BYTES"))
            item.path = Quickshell.env("SWEEPIPC_FILE")
            item.active = true
        }
    }
    Loader {
        source: "file://" + Quickshell.env("SWEEPIPC_UI") + "/Ipc.qml"
        onLoaded: item.pane = pane
    }
    IpcHandler {
        target: "sweepipc"
        function ready(): bool { return true }
        function whole(n: int): string { return "x".repeat(n) }
        function length(n: int): int { return n }
        function floorState(active: bool, enabled: bool, correctDest: bool): bool {
            floor.containsDrag = active
            floor.enabled = enabled
            floor.dest = correctDest ? pane.dropPath : "/other"
            return true
        }
        function loadPreview(): bool {
            previewLoader.source = "file://" + Quickshell.env("SWEEPIPC_UI") + "/Preview.qml"
            return true
        }
        function previewReady(): bool { return previewLoader.status === Loader.Ready }
        function markdown(mode: string, active: bool, markdown: bool): bool {
            var preview = previewLoader.item
            if (!preview) return false
            preview.path = markdown ? Quickshell.env("SWEEPIPC_MARKDOWN") : Quickshell.env("SWEEPIPC_FILE")
            preview.kind = "text"
            preview.active = active
            if (markdown) {
                // Flickable inserts a contentItem; find the real Markdown pane by its own view property.
                var markdownPane = preview.surfaceItem()
                while (markdownPane && markdownPane.view === undefined) markdownPane = markdownPane.parent
                if (!markdownPane) return false
                markdownPane.view = mode
            }
            pane.preview = preview
            return true
        }
    }
}
