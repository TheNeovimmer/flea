import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "." as Flea
import "js/Icons.js" as Icons
import "js/Markdown.js" as Markdown

// A Markdown file under the cursor, read once and on demand like every other text preview.
// Rendered draws ui/js/Markdown.js's blocks: ordinary runs through Qt's own Markdown support,
// fenced code verbatim on the chrome surface, quotes behind a muted bar, remote images as the
// board's box and same-folder images as the image. Source is the file verbatim. Every image
// URL is resolved before Qt sees any text, so a remote image is a box and only a file beside
// the document loads; links carry no handler and never leave.
Item {
    id: root

    property bool active: false
    property string path: ""
    property int size: 0
    // "rendered" or "source"; anything else reads as rendered, the board's default.
    property string view: Markdown.RENDERED

    // FileView reads the whole file into memory, so this is the largest read a preview will start.
    // Remote storage keeps the smaller 256 KiB gate through maxBytes, and refuses past it too.
    property int maxBytes: 1048576
    // Retained for its callers; over-limit rows are refused, never truncated, so it reads nothing.
    property bool truncate: false
    readonly property bool tooLarge: root.size > root.maxBytes
    property bool readFailed: false

    readonly property string rawText: file.text()
    // QML color components read 0..1, so the hex a style attribute needs is assembled, never coerced.
    function hexByte(v) {
        var s = Math.round(v * 255).toString(16)
        return s.length < 2 ? "0" + s : s
    }
    function hexOf(c) {
        return "#" + hexByte(c.r) + hexByte(c.g) + hexByte(c.b)
    }
    readonly property string borderHex: hexOf(Theme.color.muted)
    readonly property string chromeHex: hexOf(Theme.color.surface)
    // The render suite reads the ink it asserts beside the border, same assembly, no coercion.
    readonly property string inkHex: hexOf(Theme.color.foreground)
    readonly property var blockList: Markdown.blocks(root.rawText, Markdown.dirOf(root.path),
        root.chromeHex, root.inkHex)
    readonly property bool loading: root.active && !root.readFailed && !file.loaded && !root.tooLarge
    readonly property string status: {
        if (root.tooLarge) return "This file is too large to preview."
        if (root.readFailed) return "This file could not be read."
        return file.loaded ? "ready" : "loading"
    }
    readonly property string lineLabel: Markdown.countLine(Markdown.lineCount(root.rawText))
    // The bar's line count reads only once there is a file behind it, never "0 lines" first.
    readonly property bool contentReady: file.loaded && !root.tooLarge && !root.readFailed
    // True when the reader has settled with nothing to put in the frame, the way PreviewLines.blank reads.
    readonly property bool blank: root.tooLarge
        || (root.active && !root.readFailed && file.loaded && root.rawText.length === 0)

    readonly property Item bodyItem: body
    // The render suite reads delegate geometry off the live tree, the way ColumnsArea does.
    function blockItem(i) { return blocks.itemAt(i) }
    readonly property real flickContentHeight: flick.contentHeight

    visible: root.active

    FileView {
        id: file
        path: (root.active && !root.tooLarge) ? root.path : ""
        printErrors: false
        onLoadFailed: root.readFailed = true
        onPathChanged: root.readFailed = false
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, root.view === Markdown.SOURCE ? sourceText.implicitHeight : body.implicitHeight)
        visible: !root.tooLarge && !root.readFailed

        FastScrollHandler {
            parent: flick
            flickable: flick
        }

        Flea.ViewportScrollBar {
            parent: flick
            anchors { top: parent.top; right: parent.right }
            flickable: flick
        }

        Text {
            id: sourceText
            visible: root.view === Markdown.SOURCE
            width: parent.width
            text: root.rawText
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
        }

        Column {
            id: body
            visible: root.view !== Markdown.SOURCE
            width: parent.width
            spacing: Theme.spacing.gap

            Repeater {
                id: blocks
                model: root.blockList

                delegate: Item {
                    property var block: modelData
                    width: parent.width
                    // Only the drawn child lends its height; the rest hold no geometry that matters.
                    height: block.type === "run" ? runText.height
                        : block.type === "fence" ? fenceBox.height
                        : block.type === "quote" ? quoteRow.height
                        : block.type === "remote" ? remoteBox.height
                        : block.type === "list" ? listGrid.height
                        : block.type === "table" ? tableGrid.height : localImage.height

                    Text {
                        id: runText
                        visible: block.type === "run"
                        width: parent.width
                        text: block.type === "run" ? block.text : ""
                        // Qt's own Markdown renderer; with no link handler anywhere a link stays ink.
                        textFormat: Text.MarkdownText
                        wrapMode: Text.Wrap
                        color: Theme.color.foreground
                        linkColor: Theme.color.foreground
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.body
                    }

                    // A table arrives structured from ui/js/Markdown.js and draws here in Qt
                    // Quick, since Markdown tables carry no styling: a bold header, a muted rule
                    // under the header and each row, no verticals, each column as wide as its
                    // widest cell plus 14 px. The grid takes no width, so it hugs its content
                    // at the left edge instead of filling the frame.
                    GridLayout {
                        id: tableGrid
                        visible: block.type === "table"
                        columns: block.type === "table" ? Math.max(1, block.cols) : 1
                        columnSpacing: 0
                        rowSpacing: 0

                        Repeater {
                            model: block.type === "table" ? block.head : []
                            delegate: Text {
                                Layout.row: 0
                                Layout.column: index
                                Layout.topMargin: 2
                                Layout.bottomMargin: 2
                                Layout.preferredWidth: tableGrid.colWidth(index)
                                text: modelData
                                textFormat: Text.MarkdownText
                                wrapMode: Text.Wrap
                                horizontalAlignment: tableGrid.alignAt(index)
                                color: Theme.color.foreground
                                linkColor: Theme.color.foreground
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.body
                                font.bold: true
                            }
                        }

                        Rectangle {
                            Layout.row: 1
                            Layout.columnSpan: tableGrid.columns
                            Layout.preferredWidth: tableGrid.tableWidth()
                            Layout.preferredHeight: Theme.spacing.hairline
                            color: Theme.color.muted
                        }

                        Repeater {
                            model: block.type === "table" ? tableGrid.cellCount : 0
                            delegate: Text {
                                readonly property int row: Math.floor(index / tableGrid.columns)
                                readonly property int col: index % tableGrid.columns
                                Layout.row: 2 + row * 2
                                Layout.column: col
                                Layout.topMargin: 2
                                Layout.bottomMargin: 2
                                Layout.preferredWidth: tableGrid.colWidth(col)
                                text: tableGrid.cellAt(row, col)
                                textFormat: Text.MarkdownText
                                wrapMode: Text.Wrap
                                horizontalAlignment: tableGrid.alignAt(col)
                                color: Theme.color.foreground
                                linkColor: Theme.color.foreground
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.body
                            }
                        }

                        Repeater {
                            model: block.type === "table" ? block.rows.length : 0
                            delegate: Rectangle {
                                Layout.row: 3 + index * 2
                                Layout.columnSpan: tableGrid.columns
                                Layout.preferredWidth: tableGrid.tableWidth()
                                Layout.preferredHeight: Theme.spacing.hairline
                                color: Theme.color.muted
                            }
                        }

                        // Helpers over the block, so delegates read cells and alignment by place.
                        function alignName(i) {
                            var names = block.type === "table" ? block.aligns : []
                            return i < names.length ? names[i] : "left"
                        }
                        function alignAt(i) {
                            var name = alignName(i)
                            return name === "center" ? Text.AlignHCenter : name === "right" ? Text.AlignRight : Text.AlignLeft
                        }
                        readonly property int cellCount: block.type === "table" ? block.rows.length * columns : 0
                        function cellAt(r, c) {
                            var rows = block.type === "table" ? block.rows : []
                            return r < rows.length && c < rows[r].length ? rows[r][c] : ""
                        }
                        // The decoded longest cell of a column, drawn invisibly beside the grid
                        // so the column starts where its widest cell ends. Entities decode to one
                        // character each, which is what the delegate draws.
                        function longestIn(col) {
                            var best = ""
                            if (block.type !== "table")
                                return best
                            var cells = [block.head].concat(block.rows)
                            for (var r = 0; r < cells.length; r++) {
                                var row = cells[r]
                                var raw = col < row.length ? row[col] : ""
                                var decoded = String(raw).replace(/&#(\d+);/g, function (m, n) {
                                    return String.fromCharCode(parseInt(n, 10))
                                })
                                if (decoded.length > best.length)
                                    best = decoded
                            }
                            return best
                        }
                        function colWidth(col) {
                            if (block.type !== "table")
                                return 0
                            // Count and implicitWidth both notify, so a column settles once its
                            // measurer arrives and lays out; itemAt alone notifies nothing.
                            if (measurers.count <= col)
                                return 0
                            var measured = measurers.itemAt(col)
                            return (measured ? measured.implicitWidth : 0) + 14
                        }
                        function tableWidth() {
                            if (block.type !== "table")
                                return 0
                            var total = 0
                            for (var c = 0; c < tableGrid.columns; c++)
                                total += tableGrid.colWidth(c)
                            return total
                        }
                    }

                    // Invisible measurers, one per column, carrying the longest cell each, so the
                    // grid columns size to content. Excluded from the grid's own layout by visibility.
                    Repeater {
                        id: measurers
                        model: block.type === "table" ? tableGrid.columns : 0
                        delegate: Text {
                            visible: false
                            text: tableGrid.longestIn(index)
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.body
                        }
                    }

                    // A fenced block is a filled block on the chrome surface with no border.
                    Rectangle {
                        id: fenceBox
                        visible: block.type === "fence"
                        width: parent.width
                        height: fenceText.implicitHeight + 2 * Theme.spacing.gap
                        color: Theme.color.surface

                        Text {
                            id: fenceText
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.gap
                            text: block.type === "fence" ? block.text : ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: Theme.color.foreground
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.body
                        }
                    }

                    Row {
                        id: quoteRow
                        visible: block.type === "quote"
                        width: parent.width
                        spacing: Theme.spacing.gap

                        Rectangle {
                            width: 2
                            height: quoteText.implicitHeight
                            color: Theme.color.muted
                        }

                        Text {
                            id: quoteText
                            width: parent.width - 2 - parent.spacing
                            text: block.type === "quote" ? block.text : ""
                            textFormat: Text.MarkdownText
                            wrapMode: Text.Wrap
                            color: Theme.color.foreground
                            linkColor: Theme.color.foreground
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.body
                        }
                    }

                    // A top-level list draws its markers at the text's left edge, bullets and
                    // ordered alike, with the item text after each marker.
                    GridLayout {
                        id: listGrid
                        visible: block.type === "list"
                        width: parent.width
                        columns: 2
                        columnSpacing: Theme.spacing.gap
                        rowSpacing: 0

                        Repeater {
                            model: block.type === "list" ? block.items.length : 0
                            delegate: Text {
                                Layout.row: index
                                Layout.column: 0
                                Layout.alignment: Qt.AlignTop
                                text: block.ordered ? (block.start + index) + "." : "•"
                                color: Theme.color.foreground
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.body
                                textFormat: Text.PlainText
                            }
                        }

                        Repeater {
                            model: block.type === "list" ? block.items.length : 0
                            delegate: Text {
                                Layout.row: index
                                Layout.column: 1
                                Layout.alignment: Qt.AlignTop
                                Layout.fillWidth: true
                                text: block.items[index]
                                textFormat: Text.MarkdownText
                                wrapMode: Text.Wrap
                                color: Theme.color.foreground
                                linkColor: Theme.color.foreground
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.body
                            }
                        }
                    }

                    // The board's placeholder: one dashed muted rectangle across the content width,
                    // the image glyph and the sentence on one line inside it, left-aligned, muted.
                    Item {
                        id: remoteBox
                        visible: block.type === "remote"
                        width: parent.width
                        height: remoteRow.implicitHeight + 2 * Theme.spacing.gap

                        Row {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 6
                            Repeater {
                                model: Math.max(1, Math.floor((remoteBox.width + 6) / 14))
                                delegate: Rectangle { width: 8; height: Theme.spacing.hairline; color: Theme.color.muted }
                            }
                        }

                        Row {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 6
                            Repeater {
                                model: Math.max(1, Math.floor((remoteBox.width + 6) / 14))
                                delegate: Rectangle { width: 8; height: Theme.spacing.hairline; color: Theme.color.muted }
                            }
                        }

                        Column {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            spacing: 6
                            Repeater {
                                model: Math.max(1, Math.floor((remoteBox.height + 6) / 14))
                                delegate: Rectangle { width: Theme.spacing.hairline; height: 8; color: Theme.color.muted }
                            }
                        }

                        Column {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            spacing: 6
                            Repeater {
                                model: Math.max(1, Math.floor((remoteBox.height + 6) / 14))
                                delegate: Rectangle { width: Theme.spacing.hairline; height: 8; color: Theme.color.muted }
                            }
                        }

                        Row {
                            id: remoteRow
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacing.gap
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacing.gap
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacing.gap

                            Flea.Glyph {
                                id: remoteMark
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.chromeMarkSize
                                height: Theme.chromeMarkSize
                                maxSize: Theme.chromeMarkSize
                                name: Icons.glyphFor("image-x-generic")
                                color: Theme.color.muted
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - remoteMark.width - parent.spacing
                                text: block.type === "remote" ? Markdown.placeholder(block.host) : ""
                                color: Theme.color.muted
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.caption
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Image {
                        id: localImage
                        visible: block.type === "image"
                        width: parent.width
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        autoTransform: true
                        source: block.type === "image" ? block.url : ""
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.tooLarge || root.readFailed
        text: root.status
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
        textFormat: Text.PlainText
    }
}
