import QtQuick
import qs.Commons
import "." as Flea
import "js/SheetQuery.js" as SheetQuery

// One result row of the keymap sheet's query: the cursor lift across the card's inner width, the cap, the label with its matched run washed, and the muted where.
Item {
    id: hit

    required property var modelData
    required property int index
    // What the sheet hands down, so a row owns no sheet state.
    required property int resultCursor
    required property string query
    required property int capWidth
    required property int capSize
    required property int capGap
    required property int rowPitch
    required property real textInset
    // The most of the label column the muted where may take, so a deep folder elides too and the name keeps the rest.
    required property real whereShare
    height: hit.rowPitch
    // What a row has left of its width after the cap column.
    readonly property real labelColumn: hit.width - hit.capWidth - hit.capGap
    readonly property string whereText: String(hit.modelData.where || "")
    // The lift runs across the card's inner width, past the text's padding on both sides.
    Rectangle {
        x: -hit.textInset
        width: hit.width + 2 * hit.textInset
        height: parent.height
        visible: hit.index === hit.resultCursor
        color: Qt.alpha(Theme.color.foreground, Theme.washHover)
    }
    Rectangle {
        id: hitCap
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: hit.capWidth
        height: hit.capSize
        color: "transparent"
        border.width: hit.modelData.keys.length > 0 ? Theme.spacing.hairline : 0
        border.color: Theme.color.muted
        Text {
            anchors.fill: parent
            anchors.margins: Theme.spacing.hairline
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: hit.modelData.keys
            color: hit.modelData.disabled === true ? Theme.color.muted : Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
    }
    Flea.MatchText {
        id: hitLabel
        anchors.left: hitCap.right
        anchors.leftMargin: hit.capGap
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, hit.labelColumn - hitWhere.width)
        text: hit.modelData.label
        color: hit.modelData.disabled === true ? Theme.color.muted : Theme.color.foreground
        pixelSize: Theme.font.caption
        matchStart: SheetQuery.matchOf(hit.modelData.label, hit.query) ? SheetQuery.matchOf(hit.modelData.label, hit.query).start : -1
        matchLength: SheetQuery.matchOf(hit.modelData.label, hit.query) ? SheetQuery.matchOf(hit.modelData.label, hit.query).length : 0
    }
    // Where the result lives, muted and inline right after its name, as the board draws it; it keeps its width, so a long name elides instead.
    Text {
        id: hitWhere
        anchors.left: hitLabel.right
        anchors.verticalCenter: parent.verticalCenter
        width: hit.whereText.length > 0 ? Math.min(implicitWidth, hit.labelColumn * hit.whereShare) : 0
        visible: hit.whereText.length > 0
        text: hit.whereText.length > 0 ? " in " + hit.whereText : ""
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
}
