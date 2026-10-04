import QtQuick

// One quote block: a 2 px bar per level, each a bar-plus-gap step right of its parent's, then the text.
Row {
    id: root

    property int levels: 1
    property string text: ""
    property int bodyPx: Theme.font.body
    property var linkGate: null
    readonly property int barWidth: 2

    spacing: Theme.spacing.gap

    Repeater {
        model: root.levels
        delegate: Rectangle {
            width: root.barWidth
            height: quoteText.implicitHeight
            color: Theme.color.muted
        }
    }

    MarkdownText {
        id: quoteText
        linkGate: root.linkGate
        width: root.width - root.levels * (root.barWidth + root.spacing)
        bodyPx: root.bodyPx
        text: root.text
    }
}
