import QtQuick

// The blocks an item or a quote holds, in order, each drawn as its kind draws at the top of the document.
Column {
    id: root

    property var blocks: []
    // The preview that sets the document's sizes and colours, and whether this part of it is in view for figures.
    property Item preview: null
    property bool inView: true

    spacing: root.preview !== null ? root.preview.blockGap : 0

    // The first block's view, tracked without one object per item.
    property Item firstView: null
    // The first block's run text, null unless that block is a plain run.
    readonly property Item firstRunText: root.firstView !== null ? root.firstView.runText : null

    Repeater {
        id: partsRepeater
        onItemAdded: function (index, item) { if (index === 0) root.firstView = item }
        onItemRemoved: function (index, item) { if (item === root.firstView) root.firstView = null }
        model: root.blocks
        delegate: MarkdownBlockView {
            required property var modelData
            required property int index
            block: modelData
            blockIndex: index
            blockCount: root.blocks.length
            siblings: root.blocks
            preview: root.preview
            inView: root.inView
            width: root.width
        }
    }
}
