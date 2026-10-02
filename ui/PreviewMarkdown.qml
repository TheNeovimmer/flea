import QtQuick
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
    readonly property string accentHex: hexOf(Theme.color.accent)
    // Figures render only for the file under the cursor in the rendered
    // view: the Source view shows raw text and sends no request, and a path
    // change clears the block list, destroying delegates with their tickets.
    readonly property bool figuresArmed: root.active && root.view !== Markdown.SOURCE
    // The parse runs off the UI thread: the worker posts the block tree and the
    // UI shows the previous content or the loading state until it arrives. A
    // newer file cancels an older parse by sequence number.
    property var blockList: []
    property int parseSeq: 0
    property int appliedSeq: 0
    property bool parsing: false
    // True once a worker reply landed for this file; the lazy suite asserts it,
    // proving the WorkerScript path was taken and the parse never blocked input.
    property bool parsedOffThread: false
    property string parseError: ""
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
    // The render suite reads delegate geometry off the live tree, the way ColumnsArea does.
    // Only visible blocks plus the cache exist, so this answers null off screen.
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
    // One figure delegate's live state, for the figures suite: null while the
    // block is further than the cache from the viewport. A live delegate with
    // no answer and no ticket still sent nothing, so the far check reads those.
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
        onLoadFailed: root.readFailed = true
        onPathChanged: root.readFailed = false
    }

    // A WorkerScript logs one connect warning on this Qt however it is written,
    // so small files parse inline and never instantiate one; the worker serves
    // only large files, where the parse must leave the UI thread. Activated
    // imperatively in askParse: a binding lags the rawText change that fires it.
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

    // The worker owns the large parse; this timer is the dead-worker fallback,
    // never the path: it parses synchronously once rather than leaving no preview.
    Timer {
        id: parseFallback
        interval: 10000
        repeat: false
        onTriggered: {
            if (!root.parsing)
                return
            root.parsing = false
            root.blockList = Markdown.blocks(root.rawText, Markdown.dirOf(root.path),
                root.chromeHex, root.inkHex)
            root.appliedSeq = root.parseSeq
        }
    }

    function askParse() {
        if (!root.active || root.tooLarge || !file.loaded) {
            root.parsing = false
            return
        }
        root.parseSeq++
        root.parsing = true
        root.parseError = ""
        // Read off the live length: a binding on rawText still holds the
        // previous file when this change fires it. Creation is synchronous.
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

    // Both panes keep their heights warm across the Rendered/Source flip, so no
    // contentHeight binding forces a hidden pane's first layout from inside its
    // own evaluation, which Qt reports as a binding loop. A handler runs
    // outside any binding evaluation, so warming here settles nothing mid-read.
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

    // The rendered document instantiates only visible blocks plus a bounded
    // cache, the way the listing instantiates only its viewport: a 1 MiB
    // README opens without building thousands of delegates.
    ListView {
        id: body
        anchors.fill: parent
        clip: true
        visible: (!root.tooLarge && !root.readFailed && root.parseError === "")
            && root.view !== Markdown.SOURCE
        model: root.blockList
        spacing: Theme.spacing.gap
        cacheBuffer: 600
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
            id: blockDelegate
            property var block: modelData
            property int blockIndex: index
            width: ListView.view.width
            // True while any of this delegate shows in the viewport: figures ask
            // only here, so a block the viewport never reaches sends nothing.
            readonly property bool inView: {
                var v = ListView.view
                if (!v)
                    return true
                return (y + height >= v.contentY) && (y <= v.contentY + v.height)
            }
            // Only the drawn child lends its height; the rest hold no geometry that matters.
            height: block.type === "run" ? runText.height
                : block.type === "fence" ? fenceBox.height
                : block.type === "figure" ? figureBox.height
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
                    // widest cell plus 14 px. The column hugs its content at the left edge
                    // instead of filling the frame. Plain Grid/Column/Row, never QtQuick.Layouts,
                    // so the preview never loads the Layouts module.
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

                    // A figure draws through the shared service at the text width,
                    // scaled down to fit and never up. Same chrome surface and
                    // inset as a fenced block; a failure draws the source mono,
                    // exactly what the fence shows, with no new sentence or box.
                    Rectangle {
                        id: figureBox
                        objectName: "figureBox"
                        visible: block.type === "figure"
                        width: parent.width
                        height: figureItem.implicitHeight + 2 * Theme.spacing.gap
                        color: Theme.color.surface

                        Flea.MarkdownFigure {
                            id: figureItem
                            objectName: "figureItem"
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.gap
                            kind: block.type === "figure" ? block.kind : "math"
                            source: block.type === "figure" ? block.source : ""
                            display: true
                            askArmed: root.figuresArmed
                            inView: blockDelegate.inView
                            bgHex: root.chromeHex
                            fgHex: root.inkHex
                            accentHex: root.accentHex
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
                    // ordered alike, with the item text after each marker. Plain Column/Row,
                    // never QtQuick.Layouts, so the preview never loads the Layouts module.
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

                                Text {
                                    id: marker
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
