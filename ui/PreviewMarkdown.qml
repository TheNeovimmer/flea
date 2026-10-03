import QtQuick
import Quickshell.Io
import "." as Flea
import "js/Icons.js" as Icons
import "js/Markdown.js" as Markdown

// Rendered and Source previews share document insets, and only images beside the document can load.
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
    // The host supplies the code surface colour for its page.
    property color codeSurface: Theme.color.surface
    readonly property string borderHex: hexOf(Theme.color.muted)
    readonly property string chromeHex: hexOf(root.codeSurface)
    // The render suite reads the ink it asserts beside the border, same assembly, no coercion.
    readonly property string inkHex: hexOf(Theme.color.foreground)
    readonly property string accentHex: hexOf(Theme.color.accent)
    readonly property string mutedHex: hexOf(Theme.color.muted)
    readonly property string surfaceHex: hexOf(Theme.color.surface)
    // Only the active file in Rendered view may request figures.
    readonly property int insetX: Theme.spacing.rowPaddingX + Theme.spacing.rowPaddingY - Theme.spacing.hairline
    readonly property int insetY: Theme.spacing.gap + Theme.spacing.rowPaddingY
    // The 6 px gap above every block after the first is rowPaddingY (7), and the fence's 8 12 padding is gap (9) and rowPaddingX (14).
    readonly property int blockGap: Theme.spacing.rowPaddingY
    readonly property int fencePadX: Theme.spacing.rowPaddingX
    readonly property int fencePadY: Theme.spacing.gap
    // Headings are 20 and 15 px over the 14 px body, kept as ratios so every text size scales them; deeper levels are body bold.
    readonly property var headingRatio: [20 / 14, 15 / 14]
    function headingPx(level) {
        return Math.round(Theme.font.body * (level >= 1 && level <= root.headingRatio.length ? root.headingRatio[level - 1] : 1))
    }
    readonly property bool figuresArmed: root.active && root.view !== Markdown.SOURCE
    // Parse sequence numbers reject replies for an older file.
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
    readonly property bool loading: root.active && !root.readFailed && !root.tooLarge
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
    // An absent figure delegate answers null to the render probe.
    function figureInfo(i) {
        var d = blockItem(i)
        if (!d)
            return null
        var box = null
        var kids = d.children
        for (var k = 0; k < kids.length; k++)
            if (kids[k].objectName === "figureBox" && kids[k].visible)
                box = kids[k]
        if (!box)
            return null
        var fig = null
        var inner = box.children
        for (var m = 0; m < inner.length; m++)
            if (inner[m].objectName === "figureItem")
                fig = inner[m]
        if (!fig)
            return null
        return { ready: fig.ready, failed: fig.failed, working: fig.working, boxW: box.width,
            imgW: fig.fitWidth, imgH: fig.fitHeight }
    }
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

    // Large files require synchronous worker activation before their parse request.
    readonly property int workerThreshold: 65536
    Loader {
        id: parserLoader
        active: false
        sourceComponent: parserComponent
    }
    Component {
        id: parserComponent
        WorkerScript {
            source: "MarkdownWorker.js"
            onMessage: function (messageObject) { root.landed(messageObject) }
        }
    }
    function landed(messageObject) {
        if (messageObject.seq !== root.parseSeq)
            return
        root.parsing = false
        if (messageObject.error !== "") {
            root.parseError = messageObject.error
            return
        }
        root.parseError = ""
        root.blockList = messageObject.blocks
        root.appliedSeq = messageObject.seq
        root.parsedOffThread = true
    }

    // A dead worker triggers one synchronous recovery parse.
    Timer {
        id: parseFallback
        interval: root.parseFallbackMs
        repeat: false
        onTriggered: {
            if (!root.parsing)
                return
            root.parseSeq++
            root.parsing = false
            root.blockList = Markdown.blocks(root.rawText, Markdown.dirOf(root.path),
                root.chromeHex, root.inkHex)
            root.appliedSeq = root.parseSeq
        }
    }

    // Resolve images before Qt sees text: remote images become placeholders; only files beside the document load.
    function askParse() {
        root.parseSeq++
        if (!root.active || root.tooLarge || !file.loaded) {
            root.parsing = false
            return
        }
        root.parsing = true
        root.parseError = ""
        // The live text length determines worker activation before bindings update.
        var wantWorker = root.rawText.length > root.workerThreshold
        parserLoader.active = wantWorker
        var w = parserLoader.item
        if (wantWorker && w) {
            parseFallback.restart()
            w.sendMessage({ seq: root.parseSeq, source: root.rawText,
                dir: Markdown.dirOf(root.path), chrome: root.chromeHex, ink: root.inkHex })
            return
        }
        parserLoader.active = false
        parseFallback.stop()
        try {
            root.blockList = Markdown.blocks(root.rawText, Markdown.dirOf(root.path),
                root.chromeHex, root.inkHex)
        } catch (e) {
            root.parseError = String(e)
            root.parsing = false
            return
        }
        root.parseError = ""
        root.appliedSeq = root.parseSeq
        root.parsing = false
    }

    onRawTextChanged: root.askParse()
    onActiveChanged: root.askParse()
    onPathChanged: {
        root.blockList = []
        root.parsedOffThread = false
        root.askParse()
    }

    // Warming both view heights prevents a contentHeight binding loop on Rendered/Source changes.
    onViewChanged: {
        body.contentHeight
        sourceText.implicitHeight
    }

    Flickable {
        id: sourceFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, sourceText.implicitHeight + 2 * root.insetY)
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
            x: root.insetX
            y: root.insetY
            width: sourceFlick.width - 2 * root.insetX
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
        anchors.leftMargin: root.insetX
        anchors.rightMargin: root.insetX
        clip: true
        visible: (!root.tooLarge && !root.readFailed && root.parseError === "")
            && root.view !== Markdown.SOURCE
        model: root.blockList
        spacing: root.blockGap
        topMargin: root.insetY
        bottomMargin: root.insetY
        cacheBuffer: root.blockCachePixels
        focus: false

        // The wheel and the bar belong to the frame, not to the inset list, so both sit on the root.
        FastScrollHandler {
            parent: root
            flickable: body
            visible: body.visible
        }

        Flea.ViewportScrollBar {
            parent: root
            anchors { top: parent.top; right: parent.right }
            flickable: body
        }

        delegate: Item {
            id: blockDelegate
            property var block: modelData
            property int blockIndex: index
            width: ListView.view.width
            // Only a figure intersecting the viewport may send a render request.
            readonly property bool inView: {
                var v = ListView.view
                if (!v)
                    return true
                return (y + height >= v.contentY) && (y <= v.contentY + v.height)
            }
            // Only the drawn child lends its height; the rest hold no geometry that matters.
            height: block.type === "run" || block.type === "heading" ? runText.height
                : block.type === "fence" ? fenceBox.height
                : block.type === "figure" ? figureBox.height
                : block.type === "quote" ? quoteRow.height
                : block.type === "remote" ? remoteBox.height
                : block.type === "list" ? listGrid.height
                : block.type === "table" ? tableGrid.height : localImage.height

                    // Headings use the prescribed bold text size and line box.
                    Flea.MarkdownText {
                        id: runText
                        visible: block.type === "run" || block.type === "heading"
                        width: parent.width
                        text: block.type === "run" || block.type === "heading" ? block.text : ""
                        font.pixelSize: block.type === "heading" ? root.headingPx(block.level) : Theme.font.body
                        font.bold: block.type === "heading"
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
                                delegate: Flea.MarkdownText {
                                    width: tableGrid.colWidth(index)
                                    cellPad: 2
                                    text: block.head[index]
                                    horizontalAlignment: tableGrid.alignAt(index)
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
                                        delegate: Flea.MarkdownText {
                                            width: tableGrid.colWidth(index)
                                            cellPad: 2
                                            text: tableGrid.cellAt(row, index)
                                            horizontalAlignment: tableGrid.alignAt(index)
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
                            var bestLength = 0
                            if (block.type !== "table")
                                return best
                            var cells = [block.head].concat(block.rows)
                            for (var r = 0; r < cells.length; r++) {
                                var row = cells[r]
                                var raw = col < row.length ? row[col] : ""
                                var decoded = String(raw).replace(/&#(\d+);/g, function (m, n) {
                                    return String.fromCharCode(parseInt(n, 10))
                                })
                                if (decoded.length > bestLength) {
                                    best = raw
                                    bestLength = decoded.length
                                }
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
                            textFormat: Text.MarkdownText
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.body
                        }
                    }

                    // A fenced block is a filled block on the code surface with no border.
                    Rectangle {
                        id: fenceBox
                        objectName: "fenceBox"
                        visible: block.type === "fence"
                        width: parent.width
                        height: fenceText.implicitHeight + 2 * root.fencePadY
                        color: root.codeSurface

                        Text {
                            id: fenceText
                            anchors.fill: parent
                            anchors.leftMargin: root.fencePadX
                            anchors.rightMargin: root.fencePadX
                            anchors.topMargin: root.fencePadY
                            anchors.bottomMargin: root.fencePadY
                            text: block.type === "fence" ? block.text : ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: Theme.color.foreground
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.body
                        }
                    }

                    // Display maths use the figure fallback's vertical inset; the list owns the block gap.
                    Item {
                        id: figureBox
                        objectName: "figureBox"
                        visible: block.type === "figure"
                        width: parent.width
                        readonly property int figureInset: figureItem.ready && figureItem.kind === "math" && figureItem.fitHeight > 0 ? root.fencePadY : 0
                        height: figureItem.implicitHeight + 2 * figureInset

                        Flea.MarkdownFigure {
                            id: figureItem
                            objectName: "figureItem"
                            y: parent.figureInset
                            width: parent.width
                            kind: block.type === "figure" ? block.kind : "math"
                            source: block.type === "figure" ? block.source : ""
                            display: true
                            askArmed: root.figuresArmed
                            inView: blockDelegate.inView
                            bgHex: root.hexOf(Theme.color.background)
                            fgHex: root.inkHex
                            accentHex: root.accentHex
                            mutedHex: root.mutedHex
                            surfaceHex: root.surfaceHex
                            fallbackColor: root.codeSurface
                            fontFamily: Theme.font.family
                            bodyPx: Theme.font.body
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

                        Flea.MarkdownText {
                            id: quoteText
                            width: parent.width - 2 - parent.spacing
                            text: block.type === "quote" ? block.text : ""
                        }
                    }

                    // Draw top-level list markers at the text edge with text after each marker using plain Column/Row, keeping QtQuick.Layouts unloaded.
                    Column {
                        id: listGrid
                        visible: block.type === "list"
                        width: parent.width
                        spacing: 0

                        Repeater {
                            model: block.type === "list" ? block.items.length : 0
                            delegate: Row {
                                width: listGrid.width
                                spacing: Theme.spacing.gap

                                Flea.MarkdownText {
                                    id: marker
                                    text: block.ordered ? (block.start + index) + "." : "•"
                                    // The marker shares the item's line box and first-line leading.
                                    textFormat: Text.RichText
                                    height: marker.box
                                    wrapMode: Text.NoWrap
                                }

                                Flea.MarkdownText {
                                    width: parent.width - marker.width - parent.spacing
                                    text: block.items[index]
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
