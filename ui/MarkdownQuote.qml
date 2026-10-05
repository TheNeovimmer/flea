import QtQuick

// One quote block: a 2 px bar per level, each a bar-plus-gap step right of its parent's, then the text or the blocks the quote holds.
Row {
    id: root

    property int levels: 1
    property string text: ""
    // The quote's blocks when it holds more than prose, drawn in order in place of the text; the preview sets their sizes.
    property var parts: []
    property Item preview: null
    property bool inView: true
    property int bodyPx: Theme.font.body
    property var linkGate: null
    readonly property int barWidth: 2
    // The width the text or the blocks take beside the bars.
    readonly property real contentWidth: root.width - root.levels * (root.barWidth + root.spacing)

    spacing: Theme.spacing.gap

    Repeater {
        model: root.levels
        delegate: Rectangle {
            width: root.barWidth
            height: root.parts.length > 0 ? held.height : quoteText.implicitHeight
            color: Theme.color.muted
        }
    }

    MarkdownText {
        id: quoteText
        visible: root.parts.length === 0
        linkGate: root.linkGate
        width: root.contentWidth
        bodyPx: root.bodyPx
        markdown: root.text
    }

    // The blocks load by file name: MarkdownBlocks draws quotes and lists again, and a type reference would close the cycle.
    Loader {
        id: held
        active: root.parts.length > 0
        width: root.contentWidth
        source: root.parts.length > 0 ? "MarkdownBlocks.qml" : ""
        onLoaded: {
            // The preview and the view state come first: the blocks build their delegates the moment they arrive.
            held.item.preview = Qt.binding(function () { return root.preview })
            held.item.inView = Qt.binding(function () { return root.inView })
            held.item.blocks = Qt.binding(function () { return root.parts })
        }
    }
}
