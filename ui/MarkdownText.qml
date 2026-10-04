import QtQuick

// The padding places the text's baseline where CSS puts it, half the leading above the font's ascent, on every wrapped line.
Text {
    id: root

    // md_rendered: line-height 1.7 over the text's own pixel size.
    readonly property real boxRatio: 1.7
    readonly property bool rich: root.textFormat !== Text.PlainText
    readonly property real box: Math.round(root.font.pixelSize * root.boxRatio)
    // QTextLine rounds the font's height up, so the first line is ceil(height) tall.
    readonly property real lead: Math.max(0, root.box - Math.ceil(metrics.height))
    // Qt's FixedHeight line puts its baseline this share down the box whatever the font, so the padding moves it to the centred one.
    readonly property real fixedBaselineShare: 0.8
    readonly property int centredBaseline: Math.round((root.box - metrics.height) / 2 + metrics.ascent)
    // Rich text shifts by the gap between the two baselines (negative when Qt sits it low); plain text sits at the top of its natural line.
    readonly property int lift: root.rich ? root.centredBaseline - Math.round(root.box * root.fixedBaselineShare) : Math.floor(root.lead / 2)
    // The document's body size; the preview column scales it down from Quick Look's.
    property int bodyPx: Theme.font.body
    // Rows of a table add their own cell padding on top of the box.
    property int cellPad: 0

    // The host supplies the scheme gate (Markdown.isExternalLink), as no import of the parser fits the standalone probe copy.
    property var linkGate: null
    // One handler for every Markdown text: a link the gate passes opens in the default application, all else opens nothing.
    onLinkActivated: function (link) {
        if (root.linkGate !== null && root.linkGate(link))
            Qt.openUrlExternally(link)
    }

    textFormat: Text.MarkdownText
    wrapMode: Text.Wrap
    color: Theme.color.foreground
    linkColor: Theme.color.foreground
    font.family: Theme.font.family
    font.pixelSize: root.bodyPx
    lineHeight: root.rich ? root.box : 1
    lineHeightMode: root.rich ? Text.FixedHeight : Text.ProportionalHeight
    topPadding: root.cellPad + root.lift
    bottomPadding: root.cellPad + root.lead - root.lift

    FontMetrics {
        id: metrics
        font: root.font
    }
}
