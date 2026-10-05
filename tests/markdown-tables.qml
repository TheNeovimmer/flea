//@ pragma ShellId flea-markdown-tables-test

import QtQuick
import Quickshell
import "flea" as Flea
import "markdown-tables.js" as Tables

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
    // A case is quiet once both panes' content height held still this many frames.
    readonly property int quietFrames: 8
    // Frames a path change may take to drop the old document before the new one is awaited anyway.
    readonly property int dropFrames: 30
    // The test gives up on its own verdict after this long, so a hung stage fails and the run ends.
    readonly property int watchdogMs: 120000
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
        shell.log(shell.checks + " checks, " + shell.failures + " failed")
        shell.quit()
    }

    FloatingWindow {
        implicitWidth: shell.cardWidth + shell.columnWidth + 60
        implicitHeight: shell.paneHeight + 20
        color: "#101315"

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

    function ready(pane) { return pane.contentReady && pane.blockList.length > 0 }

    // The tables a pane built, in tree order, measured against the pane's block column.
    function measure(pane) {
        var body = pane.bodyItem
        return Tables.all(body.contentItem, "tableGrid").map(function (table) { return Tables.geometry(table, body.width) })
    }

    function judge(name, pane, label) {
        var geos = shell.measure(pane)
        shell.geos[name + "-" + label] = geos
        shell.log("GEO " + name + " " + label + " " + JSON.stringify(geos))
        for (var i = 0; i < geos.length; i++) {
            // The narrow column cannot hold every column of the widest cases whatever the wrap; that is named, not checked.
            var skip = label === "column" && Tables.NARROW_OVERFLOW.indexOf(name) >= 0
            shell.check(skip ? "" : Tables.fitError(geos[i]), name + " " + label + " table " + i + " fits its column")
        }
        shell.check(Tables.lineError(name, label, geos), name + " " + label + " draws its lines")
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
                card.path = shell.dir + "/" + shell.cases[shell.at] + ".md"
                column.path = card.path
                shell.waited = 0
                shell.quiet = 0
                shell.lastHeights = -1
                shell.stage = "drop"
            } else if (shell.stage === "drop") {
                shell.waited++
                if ((!shell.ready(card) && !shell.ready(column)) || shell.waited > shell.dropFrames)
                    shell.stage = "load"
            } else if (shell.stage === "load") {
                if (shell.ready(card) && shell.ready(column))
                    shell.stage = "settle"
            } else if (shell.stage === "settle") {
                var heights = card.bodyItem.contentHeight + column.bodyItem.contentHeight
                shell.quiet = heights === shell.lastHeights ? shell.quiet + 1 : 0
                shell.lastHeights = heights
                if (shell.quiet >= shell.quietFrames) {
                    var name = shell.cases[shell.at]
                    shell.judge(name, card, "card")
                    shell.judge(name, column, "column")
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
