//@ pragma ShellId flea-markdown-render-test

import QtQuick
import Quickshell
import "flea" as Flea
import "markdown-render.js" as Checks

// tests/markdown-render.sh's harness: the real ui/PreviewMarkdown.qml over a fixture
// document, grabbed and judged on pixel facts, offscreen. Quits itself, pass or fail.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_RENDER " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property string fixture: Quickshell.env("FLEA_MARKDOWN_FIXTURE")
    property string shotPath: Quickshell.env("XDG_RUNTIME_DIR") + "/markdown-render-" + Quickshell.processId
        + (shell.larger ? "-large.png" : "-base.png")
    property bool done: false
    // The Canvas paints on its own when it loads, so analysis runs only once armed behind a grab.
    property bool armed: false
    // The native cap_markdown case flips Rendered/Source twice (r, r); the driver
    // below replays both flips before the grab, or the contentHeight loop never
    // fires offscreen. A resize alone does not trigger it.
    property int driveStep: 0
    property int failures: 0
    property var savedState: ({})
    property int suiteBody: 0
    property bool larger: false

    FontMetrics { id: listMetrics; font.family: Flea.Theme.font.family; font.pixelSize: Flea.Theme.font.body }

    function listSamples() {
        var samples = []
        for (var i = 0; i < md.blockList.length; i++) {
            var b = md.blockList[i]
            if (b.type === "list")
                for (var r = 0; r < b.items.length; r++)
                    samples.push({ marker: b.ordered ? (b.start + r) + "." : String.fromCharCode(8226), text: b.items[r] })
        }
        return samples
    }

    function referenceLine(marker, text) {
        for (var i = 0; i < references.count; i++) {
            var item = references.itemAt(i)
            if (item.sample.marker === marker && item.sample.text === text)
                return { item: item, split: listMetrics.advanceWidth(marker + "  ") }
        }
        return null
    }

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
                view: "rendered"
            }

            Column {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.leftMargin: md.insetX
                Repeater {
                    id: references
                    model: shell.listSamples()
                    delegate: Flea.MarkdownText {
                        required property var modelData
                        readonly property var sample: modelData
                        textFormat: Text.RichText
                        text: sample.marker + "&nbsp;&nbsp;&nbsp;&nbsp;" + sample.text
                        wrapMode: Text.NoWrap
                    }
                }
            }
        }

        // Loaders only: the grab reads md, so neither paints into it.
        // Quick Look's own component: the board's bar order and code surface live there, so the suite reads through it.
        Flea.MarkdownPane {
            id: pane
            width: 900
            height: 1000
            visible: false
            active: true
            path: shell.fixture
            size: 1
            view: "rendered"
        }

        Flea.MarkdownFigure {
            id: fallbackProbe
            width: 420
            visible: false
            askArmed: false
            source: "first source line\nsecond source line"
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

    function blockIndex(type, text, wantOrdered) {
        for (var i = 0; i < md.blockList.length; i++) {
            var b = md.blockList[i]
            if (b.type !== type)
                continue
            if (wantOrdered !== undefined && b.ordered !== wantOrdered)
                continue
            if (text !== undefined && String(b.text || "").indexOf(text) < 0)
                continue
            return i
        }
        return -1
    }

    // Window coordinates, which are the grab's pixels: the list's top margin moves its content below the frame's top.
    function rectOf(i) {
        var item = md.blockItem(i)
        var at = item.mapToItem(grabRoot, 0, 0)
        return { x: Math.round(at.x), y: Math.round(at.y),
                 w: Math.round(item.width), h: Math.round(item.height) }
    }

    // A list block's first marker, in window coordinates.
    function markerX(i) {
        var mark = Checks.markerOf(md.blockItem(i))
        return mark === null ? -1 : Math.round(mark.mapToItem(grabRoot, 0, 0).x)
    }

    function check(error, name) {
        shell.log((error === "" ? "CHECK " : "FAIL ") + name + (error === "" ? "" : ": " + error))
        if (error !== "")
            shell.failures++
    }

    // Both lists are measured at the suite's size and a larger supported text-size stop.
    function listBaselines(inkAt) {
        var body = Flea.Theme.font.body
        for (var i = 0; i < md.blockList.length; i++) {
            var block = md.blockList[i]
            if (block.type === "list")
                shell.check(Checks.listBaselineError(md.blockItem(i), md, block.items.length, body, grabRoot, inkAt, shell.referenceLine),
                    (block.ordered ? "ordered" : "bullet") + " baselines at body " + body)
        }
    }

    // The board's geometry against the live tree: insets, rhythm, headings, line boxes, the code surface and the bar.
    function geometry() {
        var rects = []
        var texts = []
        var body = Flea.Theme.font.body
        // md_rendered is drawn at body 14, so the board's own numbers are judged only where the box runs at 14.
        shell.log("body=" + body + " inset=" + md.insetY + "," + md.insetX + " gap=" + md.blockGap)
        var ink = String(Flea.Theme.color.foreground)
        var h1 = null
        var h2 = null
        var para = null
        for (var i = 0; i < md.blockList.length; i++) {
            var type = md.blockList[i].type
            rects.push(shell.rectOf(i))
            var text = type === "run" || type === "heading" ? Checks.textOf(md.blockItem(i)) : null
            if (text === null)
                continue
            texts.push({ name: type + " " + i, text: text, h: Math.round(md.blockItem(i).height) })
            if (type === "heading" && md.blockList[i].level === 1) h1 = text
            else if (type === "heading" && md.blockList[i].level === 2) h2 = text
            else if (type === "run" && para === null) para = text
        }
        shell.check(Checks.insetError(rects, md.width, md.insetX, md.insetY, body), "document inset")
        shell.check(Checks.rhythmError(rects, Flea.Theme.spacing.rowPaddingY), "block rhythm")
        shell.check(Checks.headingError(h1, h2, para, body, ink), "heading sizes and ink")
        shell.check(Checks.lineBoxError(texts), "line boxes")
        shell.check(Checks.quoteBoxError(md.blockItem(shell.blockIndex("quote")), md), "quote bar spans line box")
        var tableIndex = shell.blockIndex("table")
        var table = md.blockList[tableIndex]
        shell.check(Checks.tableBaselineError(md.blockItem(tableIndex), md, table.rows.length + 1, table.cols),
            "table header and body baselines")
        shell.check(Checks.remoteLineError(md.blockItem(shell.blockIndex("remote")), md), "remote placeholder centres")
        shell.check(Checks.fencePadError(Checks.fallbackOf(fallbackProbe), Flea.Theme.spacing.gap, Flea.Theme.spacing.gap),
            "figure fallback padding")
        var fence = Checks.fenceOf(md.blockItem(shell.blockIndex("fence")))
        shell.check(Checks.surfaceError(fence, String(Flea.Theme.color.surface), String(Flea.Theme.color.background)), "column fence surface")
        shell.check(Checks.fencePadError(fence, md.fencePadX, md.fencePadY), "fence padding")
        var qlFence = pane.blockItem ? Checks.fenceOf(pane.blockItem(shell.blockIndex("fence"))) : null
        shell.check(Checks.surfaceError(qlFence, String(Flea.Theme.color.background), String(Flea.Theme.color.surface)), "Quick Look fence surface")
        var g = pane.barGeometry ? pane.barGeometry() : null
        shell.check(Checks.barError(g, { chromeMark: Flea.Theme.chromeMarkSize, padX: Flea.Theme.spacing.rowPaddingX,
            gap: Flea.Theme.spacing.gap, chromeHeight: Flea.Theme.chromeHeight }), "Quick Look bar order")
    }

    function fail(why) {
        if (shell.done)
            return
        shell.done = true
        shell.log("FAIL " + why)
        shell.quit()
    }

    function pass(note) {
        if (shell.done)
            return
        shell.done = true
        shell.log("PASS " + note)
        shell.quit()
    }

    Timer {
        id: settle
        interval: 1200
        repeat: false
        running: true
        onTriggered: {
            if (shell.fixture.length === 0)
                shell.fail("no fixture arrived in FLEA_MARKDOWN_FIXTURE")
            else if (!md.contentReady || !pane.contentReady)
                shell.fail("the document never loaded")
            else if (md.flickContentHeight > md.height)
                shell.fail("the fixture overflowed its frame")
            else {
                shell.log("blocks=" + md.blockList.map(function (b) { return b.type }).join(",")
                    + " border=" + md.borderHex + " ink=" + md.inkHex + " chrome=" + md.chromeHex
                    + " run0=" + JSON.stringify(String(md.blockList[0].text).slice(0, 120))
                    + " content=" + Math.round(md.flickContentHeight))
                driver.start()
            }
        }
    }

    // The r, r flip pair: each step settles before the next, and the grab waits
    // one extra step past the flip back to rendered.
    Timer {
        id: driver
        interval: 350
        repeat: true
        running: false
        onTriggered: {
            shell.driveStep++
            shell.log("step=" + shell.driveStep + " content=" + Math.round(md.flickContentHeight))
            if (shell.driveStep === 1) md.view = "source"
            else if (shell.driveStep === 2) md.view = "rendered"
            else {
                driver.stop()
                fallbackProbe.error = "fixture refusal"
                shell.log("grabbing")
                grabRoot.grabToImage(shell.grabbed)
            }
        }
    }

    // The larger layout must settle before its second grab, while the base-size failures remain counted.
    Timer {
        id: largerSettle
        interval: 350
        onTriggered: {
            fallbackProbe.error = "fixture refusal"
            grabRoot.grabToImage(shell.grabbed)
        }
    }

    Timer {
        interval: 30000
        repeat: false
        running: !shell.done
        onTriggered: shell.fail("the watchdog outlived the verdict")
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

    // Pixel facts off the reloaded grab, in image coordinates, which are the
    // component's own: the grab reads root at its size, md sitting at its top.
    function analyze(ctx) {
        var w = 560
        var h = 1080
        ctx.clearRect(0, 0, w, h)
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
        shell.geometry()
        var border = parse(String(md.borderHex).toLowerCase())
        var chrome = parse(String(md.chromeHex).toLowerCase())
        // The CI theme's foreground is its own gray, never the board's #c0caf5, so ink reads
        // off the component beside the border rather than off a hardcoded token.
        var fg = parse(String(md.inkHex).toLowerCase())
        var ground = parse(String(window.color).toLowerCase())
        function inkAt(x, y) {
            if (x < 0 || x >= w || y < 0 || y >= h)
                return false
            var c = at(x, y)
            var toInk = 0
            var toGround = 0
            for (var i = 0; i < 3; i++) {
                toInk += Math.abs(c[i] - fg[i])
                toGround += Math.abs(c[i] - ground[i])
            }
            return toInk < toGround
        }
        shell.listBaselines(inkAt)
        if (shell.larger) {
            shell.check(Flea.Theme.font.body > shell.suiteBody ? "" : "text size did not grow", "larger text size")
            Flea.ViewState.state = shell.savedState
            if (shell.failures > 0)
                return shell.fail(shell.failures + " geometry checks failed")
            return shell.pass("run, chip, markers at two sizes, rules, fence, box, bar and links all read")
        }

        // The chrome chip behind the inline code, confined to its line, never full-bleed.
        var codeIdx = shell.blockIndex("run", "<code")
        if (codeIdx < 0)
            return shell.fail("no run carried a styled code span")
        var run = shell.rectOf(codeIdx)
        var chip = 0
        var chipCols = {}
        for (var y = run.y; y < run.y + run.h; y++)
            for (var x = run.x; x < run.x + run.w; x++)
                if (same(at(x, y), chrome)) {
                    chip++
                    chipCols[x] = true
                }
        // The paragraph is one line box, so the chip is told from a full-width bar by its columns, not its rows.
        var chipColCount = Object.keys(chipCols).length
        shell.log("chip px=" + chip + " cols=" + chipColCount + " of " + run.w)
        if (chip < 40)
            return shell.fail("the chrome surface is missing behind the inline code")
        if (chipColCount > run.w * 0.4)
            return shell.fail("the chrome paint is no chip")

        // The leftmost ink column over a y band, for marker and paragraph alignment.
        // Any ink counts, not exact foreground: a thin marker antialiases without a pure
        // core pixel, while empty canvas reads as window background or transparent black.
        function painted(c) {
            return !((c[0] === 16 && c[1] === 19 && c[2] === 21) || (c[0] === 0 && c[1] === 0 && c[2] === 0))
        }
        function firstInk(rect, y0, y1) {
            for (var fx = rect.x; fx < rect.x + 40; fx++)
                for (var fy = y0; fy < y1; fy++)
                    if (painted(at(fx, fy)))
                        return fx
            return -1
        }
        var para0 = shell.rectOf(shell.blockIndex("run"))
        var orderedIdx = shell.blockIndex("list", undefined, true)
        if (orderedIdx < 0)
            return shell.fail("no ordered list block arrived")
        var orderedRect = shell.rectOf(orderedIdx)
        var orderedX = firstInk(orderedRect, orderedRect.y, orderedRect.y + 22)
        var orderedMark = shell.markerX(orderedIdx)
        var bulletIdx = shell.blockIndex("list", undefined, false)
        if (bulletIdx < 0)
            return shell.fail("no bullet list block arrived")
        var bulletRect = shell.rectOf(bulletIdx)
        var bulletX = firstInk(bulletRect, bulletRect.y, bulletRect.y + 22)
        var bulletMark = shell.markerX(bulletIdx)
        // The marker boxes share the paragraph's edge exactly; the ink sits a glyph bearing inside its own box.
        shell.log("marker box x ordered=" + orderedMark + " bullet=" + bulletMark + " paragraph=" + para0.x
            + ", ink ordered=" + orderedX + " bullet=" + bulletX)
        if (orderedMark !== para0.x || orderedX < orderedMark || orderedX - orderedMark > 3)
            return shell.fail("the ordered marker left the paragraph edge")
        if (bulletMark !== para0.x || bulletX < bulletMark || bulletX - bulletMark > 3)
            return shell.fail("the bullet marker left the paragraph edge")

        var tableIdx = shell.blockIndex("table")
        if (tableIdx < 0)
            return shell.fail("no table block arrived")
        var table = shell.rectOf(tableIdx)
        // A rule spans the hugged table, far narrower than the full-width delegate.
        var rules = 0
        for (var ry = table.y; ry < table.y + table.h; ry++) {
            var span = 0
            for (var rx = table.x; rx < table.x + table.w; rx++)
                if (same(at(rx, ry), border))
                    span++
            if (span >= 100)
                rules++
        }
        var verticals = 0
        for (var cx = table.x; cx < table.x + table.w; cx++) {
            var drop = 0
            for (var cy = table.y; cy < table.y + table.h; cy++)
                if (same(at(cx, cy), border))
                    drop++
            if (drop >= table.h * 0.75)
                verticals++
        }
        shell.log("rules=" + rules + " verticals=" + verticals)
        if (rules < 3)
            return shell.fail("the table rules never painted")
        if (verticals > 0)
            return shell.fail("the table drew vertical rules")
        // The table hugs its content: rules start at the left edge, end well short of the
        // frame, track the ink, and a clean vertical gap separates the columns.
        var ruleStart = table.x + table.w
        var ruleEnd = table.x
        var ruleRows = {}
        for (var qy = table.y; qy < table.y + table.h; qy++) {
            var qfirst = -1
            var qlast = -1
            for (var qx = table.x; qx < table.x + table.w; qx++)
                if (same(at(qx, qy), border)) {
                    if (qfirst < 0)
                        qfirst = qx
                    qlast = qx
                }
            if (qlast - qfirst >= 100) {
                ruleRows[qy] = true
                ruleStart = Math.min(ruleStart, qfirst)
                ruleEnd = Math.max(ruleEnd, qlast)
            }
        }
        var inkRight = table.x
        for (var iy = table.y; iy < table.y + table.h; iy++) {
            if (ruleRows[iy])
                continue
            for (var ix = table.x; ix < table.x + table.w; ix++)
                if (painted(at(ix, iy)) && ix > inkRight)
                    inkRight = ix
        }
        var gapX = -1
        for (var gx = table.x + 20; gx < ruleEnd - 20; gx++) {
            var clean = true
            for (var gy = table.y; gy < table.y + table.h; gy++) {
                if (ruleRows[gy])
                    continue
                if (same(at(gx, gy), fg)) {
                    clean = false
                    break
                }
            }
            if (clean) {
                gapX = gx
                break
            }
        }
        shell.log("table x=" + table.x + " rule " + ruleStart + ".." + ruleEnd + " ink to " + inkRight + " gap at " + gapX)
        if (ruleStart - table.x > 4)
            return shell.fail("the table left its left edge")
        if (ruleEnd - table.x > 400)
            return shell.fail("the table rules ran past their content")
        if (ruleEnd - inkRight > 40)
            return shell.fail("the table rules outran their ink")
        if (gapX < 0)
            return shell.fail("the table columns never separate")

        var quoteIdx = shell.blockIndex("quote")
        if (quoteIdx < 0)
            return shell.fail("no quote block arrived")
        var quote = shell.rectOf(quoteIdx)
        var bar = 0
        for (var by = quote.y; by < quote.y + quote.h; by++)
            for (var bx = quote.x; bx < quote.x + 2; bx++)
                if (same(at(bx, by), border))
                    bar++
        shell.log("bar px=" + bar + " of " + (quote.h * 2))
        if (bar < quote.h * 2 * 0.8)
            return shell.fail("the quote bar lost its muted ink")

        // A fenced block is fill with no border: its perimeter carries surface, never muted.
        var fenceIdx = shell.blockIndex("fence")
        if (fenceIdx < 0)
            return shell.fail("no fence block arrived")
        var fence = shell.rectOf(fenceIdx)
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
        shell.log("fence edge muted=" + edgeMuted + " fill=" + edgeFill)
        if (edgeMuted > 0)
            return shell.fail("the fence kept its border")
        if (edgeFill < 100)
            return shell.fail("the fence lost its fill")

        // The remote box closes its four dashed edges, and its line starts left of centre.
        var remoteIdx = shell.blockIndex("remote")
        if (remoteIdx < 0)
            return shell.fail("no remote block arrived")
        var box = shell.rectOf(remoteIdx)
        // One dashed edge, first to last border pixel along it.
        function dashSpan(horizontal, fixed, from, to) {
            var first = -1
            var last = -1
            for (var i = from; i < to; i++) {
                var c = horizontal ? at(i, fixed) : at(fixed, i)
                if (same(c, border)) {
                    if (first < 0)
                        first = i
                    last = i
                }
            }
            return [first, last]
        }
        var top = dashSpan(true, box.y, box.x, box.x + box.w)
        var bottom = dashSpan(true, box.y + box.h - 1, box.x, box.x + box.w)
        var left = dashSpan(false, box.x, box.y, box.y + box.h)
        var right = dashSpan(false, box.x + box.w - 1, box.y, box.y + box.h)
        shell.log("remote top=" + top + " bottom=" + bottom + " left=" + left + " right=" + right)
        if (top[0] - box.x > 8 || box.x + box.w - 1 - top[1] > 20
                || bottom[0] - box.x > 8 || box.x + box.w - 1 - bottom[1] > 20
                || left[0] - box.y > 8 || box.y + box.h - 1 - left[1] > 20
                || right[0] - box.y > 8 || box.y + box.h - 1 - right[1] > 20)
            return shell.fail("the remote box never closed its rectangle")
        var lineStart = box.x + box.w
        for (var ly = box.y + 4; ly < box.y + box.h - 4; ly++)
            for (var lx = box.x + 4; lx < box.x + box.w - 4; lx++) {
                var lc = at(lx, ly)
                if (same(lc, fg) || same(lc, border)) {
                    if (lx < lineStart)
                        lineStart = lx
                    break
                }
            }
        shell.log("remote line starts at " + lineStart + " of centre " + (box.x + box.w / 2))
        if (lineStart >= box.x + box.w / 2)
            return shell.fail("the remote line drifted past centre")

        for (var py = 0; py < h; py++)
            for (var px = 0; px < w; px++) {
                var c = at(px, py)
                if (c[2] >= 200 && c[0] <= 110 && c[1] <= 170)
                    return shell.fail("a Qt default link blue survived at " + px + "," + py)
            }
        shell.savedState = Flea.ViewState.state
        shell.suiteBody = Flea.Theme.font.body
        shell.larger = true
        Flea.ViewState.state = Object.assign({}, shell.savedState,
            { display: { textSize: { mode: shell.suiteBody < 16 ? 16 : 20 } } })
        shell.armed = false
        largerSettle.start()
    }
}
