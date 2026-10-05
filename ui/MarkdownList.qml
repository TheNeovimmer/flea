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
    // The preview that sets the sizes of the blocks an item holds, and whether this list is in view for figures.
    property Item preview: null
    property bool inView: true

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
                // The marker sits on the item's first baseline, 0 for an ungrown line and for a first block with no run text.
                y: itemParts.active ? (itemParts.item !== null && itemParts.item.firstRunText !== null ? itemParts.item.firstRunText.baselineOffset - marker.baselineOffset : 0) : itemText.baselineOffset - marker.baselineOffset
            }

            MarkdownText {
                id: itemText
                visible: !itemParts.active
                linkGate: root.linkGate
                width: parent.width - marker.width - parent.spacing
                bodyPx: root.bodyPx
                markdown: root.list.items[index]
            }

            // An item that holds more than prose draws its blocks in order; they load by file name since MarkdownBlocks draws lists again.
            Loader {
                id: itemParts
                readonly property var parts: root.list.parts !== undefined && root.list.parts[index] ? root.list.parts[index] : []
                active: itemParts.parts.length > 0
                width: parent.width - marker.width - parent.spacing
                source: itemParts.parts.length > 0 ? "MarkdownBlocks.qml" : ""
                onLoaded: {
                    // The preview and the view state come first: the blocks build their delegates the moment they arrive.
                    itemParts.item.preview = Qt.binding(function () { return root.preview })
                    itemParts.item.inView = Qt.binding(function () { return root.inView })
                    itemParts.item.blocks = Qt.binding(function () { return itemParts.parts })
                }
            }
        }
    }
}
