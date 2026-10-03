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
            function mediaLoaded() { return false }
            function archiveNames() { return "" }
            function swapState() { return {active: true} }
        }
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
    }
}
