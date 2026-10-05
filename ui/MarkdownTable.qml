import QtQuick
import "." as Flea
import "js/Markdown.js" as Markdown
import "js/MarkdownTableFit.js" as Fit
import "js/Scroll.js" as Scroll

// A table hugs its cells with Grid, Column and Row, never QtQuick.Layouts, so the preview never loads it.
Column {
    id: root
    objectName: "tableGrid"

    // The parsed table chunk, and the preview that sets the document's size and gap.
    property var block: ({ head: [], aligns: [], rows: [], measure: [], pictures: [], weights: [], words: [], cols: 0 })
    property Item preview: null
    // The width the block column gives the table; columns wrap inside it, and 0 means no limit.
    property real availableWidth: 0
    readonly property int bodyPx: root.preview.bodyPx
    // A chunk after the first sits flush under its predecessor, across the gap the list puts between blocks.
    y: root.block.joined === true ? -root.preview.blockGap : 0
    // A table wider than its block clips to the block and scrolls sideways; the bar's lane is reserved under it, and under no other table.
    width: root.overflows ? root.availableWidth : root.tableWidth
    clip: root.overflows
    bottomPadding: root.overflows ? Theme.spacing.rowPaddingX : 0
    spacing: 0

    // The sideways scroll, built the first time the table overflows: a table that fits owns no object for it, which the block cost gates count.
    property Item scroller: null
    function syncScroller() {
        if (root.scroller === null && root.overflows)
            root.scroller = Qt.createComponent("MarkdownTableScroll.qml").createObject(root, { table: root })
    }
    onOverflowsChanged: root.syncScroller()
    Component.onCompleted: root.syncScroller()
    // Every row slides by the scroll position under the clip, so a table that fits sits at zero.
    readonly property real shift: root.overflows && root.scroller !== null ? -root.scroller.contentX : 0

    Row {
        id: headerRow
        x: root.shift
        spacing: root.cellGap

        Repeater {
            model: root.block.head.length
            delegate: Flea.MarkdownText {
                linkGate: Markdown.isExternalLink
                width: root.textWidth(index)
                bodyPx: root.bodyPx
                cellPad: 2
                markdown: root.block.head[index]
                horizontalAlignment: root.alignAt(index)
                font.bold: true
                color: Theme.color.foregroundBright
            }
        }
    }

    Rectangle {
        visible: root.block.head.length > 0
        x: root.shift
        width: root.tableWidth
        height: Theme.spacing.hairline
        color: Theme.color.foreground
        opacity: root.preview.ruleOpacity
    }

    Repeater {
        model: root.block.rows.length
        delegate: Column {
            readonly property int row: index
            x: root.shift
            width: root.tableWidth
            spacing: 0

            Row {
                spacing: root.cellGap

                Repeater {
                    model: root.columns
                    delegate: Flea.MarkdownText {
                        linkGate: Markdown.isExternalLink
                        width: root.textWidth(index)
                        bodyPx: root.bodyPx
                        cellPad: 2
                        markdown: root.cellAt(row, index)
                        horizontalAlignment: root.alignAt(index)
                    }
                }
            }

            Rectangle {
                width: root.tableWidth
                height: Theme.spacing.hairline
                color: Theme.color.foreground
                opacity: root.preview.ruleOpacity
            }
        }
    }

    // Invisible measurers carry each column's widest cell plus a second for an image cell, since the parser cannot know the image's width.
    Repeater {
        id: measurers
        model: root.measureTexts
        delegate: Text {
            objectName: "measurer"
            visible: false
            text: modelData
            textFormat: Text.MarkdownText
            font.family: Theme.font.family
            font.pixelSize: root.bodyPx
            // A header cell may set the width and is bold, so every measurer is: chunks without the header must agree.
            font.bold: true
        }
    }

    // The measure of each column, then the picture cell of every column that has one, in the order the measurers are built.
    readonly property var measureTexts: {
        var texts = []
        var pictures = root.block.pictures || []
        for (var c = 0; c < root.columns; c++)
            texts.push(c < root.block.measure.length ? root.block.measure[c] : "")
        for (var p = 0; p < root.columns; p++) {
            if (p < pictures.length && pictures[p] !== "")
                texts.push(pictures[p])
        }
        return texts
    }
    // The empty gap each column keeps beside its text, and the width of one glyph when the parser measured no text.
    readonly property int cellGap: 14
    readonly property real fallbackGlyphEm: 0.6
    // A column's text width: the wider of its measure and its picture cell, once the measurers have laid out.
    readonly property var columnPx: {
        // Count and implicitWidth notify when a measurer arrives and lays out; itemAt alone notifies nothing.
        var widths = []
        var pictures = root.block.pictures || []
        var next = root.columns
        for (var c = 0; c < root.columns; c++) {
            var own = measurers.count > c ? measurers.itemAt(c) : null
            var px = own ? own.implicitWidth : 0
            if (c < pictures.length && pictures[c] !== "") {
                var extra = measurers.count > next ? measurers.itemAt(next) : null
                px = Math.max(px, extra ? extra.implicitWidth : 0)
                next++
            }
            widths.push(px)
        }
        return widths
    }
    // A column's text width beside its picture width: the parser weighs text alone, so the glyph price divides text by text.
    readonly property var textPx: {
        // Count and implicitWidth notify when a measurer arrives and lays out; itemAt alone notifies nothing.
        var widths = []
        for (var c = 0; c < root.columns; c++) {
            var own = measurers.count > c ? measurers.itemAt(c) : null
            widths.push(own ? own.implicitWidth : 0)
        }
        return widths
    }
    // Pixels a column of the parser's width weight draws: the table's measured text over its weight, so the longest word converts to pixels.
    readonly property real glyphPx: {
        var px = 0
        var weight = 0
        var weights = root.block.weights || []
        for (var c = 0; c < root.columns; c++) {
            if (c < weights.length && weights[c] > 0) {
                px += root.textPx[c]
                weight += weights[c]
            }
        }
        return weight > 0 ? px / weight : root.bodyPx * root.fallbackGlyphEm
    }
    // Each column's width: natural when the table fits the block, else shared by Fit with every column keeping its longest word first.
    readonly property var widths: {
        var natural = []
        var minimum = []
        var words = root.block.words || []
        for (var c = 0; c < root.columns; c++) {
            // Whole pixels up: Fit floors its shares, and a text box a fraction short of its word breaks the word.
            natural.push(Math.ceil(root.columnPx[c]) + root.cellGap)
            minimum.push(Math.ceil((c < words.length ? words[c] : 0) * root.glyphPx) + root.cellGap)
        }
        // A wide glyph takes two, so no column goes under two glyphs of text.
        var least = root.cellGap + Math.ceil(2 * root.glyphPx)
        return root.availableWidth > 0 ? Fit.fit(natural, minimum, root.availableWidth, least) : natural
    }
    readonly property real tableWidth: {
        var total = 0
        for (var c = 0; c < root.widths.length; c++)
            total += root.widths[c]
        return total
    }
    // Wider than its block once every column holds its longest word whole; the block's width then bounds the table.
    readonly property bool overflows: root.availableWidth > 0 && root.tableWidth - root.availableWidth > Scroll.OVERFLOW_PX

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
        return col < root.widths.length ? root.widths[col] : 0
    }
    // A cell's text stays inside its column's share minus the gap the next cell starts after, so the gap never holds ink.
    function textWidth(col) {
        return Math.max(0, root.colWidth(col) - root.cellGap)
    }
}
