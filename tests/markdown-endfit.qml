//@ pragma ShellId flea-markdown-endfit-test

import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "markdown-render.js" as Checks
import "markdown-board.js" as Board

// The real ui/PreviewMarkdown.qml over a document whose last block is a local picture that decodes late: a reader who reached the
// end before it grew must still see the last block's bottom and the bottom inset. The picture is a named pipe the loader blocks on
// until this test feeds it, so the late decode is held open by the test rather than by a clock. The same document, at the board's
// text size 14, holds the board's own pixels: block gaps, fence padding, headings, the table header ink and the column's sizes.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_ENDFIT " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    readonly property string fixture: Quickshell.env("FLEA_ENDFIT_DOC")
    readonly property string pictureBytes: Quickshell.env("FLEA_ENDFIT_BYTES")
    readonly property string pictureFifo: Quickshell.env("FLEA_ENDFIT_FIFO")
    // The board is resolved at body 14, the text size this suite pins.
    readonly property int boardText: 14
    // The picture the fixture feeds is 160 by 80, so its block grows by 80 once decoded.
    readonly property int pictureHeightPx: 80
    // The view is quiet once its content height held still for this many frames after the picture arrived.
    readonly property int quietFrames: 6
    // The last block's bottom plus the bottom inset may sit this far past the viewport, the rounding of a fractional height.
    readonly property real endSlackPx: 1
    property int checks: 0
    property int failures: 0
    property bool done: false
    // "load", "reach", "wait", "settle" and "verify", in order.
    property string stage: "load"
    property real lastContentHeight: -1
    property int quietCount: 0

    // The board's own palette, whose heading ink differs from its foreground, so a header cell inking either is told apart.
    readonly property string palette: 'background = "#1a1b26"\nforeground = "#a9b1d6"\nbright_foreground = "#c0caf5"\n'

    Component.onCompleted: {
        Flea.ViewState.state = { display: { textSize: { mode: shell.boardText } } }
        Flea.Theme.applyColors(shell.palette)
    }

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
        implicitWidth: 560
        implicitHeight: 400
        color: "#101315"

        Flea.PreviewMarkdown {
            id: md
            anchors.fill: parent
            active: true
            path: shell.fixture
            size: 1
            view: "rendered"
        }

        // Built beside the window and not under it, since a hidden tree draws no text for the probe to read.
        Flea.PreviewMarkdown {
            id: column
            x: parent.width
            width: 560
            height: 400
            active: true
            compact: true
            path: shell.fixture
            size: 1
            view: "rendered"
        }
    }

    Process {
        id: feeder
        command: ["/bin/sh", "-c", "cat \"$1\" > \"$2\"", "sh", shell.pictureBytes, shell.pictureFifo]
    }

    function blockOf(type, level) {
        for (var i = 0; i < md.blockList.length; i++)
            if (md.blockList[i].type === type && (level === undefined || md.blockList[i].level === level))
                return i
        return -1
    }

    function textIn(pane, i) {
        var item = i < 0 ? null : pane.blockItem(i)
        return item ? Checks.textOf(item) : null
    }

    // Window coordinates of every block that exists, in block order, for the rhythm of the whole document.
    function rects() {
        var out = []
        for (var i = 0; i < md.blockList.length; i++) {
            var item = md.blockItem(i)
            if (item === null)
                break
            var at = item.mapToItem(md.bodyItem, 0, 0)
            out.push({ x: Math.round(at.x), y: Math.round(at.y), w: Math.round(item.width), h: Math.round(item.height) })
        }
        return out
    }

    // The board at body 14, in its own pixels and not the renderer's tokens.
    function board() {
        shell.check(Flea.Theme.font.body === shell.boardText ? "" : "body " + Flea.Theme.font.body, "the suite runs at the board's text size")
        var blocks = shell.rects()
        var gapError = ""
        for (var i = 1; i < blocks.length && gapError === ""; i++) {
            var gap = blocks[i].y - blocks[i - 1].y - blocks[i - 1].h
            if (gap !== Board.BOARD_BLOCK_GAP)
                gapError = "block " + i + " sits " + gap + " px below block " + (i - 1) + ", the board draws " + Board.BOARD_BLOCK_GAP
        }
        shell.check(blocks.length < 6 ? "only " + blocks.length + " blocks were built" : gapError, "every block sits the board's 6 px below the last")
        var fence = Checks.fenceOf(md.blockItem(shell.blockOf("fence")))
        shell.check(Checks.fencePadError(fence, Board.BOARD_FENCE_PAD_X, Board.BOARD_FENCE_PAD_Y), "the fence pads the board's 8 12")
        var h1 = shell.textIn(md, shell.blockOf("heading", 1))
        var h2 = shell.textIn(md, shell.blockOf("heading", 2))
        var para = shell.textIn(md, shell.blockOf("run"))
        shell.check(h1 && h2 && h1.font.pixelSize === Checks.BOARD_H1 && h2.font.pixelSize === Checks.BOARD_H2 ? ""
            : "Quick Look h1 " + (h1 && h1.font.pixelSize) + " h2 " + (h2 && h2.font.pixelSize), "Quick Look headings are the board's 20 and 15")
        shell.check(String(Flea.Theme.color.foregroundBright) !== String(Flea.Theme.color.foreground) ? "" : "the palette gave no heading ink of its own",
            "the heading ink differs from the foreground")
        shell.check(Board.headerInkError(md.blockItem(shell.blockOf("table")), String(Flea.Theme.color.foregroundBright),
            String(Flea.Theme.color.foreground)), "table header cells are bold in the heading ink")
        var c1 = shell.textIn(column, shell.blockOf("heading", 1))
        var c2 = shell.textIn(column, shell.blockOf("heading", 2))
        var cp = shell.textIn(column, shell.blockOf("run"))
        shell.check(Board.compactHeadingError(c1, c2, cp, Flea.Theme.font.body, Flea.Theme.font.bodySmall), "the column keeps the board's 20 and 15 over its 13")
    }

    // The last block's picture, found by what it is rather than where it sits in the delegate.
    function pictureOf(item) {
        for (var i = 0; i < item.children.length; i++)
            if (item.children[i].status !== undefined && item.children[i].fillMode !== undefined)
                return item.children[i]
        return null
    }

    function endOffset() {
        var body = md.bodyItem
        return body.originY + body.contentHeight - body.height + body.bottomMargin
    }

    // How far the last block's bottom and the inset below it lie past the viewport's bottom edge.
    function pastViewport() {
        var last = md.blockItem(md.blockList.length - 1)
        return last.mapToItem(md.bodyItem, 0, last.height).y + md.bodyItem.bottomMargin - md.bodyItem.height
    }

    function verify() {
        var last = md.blockItem(md.blockList.length - 1)
        var picture = last ? shell.pictureOf(last) : null
        shell.check(picture && picture.status === Image.Ready && Math.round(last.height) === shell.pictureHeightPx ? ""
            : "the picture did not land whole", "the late picture decoded to its 80 px")
        var past = last ? shell.pastViewport() : NaN
        shell.check(past <= shell.endSlackPx ? "" : "the last block and its inset end " + past + " px past the viewport",
            "a reader at the end sees the last block's bottom and the bottom inset")
        shell.check(md.bodyItem.atYEnd ? "" : "the view rests at contentY " + md.bodyItem.contentY + " short of the end", "the view stayed at its end")
        shell.check(typeof md.endGap === "function" && md.endGap() <= shell.endSlackPx ? "" : "endGap reads " + (typeof md.endGap === "function" ? md.endGap() : "nothing"),
            "the IPC reader of the end agrees")
        shell.finish()
    }

    // One step per frame, so each stage waits on the scene graph rather than on a clock.
    FrameAnimation {
        running: !shell.done
        onTriggered: {
            if (shell.stage === "load") {
                if (md.contentReady && column.contentReady) {
                    shell.board()
                    shell.stage = "reach"
                }
            } else if (shell.stage === "reach") {
                md.bodyItem.contentY = shell.endOffset()
                var last = md.blockItem(md.blockList.length - 1)
                var picture = last ? shell.pictureOf(last) : null
                if (picture && md.bodyItem.atYEnd) {
                    shell.check(picture.status === Image.Loading && last.height === 0 ? "" : "status " + picture.status + " height " + last.height,
                        "the reader reached the end while the picture was still undecoded")
                    feeder.running = true
                    shell.stage = "wait"
                }
            } else if (shell.stage === "wait") {
                var held = md.blockItem(md.blockList.length - 1)
                var late = held ? shell.pictureOf(held) : null
                if (late && late.status === Image.Ready)
                    shell.stage = "settle"
            } else if (shell.stage === "settle") {
                shell.quietCount = md.bodyItem.contentHeight === shell.lastContentHeight ? shell.quietCount + 1 : 0
                shell.lastContentHeight = md.bodyItem.contentHeight
                if (shell.quietCount >= shell.quietFrames) {
                    shell.stage = "verify"
                    shell.verify()
                }
            }
        }
    }

    Timer {
        interval: 30000
        running: !shell.done
        onTriggered: {
            shell.log("FAIL the watchdog outlived the verdict at stage " + shell.stage)
            shell.failures++
            shell.finish()
        }
    }
}
