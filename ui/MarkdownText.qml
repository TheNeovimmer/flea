import QtQuick

// First-line padding keeps every Markdown line centred in the prescribed line box.
Text {
    id: root

    // md_rendered: line-height 1.7 over the text's own pixel size.
    readonly property real boxRatio: 1.7
    readonly property bool rich: root.textFormat !== Text.PlainText
    readonly property real box: Math.round(root.font.pixelSize * root.boxRatio)
    // QTextLine rounds the font's height up, so the first line is ceil(height) tall.
    readonly property real lead: Math.max(0, root.box - Math.ceil(metrics.height))
    // Rows of a table add their own cell padding on top of the box.
    property int cellPad: 0

    textFormat: Text.MarkdownText
    wrapMode: Text.Wrap
    color: Theme.color.foreground
    linkColor: Theme.color.foreground
    font.family: Theme.font.family
    font.pixelSize: Theme.font.body
    lineHeight: root.rich ? root.box : 1
    lineHeightMode: root.rich ? Text.FixedHeight : Text.ProportionalHeight
    topPadding: root.cellPad + Math.floor(root.lead / 2)
    bottomPadding: root.cellPad + root.lead - Math.floor(root.lead / 2)

    FontMetrics {
        id: metrics
        font: root.font
    }
}
