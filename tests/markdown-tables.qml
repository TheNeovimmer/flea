//@ pragma ShellId flea-markdown-tables-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "markdown-tables.js" as Tables
import "markdown-tables-scroll.js" as Sideways
import "markdown-markers.js" as Markers

// Every table case document, set in Quick Look's MarkdownPane and in the preview column's compact PreviewMarkdown at the board's text size 14, judged on geometry and grabbed.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_TABLES " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    readonly property string dir: Quickshell.env("FLEA_TABLES_DIR")
    readonly property string outDir: Quickshell.env("XDG_RUNTIME_DIR")
    readonly property var cases: Quickshell.env("FLEA_TABLES_CASES").split(",")
    // The board's text size, and the two widths: Quick Look's card, and the column's markdown frame.
    readonly property int boardText: 14
    readonly property int cardWidth: 840
    readonly property int columnWidth: 250
    readonly property int paneHeight: 900
    // The panes shrink to hold the wheel's point and this much below it, so the document is taller than the view and a vertical wheel has room to move it.
    readonly property int wheelPaneMargin: 12
    // The panes widen to this for the resize check, wide enough that most tables fit.
    readonly property int wideFrame: 4000
    // The hosted column's offset in its host and the spacer above its table, none zero so a dropped offset shows.
    readonly property int hostX: 11
    readonly property int hostY: 23
    readonly property int hostSpacer: 17
    // Tables that stopped overflowing in the widen check, which must be at least one.
    property int drops: 0
    property var scrollsBefore: [0, 0]
    // A case is quiet once both panes' content height held still this many frames.
    readonly property int quietFrames: 8
    // Frames a path change may take to drop the old document before the new one is awaited anyway.
    readonly property int dropFrames: 30
    // The test gives up on its own verdict after this long, so a hung stage fails and the run ends.
    readonly property int watchdogMs: 120000
    // A picture-wide column must price glyphs like a text-only one at the same size, never by its picture.
    readonly property real pictureRatio: 1.5
    // The text the panes showed before the path moved, so the drop ends only on the new file's own load.
    property string prevText: ""
    property var prevCardBlocks: null
    property var prevColumnBlocks: null
    property int checks: 0
    property int failures: 0
    property bool done: false
    property int at: -1
    property string stage: "next"
    property int waited: 0
    property int quiet: 0
    property real lastHeights: -1
    property var geos: ({})
    property var pending: []
    // The frame each grab keeps: the whole pane while a case settles, then just the document's own height.
    property int cardShot: paneHeight
    property int columnShot: paneHeight

    Component.onCompleted: Flea.ViewState.state = { display: { textSize: { mode: shell.boardText } } }

    function check(error, name) {
        checks++
        if (error !== "")
            failures++
        shell.log((error === "" ? "CHECK " : "FAIL ") + name + (error === "" ? "" : ": " + error))
    }

    function finish() {
        if (shell.done)
            return
        shell.done = true
        shell.check(shell.drops > 0 ? "" : "no table stopped overflowing when its pane widened", "a widened pane drops a table's scroll")
        shell.log(shell.checks + " checks, " + shell.failures + " failed")
        shell.quit()
    }

    FloatingWindow {
        implicitWidth: shell.cardWidth + shell.columnWidth + 60
        implicitHeight: shell.paneHeight + 20
        color: "#101315"

        // Real wheel events are sent through the window's own event path, to the item and point asked.
        Item {
            anchors.fill: parent
            TestEvent { id: driver }
        }

        Rectangle {
            id: cardFrame
            x: 10
            y: 10
            width: shell.cardWidth
            height: shell.cardShot
            clip: true
            color: Flea.Theme.color.background

            Flea.MarkdownPane {
                id: card
                width: parent.width
                height: shell.paneHeight
                active: true
                size: 1
                view: "rendered"
            }
        }

        Rectangle {
            id: columnFrame
            x: shell.cardWidth + 30
            y: 10
            width: shell.columnWidth
            height: shell.columnShot
            clip: true
            color: Flea.Theme.color.background

            Flea.PreviewMarkdown {
                id: column
                width: parent.width
                height: shell.paneHeight
                active: true
                compact: true
                size: 1
                view: "rendered"
            }
        }
    }

    // One word's laid-out width in a cell's own font, so a cell narrower than a word of it is a word Qt had to break.
    TextMetrics {
        id: wordProbe
    }

    function wordPx(cell, word) {
        wordProbe.font = cell.font
        wordProbe.text = word
        return wordProbe.advanceWidth
    }

    function ready(pane) { return pane.contentReady && pane.blockList.length > 0 }

    // The drop never falls through to load: past the frame limit the run fails naming the case it never left.
    function dropTimeout() {
        shell.log("FAIL the drop never left " + shell.cases[shell.at] + " after " + shell.dropFrames + " frames")
        shell.failures++
        shell.finish()
    }

    // The tables a pane built, in tree order, measured against the pane's block column at their body offset.
    function measure(pane) {
        var body = pane.bodyItem
        return Tables.all(body.contentItem, "tableGrid").map(function (table) { return Tables.geometry(table, body.width, Math.round(table.mapToItem(body.contentItem, 0, 0).x), shell.wordPx) })
    }

    // Where every text and rule of a case's pane sits in its grabbed frame, for the picture-line judge that reads the pixels.
    function logInk(name, label, pane, frame) {
        var ink = Tables.inkRects(pane.bodyItem.contentItem, frame)
        ink.bg = String(Flea.Theme.color.background)
        ink.lists = Markers.listInk(pane.bodyItem.contentItem, frame, name)
        shell.log("INK " + name + " " + label + " " + JSON.stringify(ink))
    }

    function judge(name, pane, label, frame) {
        shell.logInk(name, label, pane, frame)
        var geos = shell.measure(pane)
        shell.geos[name + "-" + label] = geos
        shell.log("GEO " + name + " " + label + " " + JSON.stringify(geos))
        for (var i = 0; i < geos.length; i++) {
            shell.check(Tables.fitError(geos[i]), name + " " + label + " table " + i + " fits its column")
            shell.check(Tables.gapError(geos[i]), name + " " + label + " table " + i + " keeps its column gap")
            shell.check(Tables.wordError(geos[i]), name + " " + label + " table " + i + " keeps every word whole")
        }
        if (name === "picturewide" && geos.length > 0) {
            var ref = shell.geos["mid-" + label]
            var refGlyph = ref !== undefined && ref.length > 0 ? ref[0].glyph : -1
            var over = refGlyph < 0 ? "no mid table weighs picturewide against" : geos[0].glyph <= shell.pictureRatio * refGlyph ? "" : "picturewide glyph " + geos[0].glyph + " is past " + shell.pictureRatio + "x the text-only " + refGlyph
            shell.check(over, name + " " + label + " prices glyphs by text, not by picture")
        }
        if (!Tables.tableless(name))
            shell.check(Tables.lineError(name, label, geos), name + " " + label + " draws its lines")
        var body = pane.bodyItem
        var tables = Tables.all(body.contentItem, "tableGrid")
        shell.check(Sideways.scrollError(tables, Tables.all(body.contentItem, "tableScroll"), Sideways.barsIn(body.contentItem)), name + " " + label + " builds a sideways scroll only for a table that overflows")
        shell.check(Markers.markerBaselineError(pane.bodyItem.contentItem, frame, name), name + " " + label + " marker is placed on its item text's drawnBaseline")
    }

    // A column at an offset holding a spacer and a wide table: the positioner a table's scroll must not be stacked by.
    property Item hosted: null
    Component {
        id: hostComponent
        Item {
            property alias stack: hostColumn
            Column {
                id: hostColumn
                x: shell.hostX
                y: shell.hostY
                Item { width: 1; height: shell.hostSpacer }
                Flea.MarkdownTable {
                    block: column.blockList.filter(function (b) { return b.type === "table" })[0]
                    preview: column
                    availableWidth: shell.columnWidth
                }
            }
        }
    }

    function sendWheel(item, x, y, angleX, angleY, modifiers) {
        driver.mouseWheel(item, x, y, Qt.NoButton, modifiers, angleX, angleY, 1)
    }

    // The height a pane shrinks to for the wheel checks: past its first overflowing table's wheel point by the margin, 0 when it has none.
    function wheelHeight(pane) {
        var scrollers = Tables.all(pane.bodyItem.contentItem, "tableScroll")
        if (scrollers.length === 0)
            return 0
        var body = pane.bodyItem
        var at = scrollers[0].mapToItem(body, scrollers[0].width / 2, Sideways.WHEEL_ROW_PX)
        return Math.ceil(pane.height - body.height + at.y) + shell.wheelPaneMargin
    }

    // The chunks of one table, at full height, share one position whichever is wheeled.
    function judgeChunks(name, pane, label) {
        var body = pane.bodyItem
        // The chunked wide case must build its chunks, so it never skips; any other case checks only when it chunked an overflowing table.
        if (name !== "chunkwide" && Tables.all(body.contentItem, "tableGrid").filter(function (t) { return t.overflows && t.block.tableKey !== undefined }).length === 0)
            return
        shell.check(Sideways.chunkError(Tables.all(body.contentItem, "tableGrid"), pane.tableWheel, shell.sendWheel), name + " " + label + " chunks of one table scroll sideways as one")
    }

    // The wheel checks of a pane's first overflowing table; the pane is short, so the document has room to move under a vertical wheel.
    function judgeWheel(name, pane, label) {
        var body = pane.bodyItem
        var scrollers = Tables.all(body.contentItem, "tableScroll")
        if (scrollers.length === 0)
            return
        var tops = body.contentY
        shell.check(Sideways.wheelError(pane.tableWheel, scrollers[0], body, shell.sendWheel), name + " " + label + " scrolls sideways under a real wheel and leaves a vertical one to the document")
        if (name === "extreme" && label === "column") {
            var errors = Sideways.touchErrors(pane.tableWheel, scrollers[0])
            var names = ["Begin reaches the table and the document", "the first update locks the stroke to the table", "a vertical stroke stays with the document", "End releases the stroke"]
            for (var n = 0; n < names.length; n++)
                shell.check(errors[n], name + " " + label + " touchpad: " + names[n])
        }
        for (var i = 0; i < scrollers.length; i++)
            scrollers[i].contentX = 0
        body.contentY = tops
    }

    // After the panes widen, a table that now fits has dropped its flickable, bar and router entry, and one that still overflows keeps one of each.
    function judgeWiden(name, pane, label, before) {
        var body = pane.bodyItem
        var tables = Tables.all(body.contentItem, "tableGrid")
        var scrollers = Tables.all(body.contentItem, "tableScroll")
        var error = Sideways.scrollError(tables, scrollers, Sideways.barsIn(body.contentItem))
        if (error === "" && pane.tableWheel.scrollers.filter(function (s) { return s }).length !== scrollers.length)
            error = "the router holds " + pane.tableWheel.scrollers.filter(function (s) { return s }).length + " scrollers for " + scrollers.length + " flickables"
        shell.check(error, name + " " + label + " drops its scroll when it stops overflowing")
        // The IPC's table is the first live one, whichever tables dropped theirs.
        var first = pane.tableScroller()
        var live = pane.tableWheel.scrollers.filter(function (s) { return s })
        var ipc = scrollers.length > 0 && (first === null || first.table.firstRow() === null) ? "tableScroller answers " + first + " while " + scrollers.length + " tables still scroll"
            : scrollers.length === 0 && first !== null ? "tableScroller answers a scroller while no table scrolls"
            : first !== null && (first !== live[0] || scrollers.indexOf(first) < 0) ? "tableScroller answers a scroller that is not the router's first live one in the document" : ""
        shell.check(ipc, name + " " + label + " tableScroller answers the first live scroll")
        if (before > scrollers.length)
            shell.drops++
        return scrollers.length
    }

    function shotHeight(pane, bar) {
        var body = pane.bodyItem
        return Math.min(shell.paneHeight, bar + Math.ceil(body.contentHeight + body.topMargin + body.bottomMargin))
    }

    function save(item, file) {
        shell.pending.push(file)
        item.grabToImage(function (result) {
            shell.log(result.saveToFile(file) ? "grab " + file : "FAIL the grab could not be saved " + file)
            shell.pending.splice(shell.pending.indexOf(file), 1)
        })
    }

    FrameAnimation {
        running: !shell.done
        onTriggered: {
            if (shell.stage === "next") {
                shell.at++
                if (shell.at >= shell.cases.length) {
                    shell.stage = "end"
                    return
                }
                shell.prevText = card.rawText
                shell.prevCardBlocks = card.blockList
                shell.prevColumnBlocks = column.blockList
                card.path = shell.dir + "/" + shell.cases[shell.at] + ".md"
                column.path = card.path
                shell.waited = 0
                shell.quiet = 0
                shell.lastHeights = -1
                shell.stage = "drop"
            } else if (shell.stage === "drop") {
                shell.waited++
                // The old text survives until the new load lands and a reload may pass through empty text, so only new text ends the drop.
                if (card.rawText.length > 0 && card.rawText !== shell.prevText && column.rawText.length > 0 && column.rawText !== shell.prevText)
                    shell.stage = "load"
                else if (shell.waited > shell.dropFrames)
                    shell.dropTimeout()
            } else if (shell.stage === "load") {
                // A pane that still holds the previous case's block list has not parsed the new text yet, whatever ready() reads.
                if (shell.ready(card) && shell.ready(column) && card.blockList !== shell.prevCardBlocks && column.blockList !== shell.prevColumnBlocks)
                    shell.stage = "settle"
            } else if (shell.stage === "settle") {
                var heights = card.bodyItem.contentHeight + column.bodyItem.contentHeight
                shell.quiet = heights === shell.lastHeights ? shell.quiet + 1 : 0
                shell.lastHeights = heights
                if (shell.quiet >= shell.quietFrames) {
                    var name = shell.cases[shell.at]
                    shell.judge(name, card, "card", cardFrame)
                    shell.judge(name, column, "column", columnFrame)
                    shell.cardShot = shell.shotHeight(card, Flea.Theme.chromeHeight)
                    shell.columnShot = shell.shotHeight(column, 0)
                    shell.save(cardFrame, shell.outDir + "/tables-" + name + "-card.png")
                    shell.save(columnFrame, shell.outDir + "/tables-" + name + "-column.png")
                    shell.stage = "grab"
                }
            } else if (shell.stage === "grab") {
                if (shell.pending.length === 0) {
                    shell.cardShot = shell.paneHeight
                    shell.columnShot = shell.paneHeight
                    // A case with a table that scrolls is checked only after its rest shots are saved, so the wheel never shows in a grab.
                    var gName = shell.cases[shell.at]
                    shell.judgeChunks(gName, card, "card")
                    shell.judgeChunks(gName, column, "column")
                    var cardShort = shell.wheelHeight(card)
                    var columnShort = shell.wheelHeight(column)
                    shell.scrollsBefore = [Tables.all(card.bodyItem.contentItem, "tableScroll").length, Tables.all(column.bodyItem.contentItem, "tableScroll").length]
                    if (cardShort > 0 || columnShort > 0) {
                        card.height = cardShort > 0 ? cardShort : shell.paneHeight
                        column.height = columnShort > 0 ? columnShort : shell.paneHeight
                        shell.stage = "wheel"
                    } else {
                        shell.stage = "next"
                    }
                }
            } else if (shell.stage === "wheel") {
                // A frame after the shrink, so the lists have laid out their short views.
                var wName = shell.cases[shell.at]
                shell.judgeWheel(wName, card, "card")
                shell.judgeWheel(wName, column, "column")
                card.height = shell.paneHeight
                column.height = shell.paneHeight
                cardFrame.width = shell.wideFrame
                columnFrame.width = shell.wideFrame
                shell.stage = "widening"
            } else if (shell.stage === "widening") {
                // A destroy lands on the event loop after the frame that asked for it, so the judge waits one more.
                shell.stage = "widen"
            } else if (shell.stage === "widen") {
                var dName = shell.cases[shell.at]
                shell.judgeWiden(dName, card, "card", shell.scrollsBefore[0])
                shell.judgeWiden(dName, column, "column", shell.scrollsBefore[1])
                cardFrame.width = Qt.binding(function () { return shell.cardWidth })
                columnFrame.width = Qt.binding(function () { return shell.columnWidth })
                // The extreme table, rebuilt in a positioner, gets two frames to measure and lay out.
                if (dName === "extreme") {
                    shell.hosted = hostComponent.createObject(columnFrame)
                    shell.waited = 0
                    shell.stage = "hosting"
                } else {
                    shell.stage = "next"
                }
            } else if (shell.stage === "hosting") {
                shell.waited++
                if (shell.hosted === null) {
                    shell.check("the positioner host was not created", "extreme table in a positioner keeps its scroll over it and its bar at its foot")
                    shell.stage = "next"
                } else if (shell.waited > 2) {
                    shell.check(Sideways.hostError(shell.hosted, shell.hosted.stack), "extreme table in a positioner keeps its scroll over it and its bar at its foot")
                    shell.hosted.destroy()
                    shell.hosted = null
                    shell.stage = "next"
                }
            } else if (shell.stage === "end") {
                shell.finish()
            }
        }
    }

    Timer {
        interval: shell.watchdogMs
        running: !shell.done
        onTriggered: {
            shell.log("FAIL the watchdog outlived the verdict at case " + shell.cases[shell.at] + " stage " + shell.stage)
            shell.failures++
            shell.finish()
        }
    }
}
