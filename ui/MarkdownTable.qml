import QtQuick
import "." as Flea
import "js/Markdown.js" as Markdown

// A table hugs its cells with Grid, Column and Row, never QtQuick.Layouts, so the preview never loads it.
Column {
    id: root
    objectName: "tableGrid"

    // The parsed table chunk, and the preview that sets the document's size and gap.
    property var block: ({ head: [], aligns: [], rows: [], measure: [], cols: 0 })
    property Item preview: null
    readonly property int bodyPx: root.preview.bodyPx
    // A chunk after the first sits flush under its predecessor, across the gap the list puts between blocks.
    y: root.block.joined === true ? -root.preview.blockGap : 0
    width: root.tableWidth()
    spacing: 0

    Row {
        id: headerRow
        spacing: 0

        Repeater {
            model: root.block.head.length
            delegate: Flea.MarkdownText {
                linkGate: Markdown.isExternalLink
                width: root.colWidth(index)
                bodyPx: root.bodyPx
                cellPad: 2
                text: root.block.head[index]
                horizontalAlignment: root.alignAt(index)
                font.bold: true
                color: Theme.color.foregroundBright
            }
        }
    }

    Rectangle {
        visible: root.block.head.length > 0
        width: root.tableWidth()
        height: Theme.spacing.hairline
        color: Theme.color.foreground
        opacity: root.preview.ruleOpacity
    }

    Repeater {
        model: root.block.rows.length
        delegate: Column {
            readonly property int row: index
            width: root.tableWidth()
            spacing: 0

            Row {
                spacing: 0

                Repeater {
                    model: root.columns
                    delegate: Flea.MarkdownText {
                        linkGate: Markdown.isExternalLink
                        width: root.colWidth(index)
                        bodyPx: root.bodyPx
                        cellPad: 2
                        text: root.cellAt(row, index)
                        horizontalAlignment: root.alignAt(index)
                    }
                }
            }

            Rectangle {
                width: root.tableWidth()
                height: Theme.spacing.hairline
                color: Theme.color.foreground
                opacity: root.preview.ruleOpacity
            }
        }
    }

    // Invisible measurers carry each column's longest cell, measured by the parser over the whole table, so chunks of one table share widths.
    Repeater {
        id: measurers
        model: root.columns
        delegate: Text {
            visible: false
            text: index < root.block.measure.length ? root.block.measure[index] : ""
            textFormat: Text.MarkdownText
            font.family: Theme.font.family
            font.pixelSize: root.bodyPx
        }
    }

    // Helpers over the block, so delegates read cells and alignment by place.
    readonly property int columns: Math.max(1, root.block.cols)
    function alignName(i) {
        return i < root.block.aligns.length ? root.block.aligns[i] : "left"
    }
    function alignAt(i) {
        var name = root.alignName(i)
        return name === "center" ? Text.AlignHCenter : name === "right" ? Text.AlignRight : Text.AlignLeft
    }
    function cellAt(r, c) {
        return r < root.block.rows.length && c < root.block.rows[r].length ? root.block.rows[r][c] : ""
    }
    function colWidth(col) {
        // Count and implicitWidth notify when a measurer arrives and lays out; itemAt alone notifies nothing.
        if (measurers.count <= col)
            return 0
        var measured = measurers.itemAt(col)
        return (measured ? measured.implicitWidth : 0) + 14
    }
    function tableWidth() {
        var total = 0
        for (var c = 0; c < root.columns; c++)
            total += root.colWidth(c)
        return total
    }
}
