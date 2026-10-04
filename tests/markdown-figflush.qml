//@ pragma ShellId flea-markdown-figflush-test

import QtQuick
import Quickshell
import "flea" as Flea
import "markdown-figures-render.js" as Checks

// Every Mermaid figure starts flush on the content column, the way an image does: the first painted pixel of its block is the text's left edge.
ShellRoot {
    id: shell
    property bool done: false
    property int checks: 0
    property int failures: 0
    property bool grabbed: false
    property var captured: []
    property string shotPath: Quickshell.env("XDG_RUNTIME_DIR") + "/markdown-figflush.png"
    // The figure's first painted column may sit this far in from the content edge: one pixel, the drawing's own stroke.
    readonly property int flushSlackPx: 1
    readonly property int windowWidth: 560
    readonly property int windowHeight: 600
    Component.onCompleted: Flea.ViewState.setTextSize({ mode: 14 })

    function log(line) { console.log("MARKDOWN_FIGFLUSH " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(error, name) {
        shell.checks++
        if (error !== "") shell.failures++
        shell.log((error === "" ? "CHECK " : "FAIL ") + name + (error === "" ? "" : ": " + error))
    }

    FloatingWindow {
        implicitWidth: shell.windowWidth
        implicitHeight: shell.windowHeight
        color: "#101315"
        Item {
            id: grabRoot
            anchors.fill: parent
            Flea.PreviewMarkdown {
                id: md
                anchors.fill: parent
                active: true
                path: Quickshell.env("FLEA_MARKDOWN_FIGURE_FIXTURE")
                size: 1
                view: "rendered"
            }
        }
        Image {
            id: shot
            width: 1
            height: 1
            opacity: 0
            onStatusChanged: if (status === Image.Ready) probe.requestPaint()
        }
        Canvas {
            id: probe
            width: shell.windowWidth
            height: shell.windowHeight
            opacity: 0
            onPaint: if (shot.status === Image.Ready && !shell.done) shell.pixels(getContext("2d"))
        }
    }

    function ready() {
        if (!md.contentReady || md.blockList.length !== 3) return false
        for (var i = 1; i <= 2; i++) {
            var fig = Checks.figure(md, i)
            var image = Checks.imageOf(fig)
            if (!fig || !fig.ready || fig.working || !image || image.status !== Image.Ready || image.height <= 0)
                return false
        }
        return true
    }

    // The leftmost column in a block's rect holding anything but the window ground, in window pixels.
    function pixels(ctx) {
        ctx.drawImage(shot, 0, 0)
        var data = ctx.getImageData(0, 0, shell.windowWidth, shell.windowHeight).data
        var edge = md.insetX
        for (var i = 0; i < shell.captured.length; i++) {
            var rect = shell.captured[i]
            var first = -1
            // A rect past the grab would read beyond the buffer, and an undefined byte is not bare, so it fails here instead of counting as painted.
            if (rect.x < 0 || rect.y < 0 || rect.x + rect.w > shell.windowWidth || rect.y + rect.h > shell.windowHeight) {
                shell.check("block " + rect.name + " spans " + rect.x + "," + rect.y + " " + rect.w + "x" + rect.h + ", outside the "
                    + shell.windowWidth + "x" + shell.windowHeight + " grab", rect.name + " starts flush on the content edge")
                continue
            }
            for (var x = rect.x; x < rect.x + rect.w && first < 0; x++)
                for (var y = rect.y; y < rect.y + rect.h; y++) {
                    var o = (y * shell.windowWidth + x) * 4
                    // The grab holds the figures alone, so an unpainted pixel is transparent and a node's own fill is the window ground.
                    var bare = data[o + 3] === 0 || (data[o] === 16 && data[o + 1] === 19 && data[o + 2] === 21)
                    if (!bare) { first = x; break }
                }
            shell.check(first >= 0 && first - edge >= 0 && first - edge <= shell.flushSlackPx ? ""
                : "figure " + rect.name + " first paints at x " + first + ", the content edge is " + edge,
                rect.name + " starts flush on the content edge")
        }
        shell.done = true
        shell.log(shell.checks + " checks, " + shell.failures + " failed")
        shell.quit()
    }

    Timer {
        interval: 100
        repeat: true
        running: !shell.done
        onTriggered: {
            if (shell.grabbed || !shell.ready()) return
            shell.grabbed = true
            var names = ["", "flowchart", "sequence diagram"]
            var rects = []
            for (var i = 1; i <= 2; i++) {
                var block = md.blockItem(i)
                var at = block.mapToItem(grabRoot, 0, 0)
                rects.push({ name: names[i], x: Math.round(at.x), y: Math.round(at.y), w: Math.round(block.width), h: Math.round(block.height) })
            }
            shell.captured = rects
            grabRoot.grabToImage(function (result) {
                shell.check(result.saveToFile(shell.shotPath) ? "" : "grab could not be saved", "figure grab")
                shot.source = "file://" + shell.shotPath
            })
        }
    }
    Timer {
        interval: 20000
        running: !shell.done
        onTriggered: {
            shell.done = true
            shell.log("FAIL the figures never settled")
            shell.quit()
        }
    }
}
