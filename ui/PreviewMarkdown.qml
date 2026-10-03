import QtQuick
import Quickshell.Io
import "." as Flea
import "js/Icons.js" as Icons
import "js/Markdown.js" as Markdown

// Read Markdown on demand: render parsed blocks or verbatim source, resolve image URLs before Qt sees them, box remote images, load only beside the document, and leave links inert.
Item {
    id: root

    property bool active: false
    property string path: ""
    property int size: 0
    // "rendered" or "source"; anything else reads as rendered, the board's default.
    property string view: Markdown.RENDERED

    // FileView reads whole files, so refuse above maxBytes, with remote storage keeping its smaller 256 KiB gate.
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
    // Sequence numbers reject superseded worker parses while the UI holds content or shows loading.
    property var blockList: []
    property int parseSeq: 0
    property int appliedSeq: 0
    property bool parsing: false
    // A worker reply landed for this file; the lazy suite asserts the parse left the UI thread.
    property bool parsedOffThread: false
    property string parseError: ""
    // Give the worker ten seconds to answer before the synchronous recovery parse.
    readonly property int parseFallbackMs: 10000
    // Keep this many pixels of blocks warm beyond the visible ListView window.
    readonly property int blockCachePixels: 600
    readonly property bool blocksReady: root.appliedSeq === root.parseSeq && !root.parsing
    readonly property bool loading: root.active && !root.readFailed && !root.tooLarge && root.parseError === ""
        && (!file.loaded || !root.blocksReady)
    readonly property string status: {
        if (root.tooLarge) return "This file is too large to preview."
        if (root.readFailed || root.parseError !== "") return "This file could not be read."
        return root.blocksReady && file.loaded ? "ready" : "loading"
    }
    readonly property string lineLabel: Markdown.countLine(Markdown.lineCount(root.rawText))
    // The bar's line count reads only once there is a file behind it, never "0 lines" first.
    readonly property bool contentReady: file.loaded && root.blocksReady
        && !root.tooLarge && !root.readFailed && root.parseError === ""
    // True when the reader has settled with nothing to put in the frame, the way PreviewLines.blank reads.
    readonly property bool blank: root.tooLarge
        || (root.active && !root.readFailed && file.loaded && root.rawText.length === 0)

    readonly property Item bodyItem: body
    // The render suite reads live delegate geometry; only visible blocks plus the cache exist, so offscreen blocks answer null.
    function blockItem(i) {
        var kids = body.contentItem.children
        for (var k = 0; k < kids.length; k++) {
            if (kids[k].blockIndex === i)
                return kids[k]
        }
        return null
    }
    // Instantiated delegates only: the lazy suite asserts this stays bounded.
    function delegateCount() { return body.contentItem.children.length }
    readonly property real flickContentHeight: sourceFlick.visible
        ? sourceFlick.contentHeight : body.contentHeight

    visible: root.active

    FileView {
        id: file
        path: (root.active && !root.tooLarge) ? root.path : ""
        printErrors: false
        onLoaded: root.askParse()
        onLoadFailed: root.readFailed = true
        onPathChanged: root.readFailed = false
    }

    WorkerScript {
        id: parser
        source: "MarkdownWorker.js"
        onMessage: function (messageObject) {
            if (messageObject.seq !== root.parseSeq)
                return
            root.parsing = false
            root.appliedSeq = messageObject.seq
            if (messageObject.error !== "") {
                root.parseError = messageObject.error
                return
            }
            root.parseError = ""
            root.blockList = messageObject.blocks
            root.parsedOffThread = true
        }
    }

    // The worker owns parsing; this timer recovers synchronously only if its reply never settles the request.
    Timer {
        id: parseFallback
        interval: root.parseFallbackMs
        repeat: false
        onTriggered: {
            if (!root.parsing)
                return
            root.parseSeq++
            root.parsing = false
            try {
                root.blockList = Markdown.blocks(root.rawText, Markdown.dirOf(root.path),
                    root.chromeHex, root.inkHex)
                root.parseError = ""
            } catch (error) {
                root.parseError = String(error.message || error)
            }
            root.appliedSeq = root.parseSeq
        }
    }

    function askParse() {
        root.parseSeq++
        root.parseError = ""
        if (!root.active || root.tooLarge || !file.loaded) {
            root.parsing = false
            return
        }
        root.parsing = true
        parseFallback.restart()
        parser.sendMessage({ seq: root.parseSeq, source: root.rawText,
            dir: Markdown.dirOf(root.path), chrome: root.chromeHex, ink: root.inkHex })
    }

    onRawTextChanged: root.askParse()
    onActiveChanged: root.askParse()
    onPathChanged: {
        root.parseError = ""
        root.blockList = []
        root.parsedOffThread = false
        root.askParse()
    }

    // Warm both heights outside binding evaluation on a Rendered/Source flip, preventing hidden-pane layout from causing a contentHeight binding loop.
    onViewChanged: {
        body.contentHeight
        sourceText.implicitHeight
    }

    Flickable {
        id: sourceFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, sourceText.implicitHeight)
        visible: (!root.tooLarge && !root.readFailed && root.parseError === "")
            && root.view === Markdown.SOURCE

        FastScrollHandler {
            parent: sourceFlick
            flickable: sourceFlick
        }

        Flea.ViewportScrollBar {
            parent: sourceFlick
            anchors { top: parent.top; right: parent.right }
            flickable: sourceFlick
        }

        Text {
            id: sourceText
            width: parent.width
            text: root.rawText
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
        }
    }

    // Render only visible blocks and a bounded cache, even for a 1 MiB document.
    ListView {
        id: body
        anchors.fill: parent
        clip: true
        visible: (!root.tooLarge && !root.readFailed && root.parseError === "")
            && root.view !== Markdown.SOURCE
        model: root.blockList
        spacing: Theme.spacing.gap
        cacheBuffer: root.blockCachePixels
        focus: false

        FastScrollHandler {
            parent: body
            flickable: body
        }

        Flea.ViewportScrollBar {
            parent: body
            anchors { top: parent.top; right: parent.right }
            flickable: body
        }

        delegate: Item {
            property var block: modelData
            property int blockIndex: index
            width: ListView.view.width
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

                    // Tables hug their cells with Grid, Column and Row, never QtQuick.Layouts, so the preview never loads it.
                    Column {
                        id: tableGrid
                        visible: block.type === "table"
                        width: tableGrid.tableWidth()
                        spacing: 0

                        Row {
                            id: headerRow
                            spacing: 0

                            Repeater {
                                model: block.type === "table" ? block.head.length : 0
                                delegate: Text {
                                    width: tableGrid.colWidth(index)
                                    topPadding: 2
                                    bottomPadding: 2
                                    text: block.head[index]
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
                        }

                        Rectangle {
                            width: tableGrid.tableWidth()
                            height: Theme.spacing.hairline
                            color: Theme.color.muted
                        }

                        Repeater {
                            model: block.type === "table" ? block.rows.length : 0
                            delegate: Column {
                                readonly property int row: index
                                width: tableGrid.tableWidth()
                                spacing: 0

                                Row {
                                    spacing: 0

                                    Repeater {
                                        model: tableGrid.columns
                                        delegate: Text {
                                            width: tableGrid.colWidth(index)
                                            topPadding: 2
                                            bottomPadding: 2
                                            text: tableGrid.cellAt(row, index)
                                            textFormat: Text.MarkdownText
                                            wrapMode: Text.Wrap
                                            horizontalAlignment: tableGrid.alignAt(index)
                                            color: Theme.color.foreground
                                            linkColor: Theme.color.foreground
                                            font.family: Theme.font.family
                                            font.pixelSize: Theme.font.body
                                        }
                                    }
                                }

                                Rectangle {
                                    width: tableGrid.tableWidth()
                                    height: Theme.spacing.hairline
                                    color: Theme.color.muted
                                }
                            }
                        }

                        // Helpers over the block, so delegates read cells and alignment by place.
                        readonly property int columns: block.type === "table" ? Math.max(1, block.cols) : 1
                        function alignName(i) {
                            var names = block.type === "table" ? block.aligns : []
                            return i < names.length ? names[i] : "left"
                        }
                        function alignAt(i) {
                            var name = alignName(i)
                            return name === "center" ? Text.AlignHCenter : name === "right" ? Text.AlignRight : Text.AlignLeft
                        }
                        readonly property int cellCount: block.type === "table" ? block.rows.length * tableGrid.columns : 0
                        function cellAt(r, c) {
                            var rows = block.type === "table" ? block.rows : []
                            return r < rows.length && c < rows[r].length ? rows[r][c] : ""
                        }
                        // Invisibly measure each column's decoded longest cell beside the grid, so the next column starts after its widest rendered cell.
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
                            // Count and implicitWidth notify when a measurer arrives and lays out; itemAt alone notifies nothing.
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

                    // Invisible measurers carry each column's longest cell to size columns to content without entering the grid's layout.
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

                    // Draw top-level list markers at the text edge with text after each marker using plain Column/Row, keeping QtQuick.Layouts unloaded.
                    Column {
                        id: listGrid
                        visible: block.type === "list"
                        width: parent.width
                        spacing: 0

                        TextMetrics {
                            id: listMarkerMetrics
                            text: block.type !== "list" ? "" : block.ordered
                                ? (block.start + block.items.length - 1) + "." : "•"
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.body
                        }

                        Repeater {
                            model: block.type === "list" ? block.items.length : 0
                            delegate: Row {
                                width: listGrid.width
                                spacing: Theme.spacing.gap

                                Text {
                                    id: marker
                                    width: listMarkerMetrics.advanceWidth
                                    text: block.ordered ? (block.start + index) + "." : "•"
                                    color: Theme.color.foreground
                                    font.family: Theme.font.family
                                    font.pixelSize: Theme.font.body
                                    textFormat: Text.PlainText
                                }

                                Text {
                                    width: parent.width - marker.width - parent.spacing
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
                    }

                    // The board's placeholder spans the content with a dashed muted box around a left-aligned muted image glyph and sentence on one line.
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

    Text {
        anchors.centerIn: parent
        visible: root.tooLarge || root.readFailed || root.parseError !== ""
        text: root.status
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
        textFormat: Text.PlainText
    }
}
