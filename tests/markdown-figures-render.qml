//@ pragma ShellId flea-markdown-figures-render-test

import QtQuick
import Quickshell
import "flea" as Flea
import "markdown-figures-render.js" as Checks

// tests/markdown-figures-render.sh's harness: the real ui/PreviewMarkdown.qml
// over a fixture holding a flowchart, a math fence, a $$ display block, a
// malformed diagram, an inline-$ paragraph and a far figure past filler. In
// stub mode a stub `flea` answers a canned 800x400 SVG; in real mode the real
// helper answers through the real FigureService, and each good figure's rect
// must hold ink that is not the chrome surface. Quits itself, pass or fail.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_FIGRENDER " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property string fixture: Quickshell.env("FLEA_MARKDOWN_FIGURE_FIXTURE")
    property string shotPath: Quickshell.env("XDG_RUNTIME_DIR") + "/markdown-figrender-" + Quickshell.processId + ".png"
    property bool done: false
    property bool armed: false
    property int step: 0
    property double t0: 0
    property int farIndex: -1
    property int inlineIndex: -1
    property int sendsMark: 0
    property int failures: 0
    property int padding: 0
    property real paragraphHeight: 0
    Component.onCompleted: Flea.ViewState.setTextSize({ mode: 14 })
    // Real when FLEA_FIG_MODE=real, else the canned stub: the geometry bound
    // below is the only thing that differs, since a real formula is 15 px wide.
    property string figMode: Quickshell.env("FLEA_FIG_MODE") === "real" ? "real" : "stub"

    FloatingWindow {
        id: window
        implicitWidth: 560
        implicitHeight: 1120
        color: "#101315"

        Item {
            id: grabRoot
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1080

            Flea.PreviewMarkdown {
                id: md
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1060
                active: true
                path: shell.fixture
                size: 1
                view: "source"
            }
        }

        // The seam's own component: Quick Look wraps the document in MarkdownPane, so the suite reads through it too.
        Flea.MarkdownPane {
            id: seamPane
            width: 560
            height: 200
            visible: false
            active: true
            path: shell.fixture
            size: 1
            view: "source"
        }

        Image { id: shot; width: 1; height: 1; opacity: 0 }

        Canvas {
            id: probe
            width: 560
            height: 1080
            opacity: 0
            onPaint: {
                if (shell.armed && !shell.done)
                    shell.analyze(getContext("2d"))
            }
        }
    }

    function types() {
        return md.blockList.map(function (b) { return b.type }).join(",")
    }

    function rectOf(i) {
        var item = md.blockItem(i)
        return { x: Math.round(item.x), y: Math.round(item.y),
                 w: Math.round(item.width), h: Math.round(item.height) }
    }

    function fail(why) {
        if (shell.done)
            return
        shell.done = true
        shell.log("FAIL " + why)
        shell.quit()
    }

    function figuresSettled() {
        for (var i = 1; i <= 3; i++) {
            var info = md.figureInfo(i)
            if (!info || !info.ready)
                return false
        }
        var bad = md.figureInfo(4)
        return bad !== null && bad.failed
    }

    Timer {
        id: poll
        interval: 200
        repeat: true
        running: true
        onTriggered: shell.drive()
    }

    Timer {
        interval: 90000
        repeat: false
        running: !shell.done
        onTriggered: shell.fail("the watchdog outlived the verdict")
    }

    function check(error, name) {
        shell.log((error === "" ? "CHECK " : "FAIL ") + name + (error === "" ? "" : ": " + error))
        if (error !== "")
            shell.failures++
    }

    function checkFar(tag) {
        var view = md.bodyItem
        var end = view.contentY + view.height + view.cacheBuffer
        var top = Checks.farTop(md, shell.padding, shell.paragraphHeight)
        var item = md.blockItem(shell.farIndex)
        if (!(top > end) || (item && item.y <= end)) {
            shell.fail("fixture far figure at " + top + " is inside cache end " + end + " on " + tag)
            return false
        }
        shell.log("far top=" + top + " cacheEnd=" + end + " padding=" + shell.padding + " (" + tag + ")")
        return true
    }

    function drive() {
        if (shell.step === 0) {
            if (shell.fixture.length === 0)
                return shell.fail("no fixture arrived in FLEA_MARKDOWN_FIGURE_FIXTURE")
            if (!md.contentReady)
                return
            if (!seamPane.contentReady)
                return
            if (seamPane.blockList === undefined)
                return shell.fail("the Quick Look pane exposes no block list for the seam")
            if (typeof seamPane.figureInfo !== "function")
                return shell.fail("the Quick Look pane exposes no figureInfo for the seam")
            if (seamPane.blockList.length !== md.blockList.length)
                return shell.fail("the seam pane lists " + seamPane.blockList.length + " blocks, want " + md.blockList.length)
            shell.log("blocks=" + shell.types())
            var head = md.blockList.slice(0, 6).map(function (b) { return b.type }).join(",")
            if (head !== "run,figure,figure,figure,figure,run")
                return shell.fail("the head blocks are " + head + ", want run,figure,figure,figure,figure,run")
            if (md.blockList[1].kind !== "mermaid" || md.blockList[2].kind !== "math"
                    || md.blockList[3].kind !== "math" || md.blockList[4].kind !== "mermaid")
                return shell.fail("the figure kinds misread")
            shell.farIndex = md.blockList.length - 1
            if (md.blockList[shell.farIndex].type !== "figure")
                return shell.fail("the tail block is not a figure")
            shell.inlineIndex = 5
            if (String(md.blockList[5].text).indexOf('data-math="inline"') < 0)
                return shell.fail("the inline paragraph kept no maths chip")
            var paragraph = md.blockItem(5)
            if (!paragraph || paragraph.height <= 0)
                return
            shell.paragraphHeight = paragraph.height
            var view = md.bodyItem
            var end = view.contentY + view.height + view.cacheBuffer
            shell.padding = Checks.paddingCount(end, paragraph.y + paragraph.height,
                paragraph.height, view.spacing)
            var blocks = md.blockList.slice(0, 6)
            for (var p = 0; p < shell.padding; p++)
                blocks.push(md.blockList[5])
            blocks.push(md.blockList[shell.farIndex])
            shell.farIndex = blocks.length - 1
            md.blockList = blocks
            md.view = "rendered"
            shell.t0 = Date.now()
            shell.step = 1
        } else if (shell.step === 1) {
            if (!shell.figuresSettled()) {
                if (Date.now() - shell.t0 > 20000)
                    return shell.fail("the near figures never settled")
                return
            }
            for (var i = 1; i <= 3; i++) {
                var info = md.figureInfo(i)
                if (info.boxW > md.width + 1)
                    return shell.fail("figure " + i + " runs past the text width")
                // The stub draws 800 px wide scaled into the frame; a real
                // formula is 15 px wide, so only the real bound is the floor.
                if (shell.figMode === "real") {
                    if (!(info.imgW > 0 && info.imgW <= 800 && info.imgH > 0))
                        return shell.fail("figure " + i + " missed its scaled geometry")
                } else if (!(info.imgW > 100 && info.imgW < 800 && info.imgH > 0)) {
                    return shell.fail("figure " + i + " missed its scaled geometry")
                }
            }
            if (!shell.checkFar("first"))
                return
            for (var b = 1; b <= 3; b++)
                shell.check(Checks.surfaceError(md.blockItem(b)), "ready figure " + b + " page ground")
            if (shell.figMode === "real") {
                var svg = Checks.figure(md, 1).svg
                shell.check(Checks.labelError(svg, Checks.bodyFont(md), md.inkHex),
                    "Mermaid body typography and foreground")
                shell.check(Checks.paletteError(svg, [md.hexOf(Flea.Theme.color.background), md.inkHex,
                    md.accentHex, md.borderHex, md.chromeHex]), "Mermaid theme edges and nodes")
            }
            // A live delegate past the cache still sent nothing while it holds
            // no answer and no ticket; only a working, ready or failed far one did.
            var far = md.figureInfo(shell.farIndex)
            if (far !== null && (far.working || far.ready || far.failed))
                return shell.fail("the far figure was asked for despite sitting past the cache")
            shell.sendsMark = Flea.FigureService.sends
            shell.log("near figures drawn, far figure unasked, sends=" + shell.sendsMark)
            md.view = "source"
            shell.t0 = Date.now()
            shell.step = 2
        } else if (shell.step === 2) {
            if (Date.now() - shell.t0 < 600)
                return
            if (Flea.FigureService.sends !== shell.sendsMark)
                return shell.fail("the Source view sent a figure request")
            shell.log("source view asked for nothing")
            md.view = "rendered"
            shell.t0 = Date.now()
            shell.step = 3
        } else if (shell.step === 3) {
            if (!shell.figuresSettled()) {
                if (Date.now() - shell.t0 > 10000)
                    return shell.fail("the figures never came back after Source")
                return
            }
            // The error answer is never cached, so the malformed figure re-sends
            // here; the cache pin lives in tests/markdown-figures.qml instead.
            // What matters is the figures come back and the far one stays unasked.
            if (!shell.checkFar("return"))
                return
            var farAgain = md.figureInfo(shell.farIndex)
            if (farAgain !== null && (farAgain.working || farAgain.ready || farAgain.failed))
                return shell.fail("the far figure was asked for on the return trip")
            shell.log("rendered again, far figure still unasked")
            poll.stop()
            shell.log("grabbing")
            grabRoot.grabToImage(shell.grabbed)
        }
    }

    function grabbed(result) {
        if (!result.saveToFile(shell.shotPath)) {
            shell.fail("the grab could not be saved")
            return
        }
        shell.log("grab " + shell.shotPath)
        shot.source = "file://" + shell.shotPath
    }

    Connections {
        target: shot
        function onStatusChanged() {
            if (shot.status === Image.Ready) {
                shell.armed = true
                probe.requestPaint()
            } else if (shot.status === Image.Error)
                shell.fail("the saved grab would not reload")
        }
    }

    // Pixel facts off the reloaded grab: each good figure holds ink that is
    // not the chrome surface, the inline maths keeps its chrome chip and the
    // malformed figure draws the fence look (fill, no border).
    function analyze(ctx) {
        var w = 560
        var h = 1080
        ctx.drawImage(shot, 0, 0)
        var pixels = ctx.getImageData(0, 0, w, h).data
        function at(x, y) {
            var o = (y * w + x) * 4
            return [pixels[o], pixels[o + 1], pixels[o + 2]]
        }
        function same(a, b) { return a[0] === b[0] && a[1] === b[1] && a[2] === b[2] }
        function parse(s) {
            return [parseInt(s.slice(1, 3), 16), parseInt(s.slice(3, 5), 16), parseInt(s.slice(5, 7), 16)]
        }
        var border = parse(String(md.borderHex).toLowerCase())
        var chrome = parse(String(md.chromeHex).toLowerCase())
        // Empty canvas reads as the window ground or transparent black, so
        // neither counts as figure ink, only a drawn mark does.
        function isInk(c) {
            return !same(c, chrome) && !(c[0] === 16 && c[1] === 19 && c[2] === 21)
                && !(c[0] === 0 && c[1] === 0 && c[2] === 0)
        }
        for (var f = 1; f <= 3; f++) {
            var fr = shell.rectOf(f)
            var ink = 0
            for (var fy = fr.y; fy < fr.y + fr.h; fy++)
                for (var fx = fr.x; fx < fr.x + fr.w; fx++)
                    if (isInk(at(fx, fy)))
                        ink++
            shell.log("figure " + f + " ink px=" + ink)
            if (ink < 40)
                return shell.fail("figure " + f + " drew no ink in " + shell.figMode + " mode")
        }

        var flowInk = Checks.inkBounds(pixels, w, shell.rectOf(1), [16, 19, 21], chrome)
        var font = Checks.bodyFont(md)
        if (shell.figMode === "real") {
            var mathInk = Checks.inkBounds(pixels, w, shell.rectOf(3), [16, 19, 21], chrome)
            shell.log("x^2 ink rows=" + mathInk.height + " bodyPx=" + font.pixelSize)
            shell.check(Checks.mathError(mathInk.height, font.pixelSize), "display maths body scale")
        }
        var first = shell.rectOf(6)
        var second = shell.rectOf(7)
        var paragraphGap = second.y - first.y - first.h
        shell.check(Checks.spacingError(shell.rectOf(0), shell.rectOf(1), shell.rectOf(2),
            flowInk, paragraphGap), "figure paragraph spacing")

        var inline = shell.rectOf(shell.inlineIndex)
        var chip = 0
        for (var y = inline.y; y < inline.y + inline.h; y++)
            for (var x = inline.x; x < inline.x + inline.w; x++)
                if (same(at(x, y), chrome))
                    chip++
        shell.log("inline chip px=" + chip)
        if (chip < 40)
            return shell.fail("the inline maths lost its code chip")

        var fence = shell.rectOf(4)
        var edgeMuted = 0
        var edgeFill = 0
        for (var ex = fence.x; ex < fence.x + fence.w; ex++) {
            if (same(at(ex, fence.y), border))
                edgeMuted++
            if (same(at(ex, fence.y), chrome))
                edgeFill++
            if (same(at(ex, fence.y + fence.h - 1), border))
                edgeMuted++
            if (same(at(ex, fence.y + fence.h - 1), chrome))
                edgeFill++
        }
        for (var ey = fence.y; ey < fence.y + fence.h; ey++) {
            if (same(at(fence.x, ey), border))
                edgeMuted++
            if (same(at(fence.x, ey), chrome))
                edgeFill++
            if (same(at(fence.x + fence.w - 1, ey), border))
                edgeMuted++
            if (same(at(fence.x + fence.w - 1, ey), chrome))
                edgeFill++
        }
        shell.log("fallback edge muted=" + edgeMuted + " fill=" + edgeFill)
        if (edgeMuted > 0)
            return shell.fail("the fallback kept a border")
        if (edgeFill < 100)
            return shell.fail("the fallback lost its fill")

        for (var py = 0; py < h; py++)
            for (var px = 0; px < w; px++) {
                var c = at(px, py)
                if (c[2] >= 200 && c[0] <= 110 && c[1] <= 170)
                    return shell.fail("a Qt default link blue survived at " + px + "," + py)
            }
        if (shell.failures > 0)
            return shell.fail(shell.failures + " visual checks failed")
        shell.done = true
        shell.log("PASS (" + shell.figMode + ") three figures, one mono fallback, widths fit, far figure unasked")
        shell.quit()
    }
}
