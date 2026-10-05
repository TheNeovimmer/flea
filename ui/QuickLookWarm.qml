import QtQuick
import "." as Flea

// What Quick Look's first Space needs before it exists: the rested file's prepared entry and held pictures, and Quick Look's own, the Markdown and the swap units compiled.
Item {
    id: root

    // WindowBody builds this on the cursor's first landing on a Markdown file, so a window that never rests on one pays nothing for it.
    property var pane: null
    // False while Quick Look is open: the entry is for the next Space.
    readonly property bool resting: !(root.look !== null && root.look.active)
    readonly property alias prepare: prepare
    // Quick Look's own unit, the Markdown pane and the swap wrapper, held from the first idle after the window settles and never instantiated, so the first Space compiles and loads no unit.
    property var previewUnit: null
    property var markdownUnit: null
    property var swapUnit: null
    readonly property int unitWarmMs: 1000
    readonly property bool windowSettled: root.pane !== null && root.pane.listingState === "ready" && !root.pane.listInFlight

    Timer {
        running: root.windowSettled && root.markdownUnit === null
        interval: root.unitWarmMs
        onTriggered: {
            root.previewUnit = Qt.createComponent("Preview.qml", Component.Asynchronous)
            root.markdownUnit = Qt.createComponent("MarkdownPane.qml", Component.Asynchronous)
            root.swapUnit = Qt.createComponent("QuickLookSwap.qml", Component.Asynchronous)
        }
    }
    Flea.QuickLookPrepare { id: prepare; pane: root.pane; resting: root.resting }
    // The card Quick Look opens; resting reads it so a rest never prepares over an open card.
    readonly property var look: root.pane ? root.pane.preview : null
    // The cursor is already on its file when this is built, so the first rest starts here and not on a move.
    Component.onCompleted: prepare.moved()
}
