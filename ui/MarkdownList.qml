import QtQuick
import "js/MarkdownLists.js" as Lists

// One list block drawn with plain Column and Row, keeping QtQuick.Layouts unloaded: each depth's marker column starts at its parent's text column.
Column {
    id: root

    // The parsed list: items, and when nested or loose their depths, markers and gaps.
    property var list: ({ items: [] })
    property int bodyPx: Theme.font.body
    // The paragraph gap a loose list puts between its entries.
    property int gap: 0
    property var linkGate: null

    spacing: 0

    // Each entry's marker column, marker and gap above it; reading the font's size and family re-lays it out when either changes.
    readonly property var cells: {
        listFont.font.pixelSize
        listFont.font.family
        return Lists.layout(root.list, function (text) { return listFont.advanceWidth(text) }, Theme.spacing.gap)
    }

    FontMetrics {
        id: listFont
        font.family: Theme.font.family
        font.pixelSize: root.bodyPx
    }

    Repeater {
        model: root.list.items.length
        delegate: Row {
            objectName: "listRow"
            readonly property var cell: root.cells[index]
            x: cell.x
            width: root.width - cell.x
            topPadding: cell.gap ? root.gap : 0
            spacing: Theme.spacing.gap

            MarkdownText {
                id: marker
                width: cell.w
                bodyPx: root.bodyPx
                text: cell.marker
                // The marker shares the item's line box and first-line leading.
                textFormat: Text.RichText
                height: marker.box
                wrapMode: Text.NoWrap
            }

            MarkdownText {
                linkGate: root.linkGate
                width: parent.width - marker.width - parent.spacing
                bodyPx: root.bodyPx
                text: root.list.items[index]
            }
        }
    }
}
