//@ pragma ShellId flea-markdown-arrows-test
import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

ShellRoot {
    id: shell
    property bool done: false
    property bool armed: false
    property bool syntheticArmed: false
    property int checks: 0
    property int failures: 0
    property string output: Quickshell.env("XDG_RUNTIME_DIR") + "/markdown-arrows.png"
    property var arrowCases: JSON.parse(casesFile.text() || "[]")
    FileView {
        id: casesFile
        path: Quickshell.env("FLEA_ARROW_FIXTURE")
        blockLoading: true
    }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(ok, label) {
        checks++
        if (!ok) failures++
        console.log("MARKDOWN_ARROWS " + (ok ? "CHECK " : "FAIL ") + label)
    }
    FloatingWindow {
        implicitWidth: 1200
        implicitHeight: 640
        color: "#101315"
        Item {
            id: grab
            anchors.fill: parent
            Repeater {
                id: figures
                model: ["TD", "BT", "LR", "RL"]
                Flea.MarkdownFigure {
                    required property string modelData
                    required property int index
                    x: (index % 2) * 240
                    y: Math.floor(index / 2) * 160
                    width: 220
                    source: "flowchart " + modelData + "\n    A --> B"
                    kind: "mermaid"
                    fontFamily: "monospace"
                    bodyPx: 14
                }
            }
            Repeater {
                id: synthetic
                model: shell.arrowCases
                Flea.MarkdownFigure {
                    required property var modelData
                    required property int index
                    x: 480 + (index % 4) * 160
                    y: Math.floor(index / 4) * 160
                    width: 140
                    askArmed: false
                    kind: "mermaid"
                }
            }
        }
        Image { id: shot; width: 1; height: 1; opacity: 0 }
        Canvas {
            id: probe
            width: 1200
            height: 640
            opacity: 0
            onPaint: if (shell.armed) shell.analyze(getContext("2d"))
        }
    }
    function edge(svg) {
        var found = svg.match(/<(?:polyline|path)\b[^>]*class="edge"[^>]*\s(?:points|d)="([^"]+)"/)
        var points = found ? found[1].replace(/[ML]/g, " ").trim().split(/[\s,]+/).map(Number) : []
        if (points.length < 4)
            return null
        return { start: { x: points[0], y: points[1] }, end: { x: points[points.length - 2], y: points[points.length - 1] } }
    }
    function head(pixels, fig, line) {
        var at = fig.mapToItem(grab, 0, 0)
        var box = fig.svg.match(/viewBox="([^"]*)"/)[1].split(/\s+/).map(Number)
        var sx = fig.fitWidth / box[2], sy = fig.fitHeight / box[3]
        var x = at.x + (line.end.x - box[0]) * sx
        var y = at.y + (line.end.y - box[1]) * sy
        var dx = line.end.x - line.start.x, dy = line.end.y - line.start.y
        var length = Math.sqrt(dx * dx + dy * dy)
        dx /= length; dy /= length
        var count = 0, along = 0, cross = 0, tip = -Infinity, tipCross = 0
        var wide = 0, narrow = 0
        for (var py = Math.floor(y - 12); py <= Math.ceil(y + 12); py++)
            for (var px = Math.floor(x - 12); px <= Math.ceil(x + 12); px++) {
                var offset = (py * 1200 + px) * 4
                var r = pixels[offset], g = pixels[offset + 1], b = pixels[offset + 2]
                if (!(b > r + 70 && b > g + 60))
                    continue
                var a = (px + 0.5 - x) * dx + (py + 0.5 - y) * dy
                var c = (px + 0.5 - x) * -dy + (py + 0.5 - y) * dx
                count++; along += a; cross += c
                if (a > tip) { tip = a; tipCross = c }
                if (a >= -7 && a < -4) wide++
                if (a >= -2 && a <= 0) narrow++
            }
        return { count: count, along: along / count, cross: cross / count, tip: tip,
            tipCross: tipCross, wide: wide, narrow: narrow }
    }
    function analyze(ctx) {
        ctx.drawImage(shot, 0, 0)
        var pixels = ctx.getImageData(0, 0, 1200, 640).data
        for (var i = 0; i < 4 + synthetic.count; i++) {
            var fig = i < 4 ? figures.itemAt(i) : synthetic.itemAt(i - 4)
            var label = i < 4 ? fig.modelData : fig.modelData.name
            var line = edge(fig.svg)
            check(line !== null, label + " has an edge")
            if (!line) continue
            if (i >= 4 && fig.modelData.atStart) {
                var first = line.start
                line.start = line.end
                line.end = first
            }
            var h = head(pixels, fig, line)
            console.log("MARKDOWN_ARROWS PIXELS " + label + " " + JSON.stringify(h))
            check(h.count >= 10 && Math.abs(h.cross) <= 1 && h.along < -2,
                label + " head centered behind edge end")
            check(h.tip >= -2 && h.tip <= 2 && Math.abs(h.tipCross) <= 1.5,
                label + " tip touches edge end")
            check(h.wide > h.narrow && h.narrow > 0, label + " head tapers along edge direction")
        }
        shell.done = true
        console.log("MARKDOWN_ARROWS " + checks + " checks, " + failures + " failed")
        shell.quit()
    }
    Timer {
        id: settle
        interval: 700
        repeat: true
        running: !shell.done
        onTriggered: {
            for (var i = 0; i < 4; i++) {
                var fig = figures.itemAt(i)
                if (fig.failed) {
                    console.log("MARKDOWN_ARROWS FAIL helper " + fig.error)
                    shell.quit()
                    return
                }
                if (!fig.ready || fig.fitWidth <= 0 || fig.fitHeight <= 0)
                    return
            }
            if (synthetic.count !== 16)
                return
            // An unarmed startup ask clears SVG, so inject fixtures after that timer has finished.
            if (!shell.syntheticArmed) {
                for (var a = 0; a < synthetic.count; a++)
                    synthetic.itemAt(a).svg = synthetic.itemAt(a).modelData.svg
                shell.syntheticArmed = true
                return
            }
            for (var s = 0; s < synthetic.count; s++)
                if (synthetic.itemAt(s).fitWidth <= 0 || synthetic.itemAt(s).fitHeight <= 0)
                    return
            settle.stop()
            grab.grabToImage(function(result) {
                if (!result.saveToFile(shell.output)) {
                    console.log("MARKDOWN_ARROWS FAIL capture")
                    shell.quit()
                }
                shot.source = "file://" + shell.output
            })
        }
    }
    Connections {
        target: shot
        function onStatusChanged() {
            if (shot.status === Image.Ready) {
                shell.armed = true
                probe.requestPaint()
            }
        }
    }
    Timer {
        interval: 15000
        running: !shell.done
        onTriggered: {
            console.log("MARKDOWN_ARROWS FAIL watchdog cases=" + shell.arrowCases.length + " delegates=" + synthetic.count)
            shell.quit()
        }
    }
}
