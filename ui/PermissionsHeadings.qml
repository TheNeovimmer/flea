import QtQuick
import qs.Commons

// The READ, WRITE and EXEC (ENTER for a folder) headings over the bit columns, each in the thirds the dialog's grid lays out.
Row {
    id: root
    // The PermissionsDialog whose label width, row height and bit columns these headings sit on.
    property var card: null
    property bool enter: false
    // The board's headings inherit the body's line-height of 1.6, where the note under the grid sets 1.5.
    readonly property real headingLineRatio: 1.6
    readonly property int lineBox: Math.round(root.headingLineRatio * Theme.font.caption)
    readonly property int lead: Math.round((root.lineBox - metrics.height) / 2)
    height: root.card.headingHeight
    FontMetrics { id: metrics; font { family: Theme.font.family; pixelSize: Theme.font.caption } }
    Item { width: root.card.labelWidth; height: parent.height }
    Repeater {
        model: ["READ", "WRITE", root.enter ? "ENTER" : "EXEC"]
        // The board's row centres a one-line box in the heading and the glyphs in that box, so a floor, not Qt's half pixel, sets its top.
        Text {
            required property string modelData
            required property int index
            width: root.card.bitWidth(index); height: root.lineBox
            y: Math.floor((parent.height - height) / 2)
            lineHeight: height; lineHeightMode: Text.FixedHeight; topPadding: root.lead
            horizontalAlignment: Text.AlignHCenter
            text: modelData; textFormat: Text.PlainText; color: Theme.color.foreground
            font { family: Theme.font.family; pixelSize: Theme.font.caption; letterSpacing: Theme.font.caption / 10 }
        }
    }
}
