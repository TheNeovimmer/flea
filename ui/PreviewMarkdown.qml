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
    // "rendered" or "source"; anything else reads as rendered. Only the Quick Look's r asks for source.
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
    readonly property int insetX: Theme.spacing.rowPaddingX + Theme.spacing.rowPaddingY - Theme.spacing.hairline
    readonly property int insetY: Theme.spacing.gap + Theme.spacing.rowPaddingY
    // RenderedPreviews resolves its pixels at body 14, and each one follows the body from there: no spacing token equals them at any size.
    readonly property int boardBody: 14
    readonly property int boardBlockGap: 6
    readonly property int boardFencePadX: 12
    readonly property int boardFencePadY: 8
    // Headings are 20 and 15 px at body 14 in both surfaces, over the body the surface sets; deeper levels are body bold.
    readonly property var boardHeadings: [20, 15]
    function boardPx(px) {
        return Math.round(px * Theme.font.body / root.boardBody)
    }
    readonly property int blockGap: root.boardPx(root.boardBlockGap)
    readonly property int fencePadX: root.boardPx(root.boardFencePadX)
    readonly property int fencePadY: root.boardPx(root.boardFencePadY)
    // The preview column sets the document one token under Quick Look's body (RenderedPreviews 13 against 14).
    property bool compact: false
    readonly property int bodyPx: root.compact ? Theme.font.bodySmall : Theme.font.body
    // The faint rule wash the Quick Look bar's bottom hairline draws, shared by the table's header and row rules.
    readonly property real ruleOpacity: 0.12
    // RenderedPreviews' remote box is a 1 px CSS dashed border: 3 px dashes with 3 px gaps.
    readonly property int dashPx: 3
    readonly property int dashPitch: 2 * root.dashPx
    function headingPx(level) {
        return level >= 1 && level <= root.boardHeadings.length ? root.boardPx(root.boardHeadings[level - 1]) : root.bodyPx
    }
    // Only the active file in Rendered view may request figures.
    readonly property bool figuresArmed: root.active && root.view !== Markdown.SOURCE
    // A parsed document that may ask for figures starts the helper at once, so it is warm when the first one is asked for.
    readonly property var warmBlocks: root.figuresArmed && root.blocksReady && file.loaded && !root.tooLarge ? root.blockList : []
    onWarmBlocksChanged: FigureService.warm(root.warmBlocks)
    // Parse sequence numbers reject replies for an older file.
    property var blockList: []
    property int parseSeq: 0
    property int appliedSeq: 0
    property bool parsing: false
    // Parses that really ran (worker message or synchronous), so a suite counts one per event.
    property int parseRuns: 0
    // Loads of the shown file that landed, so a suite can tell a save the watcher read from one it never saw.
    property int loadRuns: 0
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
    // The offset the wheel moved, in whichever view shows, for Quick Look's IPC.
    readonly property real scrollY: root.view === Markdown.SOURCE ? sourceFlick.contentY : body.contentY
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
        // The one watcher is on the shown file; a path change re-points it, so an old file never reloads here.
        watchChanges: true
        // The first event opens the window and the rest land inside it: a restart would starve a file written without pause.
        onFileChanged: if (!reloadCoalesce.running) reloadCoalesce.start()
        onLoaded: {
            root.loadRuns++
            // A save that unlinks and recreates the file can fail one reload; the next good load clears it.
            root.readFailed = false
            root.askParse()
        }
        onLoadFailed: {
            root.keepScroll = false
            root.readFailed = true
        }
        onPathChanged: root.readFailed = false
    }

    // One reload per save: an editor's truncate, write and rename raise events within a few ms, and 50 ms is under what a reader notices.
    readonly property int reloadCoalesceMs: 50
    Timer {
        id: reloadCoalesce
        interval: root.reloadCoalesceMs
        repeat: false
        onTriggered: root.reloadFromDisk()
    }

    // A reparse of the shown file (disk edit, theme change) puts the reader back where they were.
    property real savedY: 0
    property bool keepScroll: false
    // Where a restore left the view when the content was too short for the saved place, NaN when none waits.
    property real heldY: NaN
    // Two positions this close are the same place: the list stores contentY as a float.
    readonly property real samePlacePx: 1
    // True while the model is replaced: the list moves itself to its top then, and restoreScroll puts the view back.
    property bool settingBlocks: false
    // A place waiting for taller content ends the moment the reader moves the view away from it.
    function releaseHeldPlace() {
        if (root.settingBlocks || isNaN(root.heldY) || Math.abs(body.contentY - root.heldY) < root.samePlacePx)
            return
        root.keepScroll = false
        root.heldY = NaN
    }
    // A place waiting for taller content is kept; otherwise the reader's present place is saved (each landing asks first).
    function rememberScroll() {
        if (root.keepScroll)
            return
        root.savedY = body.contentY
        root.keepScroll = true
        // A path change or a failed load ends a hold without clearing its place, so a new place starts with none.
        root.heldY = NaN
    }
    // The view rests between the list's own resting top and the end of the new content, and a model too short for the place keeps it.
    function restoreScroll() {
        if (!root.keepScroll)
            return
        var top = body.originY - body.topMargin
        var end = Math.max(top, body.originY + body.contentHeight - body.height + body.bottomMargin)
        var at = Math.max(top, Math.min(root.savedY, end))
        var settled = root.savedY <= end
        // The hold is recorded before the move, so the move itself reads as the same place.
        root.heldY = settled ? NaN : at
        body.contentY = at
        if (settled)
            root.keepScroll = false
    }
    // The content height last seen, which is where the end was before a block grew.
    property real seenHeight: 0
    // Whether the last block had a delegate at the last height change, so the end then was a drawn end and no estimate.
    property bool endBuilt: false
    // The snap below sets contentY itself, and the height can settle again under it.
    property bool snappingToEnd: false
    function noteEnd() {
        root.endBuilt = root.blockItem(root.blockList.length - 1) !== null
    }
    // A picture decodes after its block was built at no height; only a reader at the drawn end follows it, never one in unbuilt blocks.
    function holdEnd() {
        var was = root.seenHeight
        var builtBefore = root.endBuilt
        root.seenHeight = body.contentHeight
        root.noteEnd()
        if (root.snappingToEnd || !builtBefore || !(body.contentHeight > was))
            return
        var wasEnd = body.originY + was - body.height + body.bottomMargin
        var tallerThanView = wasEnd > body.originY - body.topMargin
        if (!tallerThanView || body.contentY < wasEnd - root.samePlacePx)
            return
        root.snappingToEnd = true
        body.contentY = body.originY + body.contentHeight - body.height + body.bottomMargin
        root.snappingToEnd = false
    }
    // How far the last block's bottom and the inset under it lie past the viewport, 0 when whole, -1 when the last block is not built.
    function endGap() {
        var last = root.blockItem(root.blockList.length - 1)
        return last === null ? -1 : Math.max(0, Math.round(last.mapToItem(body, 0, last.height).y + body.bottomMargin - body.height))
    }
    function reloadFromDisk() {
        if (!root.active || root.tooLarge)
            return
        file.reload()
    }
    // Link ink and code chrome are parsed into the runs, so a theme change reparses the loaded file.
    function reparseForTheme() {
        if (!root.active || !file.loaded)
            return
        root.askParse()
    }
    // A theme switch moves ink and chrome in one turn, so both ask through one callLater and the parse sees both.
    onInkHexChanged: Qt.callLater(root.reparseForTheme)
    onChromeHexChanged: Qt.callLater(root.reparseForTheme)

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
        root.appliedSeq = messageObject.seq
        if (messageObject.error !== "") {
            root.parseError = messageObject.error
            root.askedAny = false
            return
        }
        root.parseError = ""
        // The reader's present place is taken before the model reset moves the list to its top; a place that waits is kept.
        root.rememberScroll()
        root.settingBlocks = true
        root.blockList = messageObject.blocks
        root.settingBlocks = false
        // A reply that changed nothing the list sees raises no model change, so the saved place is released here.
        root.restoreScroll()
        root.parsedOffThread = true
    }

    // The worker parses only above workerThreshold; this timer recovers a worker request whose reply never settles.
    Timer {
        id: parseFallback
        interval: root.parseFallbackMs
        repeat: false
        onTriggered: {
            if (!root.parsing)
                return
            // A late worker reply for the request being recovered is voided by the new number.
            root.parseSeq++
            root.parseNow(root.askedText, root.askedDir, root.askedChrome, root.askedInk)
        }
    }

    // The last parsed request's text, folder, chrome and ink; a reload's second trigger (onRawTextChanged after onLoaded) is skipped.
    property string askedText: ""
    property string askedDir: ""
    property string askedChrome: ""
    property string askedInk: ""
    property bool askedAny: false
    // Forget the last request and void any worker reply in flight, so the next ask always parses.
    function dropParse() {
        root.parseSeq++
        root.parsing = false
        root.askedAny = false
        root.askedText = ""
    }

    // The synchronous parse of one request, landed like a worker reply: the small-file path and the worker's recovery both end here.
    function parseNow(text, dir, chrome, ink) {
        var blocks
        try {
            blocks = Markdown.blocks(text, dir, chrome, ink)
        } catch (e) {
            root.parseError = String(e.message || e)
            root.appliedSeq = root.parseSeq
            root.parsing = false
            root.askedAny = false
            return
        }
        // Taken once the parse is good and before the model reset, like the worker landing: a parse that throws takes no place.
        root.rememberScroll()
        root.settingBlocks = true
        root.blockList = blocks
        root.settingBlocks = false
        root.parseError = ""
        root.appliedSeq = root.parseSeq
        root.parsing = false
        root.restoreScroll()
    }

    // Resolve images before Qt sees text: remote images become placeholders; only files beside the document load.
    function askParse() {
        if (!root.active || root.tooLarge || !file.loaded) {
            root.parseError = ""
            root.dropParse()
            return
        }
        // Read the file's own text: onLoaded can run before the rawText binding has caught up.
        var text = file.text()
        var dir = Markdown.dirOf(root.path)
        if (root.askedAny && text === root.askedText && dir === root.askedDir
                && root.chromeHex === root.askedChrome && root.inkHex === root.askedInk) {
            return
        }
        // Only a request that goes on to parse clears an error; a skipped one has nothing to replace it with.
        root.parseError = ""
        root.askedAny = true
        root.askedText = text
        root.askedDir = dir
        root.askedChrome = root.chromeHex
        root.askedInk = root.inkHex
        root.parseSeq++
        root.parseRuns++
        root.parsing = true
        // The live text length determines worker activation before bindings update.
        var wantWorker = text.length > root.workerThreshold
        parserLoader.active = wantWorker
        var w = parserLoader.item
        if (wantWorker && w) {
            parseFallback.restart()
            w.sendMessage({ seq: root.parseSeq, source: text, dir: dir, chrome: root.chromeHex, ink: root.inkHex })
            return
        }
        parserLoader.active = false
        parseFallback.stop()
        root.parseNow(text, dir, root.chromeHex, root.inkHex)
    }

    onRawTextChanged: root.askParse()
    onActiveChanged: root.askParse()
    onPathChanged: {
        // A save's pending reload belongs to the old file.
        reloadCoalesce.stop()
        root.keepScroll = false
        root.parseError = ""
        root.blockList = []
        root.parsedOffThread = false
        // The new file's load asks; asking now would parse the old file's text under the new path.
        root.dropParse()
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
        contentHeight: Math.max(height, sourceText.measuredHeight + 2 * root.insetY)
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
            // Measure Source outside the scroll-height binding, where Text's lazy getter can relayout and notify.
            property real measuredHeight: 0
            onImplicitHeightChanged: if (root.view === Markdown.SOURCE) sourceText.measuredHeight = sourceText.implicitHeight
            onVisibleChanged: if (root.view === Markdown.SOURCE) sourceText.measuredHeight = sourceText.implicitHeight
            x: root.insetX
            y: root.insetY
            width: sourceFlick.width - 2 * root.insetX
            text: root.rawText
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: root.bodyPx
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
        // A new model resets the view to its origin, so the saved place is restored once that reset is done.
        onModelChanged: root.restoreScroll()
        onContentYChanged: root.releaseHeldPlace()
        onContentHeightChanged: root.holdEnd()
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
                : block.type === "list" ? listGrid.height + listGrid.y
                : block.type === "table" ? tableGrid.height + tableGrid.y : localImage.height

                    // Headings use the prescribed bold text size and line box.
                    Flea.MarkdownText {
                        id: runText
                        linkGate: Markdown.isExternalLink
                        visible: block.type === "run" || block.type === "heading"
                        width: parent.width
                        text: block.type === "run" || block.type === "heading" ? block.text : ""
                        font.pixelSize: block.type === "heading" ? root.headingPx(block.level) : root.bodyPx
                        font.bold: block.type === "heading"
                        // h1 and h2 take the bright foreground; deeper levels and body stay the foreground.
                        color: block.type === "heading" && block.level <= root.boardHeadings.length ? Theme.color.foregroundBright : Theme.color.foreground
                    }

                    // Tables hug their cells with Grid, Column and Row, never QtQuick.Layouts, so the preview never loads it.
                    Column {
                        id: tableGrid
                        visible: block.type === "table"
                        // A chunk after the first sits flush under its predecessor, across the gap the list puts between blocks.
                        y: block.joined === true ? -root.blockGap : 0
                        width: tableGrid.tableWidth()
                        spacing: 0

                        Row {
                            id: headerRow
                            spacing: 0

                            Repeater {
                                model: block.type === "table" ? block.head.length : 0
                                delegate: Flea.MarkdownText {
                                    linkGate: Markdown.isExternalLink
                                    width: tableGrid.colWidth(index)
                                    bodyPx: root.bodyPx
                                    cellPad: 2
                                    text: block.head[index]
                                    horizontalAlignment: tableGrid.alignAt(index)
                                    font.bold: true
                                    color: Theme.color.foregroundBright
                                }
                            }
                        }

                        Rectangle {
                            visible: block.type === "table" && block.head.length > 0
                            width: tableGrid.tableWidth()
                            height: Theme.spacing.hairline
                            color: Theme.color.foreground
                            opacity: root.ruleOpacity
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
                                            linkGate: Markdown.isExternalLink
                                            width: tableGrid.colWidth(index)
                                            bodyPx: root.bodyPx
                                            cellPad: 2
                                            text: tableGrid.cellAt(row, index)
                                            horizontalAlignment: tableGrid.alignAt(index)
                                        }
                                    }
                                }

                                Rectangle {
                                    width: tableGrid.tableWidth()
                                    height: Theme.spacing.hairline
                                    color: Theme.color.foreground
                                    opacity: root.ruleOpacity
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

                    // Invisible measurers carry each column's longest cell, measured by the parser over the whole table, so chunks of one table share widths.
                    Repeater {
                        id: measurers
                        model: block.type === "table" ? tableGrid.columns : 0
                        delegate: Text {
                            visible: false
                            text: block.type === "table" && index < block.measure.length ? block.measure[index] : ""
                            textFormat: Text.MarkdownText
                            font.family: Theme.font.family
                            font.pixelSize: root.bodyPx
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
                            font.pixelSize: root.bodyPx
                        }
                    }

                    // Display maths use the figure fallback's vertical inset; the list owns the block gap.
                    Item {
                        id: figureBox
                        objectName: "figureBox"
                        visible: block.type === "figure"
                        width: parent.width
                        readonly property int figureInset: figureItem.ready && figureItem.kind === "math" && figureItem.fitHeight > 0 ? Theme.spacing.gap : 0
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
                            bodyPx: root.bodyPx
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
                            linkGate: Markdown.isExternalLink
                            width: parent.width - 2 - parent.spacing
                            bodyPx: root.bodyPx
                            text: block.type === "quote" ? block.text : ""
                        }
                    }

                    // Draw top-level list markers at the text edge with text after each marker using plain Column/Row, keeping QtQuick.Layouts unloaded.
                    Column {
                        id: listGrid
                        visible: block.type === "list"
                        // A chunk after the first sits flush under its predecessor, across the gap the list puts between blocks.
                        y: block.joined === true ? -root.blockGap : 0
                        width: parent.width
                        spacing: 0

                        TextMetrics {
                            id: listMarkerMetrics
                            text: block.type !== "list" ? "" : block.ordered
                                ? (block.last !== undefined ? block.last : block.start + block.items.length - 1) + "." : "•"
                            font.family: Theme.font.family
                            font.pixelSize: root.bodyPx
                        }

                        Repeater {
                            model: block.type === "list" ? block.items.length : 0
                            delegate: Row {
                                width: listGrid.width
                                spacing: Theme.spacing.gap

                                Flea.MarkdownText {
                                    id: marker
                                    width: listMarkerMetrics.advanceWidth
                                    bodyPx: root.bodyPx
                                    text: block.ordered ? (block.start + index) + "." : "•"
                                    // The marker shares the item's line box and first-line leading.
                                    textFormat: Text.RichText
                                    height: marker.box
                                    wrapMode: Text.NoWrap
                                }

                                Flea.MarkdownText {
                                    linkGate: Markdown.isExternalLink
                                    width: parent.width - marker.width - parent.spacing
                                    bodyPx: root.bodyPx
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
                            spacing: root.dashPx
                            Repeater {
                                model: Math.max(1, Math.floor((remoteBox.width + root.dashPx) / root.dashPitch))
                                delegate: Rectangle { width: root.dashPx; height: Theme.spacing.hairline; color: Theme.color.muted }
                            }
                        }

                        Row {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: root.dashPx
                            Repeater {
                                model: Math.max(1, Math.floor((remoteBox.width + root.dashPx) / root.dashPitch))
                                delegate: Rectangle { width: root.dashPx; height: Theme.spacing.hairline; color: Theme.color.muted }
                            }
                        }

                        Column {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            spacing: root.dashPx
                            Repeater {
                                model: Math.max(1, Math.floor((remoteBox.height + root.dashPx) / root.dashPitch))
                                delegate: Rectangle { width: Theme.spacing.hairline; height: root.dashPx; color: Theme.color.muted }
                            }
                        }

                        Column {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            spacing: root.dashPx
                            Repeater {
                                model: Math.max(1, Math.floor((remoteBox.height + root.dashPx) / root.dashPitch))
                                delegate: Rectangle { width: Theme.spacing.hairline; height: root.dashPx; color: Theme.color.muted }
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
                        // A picture narrower than the content sits on the text's left edge, as the board's stand-in does.
                        horizontalAlignment: Image.AlignLeft
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
