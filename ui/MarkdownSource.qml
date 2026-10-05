import QtQuick
import "js/Markdown.js" as Markdown

// The Source view: the text in chunks of whole lines, so only the chunks near the viewport are laid out and a large file costs a screenful.
ListView {
    id: root

    // The whole text, empty while Rendered shows.
    property string text: ""
    property int insetX: 0
    property int insetY: 0
    // The notice drawn above the text, empty for none, and the gap between it and the text.
    property string notice: ""
    property int blockGap: 0
    property int bodyPx: 14
    // Pixels of chunks kept built beyond the viewport.
    property int cachePixels: 0
    // Characters laid out now, so a suite sees that a screenful is.
    property int laidChars: 0
    readonly property Item noticeItem: deepNotice
    // The insets and the notice sit in the first and last rows, so they scroll with the text and the list never moves under a change to them.
    readonly property real noticeSpace: root.notice !== "" ? deepNotice.height + root.blockGap : 0
    readonly property var starts: Markdown.sourceChunkStarts(root.text)

    clip: true
    cacheBuffer: root.cachePixels
    model: root.text.length > 0 ? root.starts.length : 0
    FastScrollHandler {
        parent: root
        flickable: root
    }
    ViewportScrollBar {
        parent: root
        anchors { top: parent.top; right: parent.right }
        flickable: root
    }

    // A child of a list is part of its content, so the notice scrolls with the rows.
    Text {
        id: deepNotice
        visible: root.notice !== ""
        x: root.insetX
        y: root.insetY
        width: root.width - 2 * root.insetX
        text: root.notice
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
    }

    // A list lays a vertical delegate at x 0, so the inset is the text's own offset inside a row as wide as the list.
    delegate: Item {
        id: row
        required property int index
        objectName: "sourceChunk"
        readonly property Item label: chunk
        // What the first row holds above its text and the last below it.
        readonly property real above: row.index === 0 ? root.insetY + root.noticeSpace : 0
        readonly property real below: row.index === root.count - 1 ? root.insetY : 0
        width: root.width
        // The text's implicit height, not its height: a Text lays out lazily, so its height can lag the wrap a width change gave it.
        height: row.above + chunk.implicitHeight + row.below
        Text {
            id: chunk
            // The characters this chunk added to laidChars, so a changed text or a destroyed chunk takes back exactly them.
            property int counted: 0
            function tally() {
                root.laidChars += chunk.text.length - chunk.counted
                chunk.counted = chunk.text.length
            }
            x: root.insetX
            y: row.above
            width: root.width - 2 * root.insetX
            text: Markdown.sourceChunk(root.text, root.starts, row.index)
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: root.bodyPx
            onTextChanged: chunk.tally()
            Component.onCompleted: chunk.tally()
            Component.onDestruction: root.laidChars -= chunk.counted
        }
    }
}
