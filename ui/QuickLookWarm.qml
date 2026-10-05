import QtQuick
import "." as Flea
import "js/MarkdownPrepared.js" as Prepared

// What Quick Look's first Space needs before it opens: the rested file's prepared entry and held pictures, the compiled units, and the card itself built closed.
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
    readonly property bool unitsReady: root.previewUnit !== null && root.previewUnit.status === Component.Ready
        && root.markdownUnit !== null && root.markdownUnit.status === Component.Ready
        && root.swapUnit !== null && root.swapUnit.status === Component.Ready
    // The cursor has rested on a Markdown file with every unit compiled: the card is built now, hidden and inactive, so the first Space only opens it.
    readonly property bool cardDue: root.unitsReady && prepare.rested && root.pane !== null && Prepared.isMarkdownRow(root.pane.cursorRow)
    onCardDueChanged: if (root.cardDue && root.pane.previewLoader) root.pane.previewLoader.active = true
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
