import QtQuick
import "." as Flea
import "js/Scroll.js" as Scroll

// The sideways scroll of a table wider than its block: the position and extent the table's rows slide by, the bar under the table, and the wheel's arithmetic.
Flickable {
    id: root
    objectName: "tableScroll"

    required property Item table

    // A sibling of the table in the block, laid over it. A positioner would stack it as a row, so under one it takes the positioner's parent and offset.
    readonly property Item flow: root.table.parent !== null && root.table.parent.move !== undefined ? root.table.parent : null
    // The key every chunk of one table shares, undefined for a table in one piece.
    readonly property var group: root.table.block.tableKey
    parent: root.flow !== null ? root.flow.parent : root.table.parent
    x: root.table.x + (root.flow !== null ? root.flow.x : 0)
    y: root.table.y + (root.flow !== null ? root.flow.y : 0)
    z: 1
    width: root.table.width
    height: root.table.height
    contentWidth: root.table.tableWidth
    contentHeight: root.height
    // Only the wheel and the bar move it: a disabled item takes none of the presses the table's links and cells need.
    enabled: false
    // The chunks of one table follow one position, whichever of them the wheel is over.
    onContentXChanged: if (root.route !== null) root.route.follow(root)
    onWidthChanged: root.returnToBounds()
    onContentWidthChanged: root.returnToBounds()

    // The router calls this for a stroke it gave the table, since the disabled handler below gets no event of its own.
    function wheel(event) {
        return wheelHandler.handleWheel(event)
    }

    // Kept from the start, since the table is already going when this is destroyed with it.
    property Item route: null
    Component.onCompleted: {
        root.route = root.table.preview !== null && root.table.preview.tableWheel ? root.table.preview.tableWheel : null
        if (root.route !== null)
            root.route.add(root)
    }
    Component.onDestruction: {
        if (root.route !== null)
            root.route.remove(root)
    }

    Flea.FastScrollHandler {
        id: wheelHandler
        parent: root
        flickable: root
    }

    // The bar draws under the table, in the lane the table reserved; the lane shows it only while moving, hovered or dragged.
    Flea.ViewportScrollBar {
        parent: root.parent
        // Only the last chunk of a table holds the lane, so a joined chunk stays flush under the one above.
        visible: root.table.lane && root.contentWidth - root.width > Scroll.OVERFLOW_PX
        x: root.x
        y: root.y + root.height - height
        flickable: root
        orientation: Qt.Horizontal
    }
}
