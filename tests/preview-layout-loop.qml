//@ pragma ShellId flea-preview-layout-loop-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea

// Real column and Quick Look hosts, including first Source toggle and nearest documents across overflow.
ShellRoot {
    id: shell
    readonly property string dir: Quickshell.env("FLEA_LAYOUT_DIR")
    property int scenario: -1
    property int stage: 0
    property int cases: 0
    property int ticks: 0
    property int low: 1
    property int high: 96
    property int count: 0
    property int below: 0
    property int above: 0
    property real belowHeight: 0
    property bool scrolling: false
    property bool wheeling: false
    // One downward wheel notch, delivered inside the preview rather than its scrollbar lane.
    readonly property int wheelAngleUnits: -120
    readonly property int wheelHorizontalUnits: 0
    readonly property int wheelDelayMs: 1
    readonly property real wheelCenter: 0.5
    readonly property real scrollTop: 0
    // Rows a focused close ring keeps clear of the surface frame above it and of the bar's rule below it.
    readonly property int ringClearRows: 1
    property int sibling: -1
    property bool done: false
    property bool toggled: false
    property bool preludeDone: false
    property string expectedPath: ""
    // Scenarios 0 and 1 are the column at two widths, which only renders; 2 to 5 are Quick Look, rendered then flipped to Source.
    readonly property int columnScenarios: 2
    readonly property int lastScenario: 5
    readonly property int quickScenarioFirst: 2
    readonly property int quickScenarioLarge: 4
    readonly property bool columnHost: scenario < columnScenarios
    // Before the first scenario the prelude flips a standalone pane to Source, and that cell reads the same view.
    readonly property string view: scenario < 0 || (!columnHost && scenario % 2 === 1) ? "source" : "rendered"

    function log(line) { console.log("PREVIEW_LAYOUT " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function fail(why) { shell.log("FAIL " + why); shell.done = true; shell.quit() }
    function check(cond, why) { if (!cond) shell.fail(why); return cond }
    function find(item, type) {
        if (String(item).indexOf(type) === 0 || String(item).indexOf("QQuick" + type) === 0)
            return item
        var children = item.children || []
        for (var i = 0; i < children.length; i++) {
            var found = shell.find(children[i], type)
            if (found) return found
        }
        return null
    }
    // The delegate carries one Image per block kind, and only the one the block draws has a source.
    function findSourced(item, type) {
        if ((String(item).indexOf(type) === 0 || String(item).indexOf("QQuick" + type) === 0) && String(item.source) !== "")
            return item
        var children = item.children || []
        for (var i = 0; i < children.length; i++) {
            var found = shell.findSourced(children[i], type)
            if (found) return found
        }
        return null
    }
    function markdown() { return shell.find(shell.columnHost ? column : look, "PreviewMarkdown") }
    // The view the host draws, read the way the ipc does: Quick Look's shownView, the column item's own view.
    function drawnView(md) { return shell.columnHost ? md.view : look.markdownView() }
    function flick(item) { return shell.find(item, "Flickable") }
    // Rendered and Source are each a list; the Rendered list's margins sit outside its content.
    function mdFlick(md) { return md.view === "source" ? md.sourceItem : md.bodyItem }
    function top(f) { return f.originY - f.topMargin }
    function bottom(f) { return f.originY + f.contentHeight - f.height + f.bottomMargin }
    // The Source list's first chunk holds the whole of a short document.
    function sourceText(md) {
        var children = md.sourceItem.contentItem.children
        for (var i = 0; i < children.length; i++)
            if (children[i].objectName === "sourceChunk" && children[i].index === 0 && children[i].label.text === md.rawText)
                return children[i].label
        shell.fail("source text is absent")
        return null
    }
    // What the view can scroll: Source text plus its inset, Rendered content plus the list's own margins.
    function extent(md) {
        if (md.view !== "source") return md.bodyItem.contentHeight + md.bodyItem.topMargin + md.bodyItem.bottomMargin
        var text = shell.sourceText(md)
        return text ? text.implicitHeight + 2 * md.insetY : 0
    }
    // The bar the viewer draws for this flickable: inside the Source flickable, on the frame for the lazy list.
    function barFor(md, f) {
        var parent = md.view === "source" ? f : md
        for (var i = 0; i < parent.children.length; i++) {
            var child = parent.children[i]
            if (String(child).indexOf("ViewportScrollBar") === 0 && child.flickable === f) return child
        }
        return null
    }
    // Every block is instantiated at these sizes: the content is each delegate's own height plus the spacing between them.
    function stackedHeight(md) {
        var total = 0
        for (var i = 0; i < md.blockList.length; i++) {
            var item = md.blockItem(i)
            if (!item) { shell.fail("block " + i + " is not instantiated"); return -1 }
            total += item.height
        }
        return total + Math.max(0, md.blockList.length - 1) * md.bodyItem.spacing
    }
    // Each instantiated block delegate is exactly as wide as the list it sits in.
    function delegatesFitList(md) {
        for (var i = 0; i < md.blockList.length; i++) {
            var item = md.blockItem(i)
            if (!item) { shell.fail("block " + i + " is not instantiated"); return false }
            if (item.width !== md.bodyItem.width) return false
        }
        return true
    }

    FloatingWindow {
        implicitWidth: 1400
        implicitHeight: 920
        color: Flea.Theme.color.background
        TestEvent { id: driver }
        Flea.PreviewMarkdown {
            id: firstToggle
            x: 1020
            width: 350
            height: 573
            active: !shell.preludeDone
            path: shell.dir + "/mixed.md"
            size: 1
            view: "rendered"
        }
        Flea.PreviewColumn { id: column; width: 380; height: 860 }
        Item {
            id: lookHost
            width: 1000
            height: 800
            Flea.Preview { id: look; anchors.fill: parent }
        }
    }

    function show(path, icon) {
        shell.expectedPath = shell.dir + "/" + path
        if (shell.columnHost) {
            column.path = shell.expectedPath
            column.meta = {}
            column.kindName = "layout fixture"
            column.row = { n: path, d: false, s: 1, m: 1, p: 33188, i: icon, t: false, k: 0 }
            column.noThumbComing = true
        } else {
            look.open(shell.expectedPath, icon, 1, "layout fixture", "")
        }
        shell.ticks = 0
    }
    function showCount(n) { shell.count = n; shell.show("edge-" + n + ".md", "text-plain") }
    function begin() {
        shell.scenario++
        if (shell.scenario > shell.lastScenario) {
            shell.nextSibling()
            return
        }
        look.close()
        column.row = null
        column.width = shell.scenario < 1 ? 380 : 760
        lookHost.width = shell.scenario < shell.quickScenarioLarge ? 500 : 1000
        lookHost.height = shell.scenario < shell.quickScenarioLarge ? 400 : 800
        // The flip lives in the open Quick Look, so the host sets it after the close that forgot the last one.
        look.markdownSource = shell.view === "source"
        shell.low = 1
        shell.high = 96
        shell.below = 0
        shell.above = 0
        shell.stage = 0
        shell.scrolling = false
        shell.showCount(48)
    }
    // The wheel call can run the event loop: ticks stand aside until it returns, and only then do the scroll checks open.
    function wheelDown(f) {
        shell.wheeling = true
        driver.mouseWheel(f, f.width * shell.wheelCenter, f.height * shell.wheelCenter,
            Qt.NoButton, Qt.NoModifier, shell.wheelHorizontalUnits, shell.wheelAngleUnits, shell.wheelDelayMs)
        shell.wheeling = false
        shell.scrolling = true
    }
    // The Markdown pane lies inside the surface's own hairline frame, and the focused close ring keeps a clear row from that frame and from the bar's rule.
    function quickLookFrame(label) {
        var pane = look.markdownItem
        var surface = look.panesItem.parent
        var edge = surface.border.width
        var at = pane.mapToItem(surface, 0, 0)
        if (!shell.check(at.x === edge && at.y === edge && at.x + pane.width === surface.width - edge && at.y + pane.height === surface.height - edge,
            label + " Markdown pane fills " + at.x + "," + at.y + " " + pane.width + "x" + pane.height + " of the " + surface.width + "x" + surface.height
            + " surface, want a " + edge + " px frame clear on every side")) return
        look.markdownCloseFocus = true
        var ring = pane.barGeometry().close.ringItem
        var bar = pane.barGeometry().bar
        var rect = ring.mapToItem(surface, 0, 0, ring.width, ring.height)
        var rule = bar.mapToItem(surface, 0, bar.height).y - Flea.Theme.spacing.hairline
        var shown = ring.visible
        look.markdownCloseFocus = false
        if (!shell.check(shown, label + " close ring is not drawn while focused")) return
        shell.check(rect.y - edge >= shell.ringClearRows && rule - (rect.y + rect.height) >= shell.ringClearRows,
            label + " close ring rows " + rect.y + ".." + (rect.y + rect.height) + " keep " + (rect.y - edge) + " clear under the frame and "
            + (rule - (rect.y + rect.height)) + " above the bar rule at row " + rule + ", want " + shell.ringClearRows)
    }
    function cell(label, md) {
        var f = shell.mdFlick(md)
        var h = shell.extent(md)
        var inset = md.view === "source" ? 0 : 2 * md.insetX
        if (!shell.check(shell.drawnView(md) === shell.view && md.view === shell.view,
            label + " measured the " + shell.drawnView(md) + " layout, not the scenario's " + shell.view)) return
        if (!shell.check(md.width === f.width + inset && md.height === f.height, "reader left its viewport")) return
        if (md.view === "source") {
            var text = shell.sourceText(md)
            if (!text) return
            if (!shell.check(text.x === md.insetX && text.width === f.width - 2 * md.insetX, "source text width changed")) return
            if (!shell.check(Math.abs(f.contentHeight - h) < 0.1, "content height is stale")) return
        } else {
            if (!shell.check(md.bodyItem.width === md.width - 2 * md.insetX, "rendered text width changed")) return
            if (!shell.check(shell.delegatesFitList(md), "a block delegate is not as wide as the list")) return
            var stacked = shell.stackedHeight(md)
            if (stacked < 0) return
            if (!shell.check(Math.abs(f.contentHeight - stacked) < 0.1, "content height is stale")) return
        }
        if (!shell.columnHost) shell.quickLookFrame(label)
        if (shell.done) return
        var bar = shell.barFor(md, f)
        if (!shell.check(bar && bar.width === Flea.Theme.spacing.rowPaddingX,
            "scroll lane changed its fixed overlay geometry")) return
        if (!shell.check(bar.overflow === (h - f.height > 0.5), "overflow disagrees with laid-out content")) return
        shell.cases++
        shell.log("CASE " + shell.cases + " " + (shell.columnHost ? "column" : "quicklook")
            + " " + md.view + " " + label + " frame=" + md.width + "x" + md.height + " content=" + h
            + " bare=" + f.contentHeight + " overflow=" + bar.overflow)
    }
    function advanceMarkdown() {
        var md = shell.markdown()
        if (!md || !md.contentReady || md.path !== shell.expectedPath) {
            if (shell.ticks === 10) shell.log("WAIT markdown=" + md + " ready=" + (md ? md.contentReady : false)
                + " path=" + (md ? md.path : "") + " view=" + (md ? md.view : "") + " column=" + column.previewState)
            return
        }
        // The document under measure is in, so a view that is not the scenario's is a lost flip, not a wait.
        if (!shell.check(shell.drawnView(md) === shell.view, "scenario " + shell.scenario + " draws the "
            + shell.drawnView(md) + " layout, not its " + shell.view)) return
        if (shell.stage < 3 && md.rawText.indexOf("edge " + shell.count + "\n") !== 0) return
        if (shell.stage === 3 && md.rawText.indexOf("# Overflow edge") !== 0) return
        var h = shell.extent(md)
        if (shell.stage === 0) {
            if (h <= md.height) { shell.below = shell.count; shell.low = shell.count + 1 }
            else { shell.above = shell.count; shell.high = shell.count - 1 }
            if (shell.low <= shell.high) {
                shell.showCount(Math.floor((shell.low + shell.high) / 2))
                return
            }
            if (!shell.check(shell.below > 0 && shell.above === shell.below + 1, "overflow was not bracketed")) return
            shell.stage = 1
            shell.showCount(shell.below)
        } else if (shell.stage === 1) {
            if (!shell.check(h <= md.height, "short document overflowed")) return
            shell.belowHeight = h
            shell.cell("short", md)
            shell.stage = 2
            shell.showCount(shell.above)
        } else if (shell.stage === 2 && !shell.scrolling) {
            if (!shell.check(h > md.height && h - shell.belowHeight < 40, "tall document missed overflow edge")) return
            shell.cell("tall", md)
            if (shell.done) return
            var f = shell.mdFlick(md)
            if (!shell.check(f.contentY === shell.top(f), "overflow scroll did not start at the top")) return
            shell.wheelDown(f)
        } else if (shell.stage === 2) {
            var f = shell.mdFlick(md)
            if (f.moving) return
            if (!shell.check(f.contentY > shell.top(f), "overflow could not scroll")) return
            if (!shell.check(f.contentY <= shell.bottom(f), "overflow scrolled past its content bounds")) return
            shell.scrolling = false
            shell.stage = 3
            shell.show("mixed.md", "text-plain")
        } else {
            if (!shell.check(md.blockList.some(function(b) { return b.type === "table" })
                && md.blockList.some(function(b) { return b.type === "image" }), "mixed blocks never arrived")) return
            var imageBlock = md.blockList.findIndex(function(b) { return b.type === "image" })
            var image = shell.findSourced(md.blockItem(imageBlock), "Image")
            if (!image || image.status !== Image.Ready) return
            shell.cell("image-table-fence", md)
            if (shell.done) return
            shell.begin()
        }
    }
    function nextSibling() {
        shell.sibling++
        shell.scenario = shell.sibling < 4 ? 0 : shell.quickScenarioFirst
        look.close()
        column.row = null
        column.width = 380
        lookHost.width = 1000
        lookHost.height = 800
        if (shell.sibling === 8) {
            shell.log("PASS cases=" + shell.cases)
            shell.log("DONE")
            shell.done = true
            shell.quit()
            return
        }
        var kind = shell.sibling % 4
        shell.show(["plain.txt", "code.rs", "page.pdf", "local.svg"][kind],
            ["text-plain", "text-x-script", "application-pdf", "image-svg+xml"][kind])
    }
    function advanceSibling() {
        var kind = shell.sibling % 4
        var host = shell.columnHost ? column : look
        if (kind < 2) {
            if (shell.columnHost) {
                if (column.textLoading || column.linesItem.readFailed) return
                var lines = shell.find(column, "PreviewLines")
                if (!lines || lines.lines.length !== 14) return
                if (!shell.check(lines.numbered === (kind === 1), "code gutter changed")) return
            } else {
                var text = shell.find(look, "PreviewText")
                if (!text || text.status !== "ready") return
                var f = shell.flick(text)
                if (!shell.check(text.bodyItem.width === f.width && f.contentHeight > f.height,
                    "text/code overflow is absent")) return
                if (!shell.scrolling) {
                    if (!shell.check(f.contentY === shell.scrollTop, "text/code scroll did not start at the top")) return
                    shell.wheelDown(f)
                    return
                }
                if (f.moving) return
                if (!shell.check(f.contentY > shell.scrollTop, "text/code did not scroll")) return
                if (!shell.check(f.contentY <= f.contentHeight - f.height, "text/code scrolled past its content bounds")) return
                shell.scrolling = false
            }
        } else if (kind === 2) {
            var pdf = shell.find(host, "PreviewPdf")
            if (!pdf || pdf.shownPage < 0 || pdf.failed) return
            var pf = pdf.viewport
            if (!shell.check(pf !== null, "PDF viewport is absent")) return
            if (shell.columnHost) column.pdfZoom = 2
            else shell.find(look, "PdfViewer").zoom = 2
            if (!shell.check(pf.contentHeight === pf.height * 2 && pf.contentWidth === pf.width * 2,
                "PDF zoom extent changed")) return
            pf.contentY = pf.contentHeight - pf.height
        } else {
            if (shell.columnHost) {
                if (!column.pictureItem || column.pictureItem.status !== Image.Ready) return
            } else {
                var picture = shell.find(look, "PreviewImage")
                if (!picture || picture.status !== "image") return
            }
        }
        shell.cases++
        shell.log("CASE " + shell.cases + " " + (shell.columnHost ? "column" : "quicklook")
            + " " + ["text", "code", "pdf", "image"][kind] + " settled")
        shell.nextSibling()
    }

    Timer {
        interval: 100
        running: !shell.done
        repeat: true
        onTriggered: {
            if (shell.wheeling) return
            shell.ticks++
            // Keep this reader loaded across its first toggle; clearing it first primes Qt's lazy getter on empty text.
            if (!shell.preludeDone) {
                if (shell.ticks < 6 || !firstToggle.contentReady) return
                if (!shell.toggled) {
                    firstToggle.view = "source"
                    shell.toggled = true
                    shell.ticks = 0
                    return
                }
                shell.cell("first-loaded-source-toggle", firstToggle)
                if (shell.done) return
                shell.preludeDone = true
                shell.ticks = 0
                return
            }
            if (shell.scenario < 0) {
                if (!Flea.Theme.ready) return
                if (!shell.check(String(Flea.Theme.color.background) === Quickshell.env("FLEA_LAYOUT_BACKGROUND"), "theme did not load")) return
                shell.begin()
                return
            }
            if (shell.ticks < 3) return
            if (shell.sibling < 0) shell.advanceMarkdown()
            else shell.advanceSibling()
        }
    }
    Timer { interval: 60000; running: !shell.done; onTriggered: shell.fail("watchdog expired at scenario=" + shell.scenario + " stage=" + shell.stage + " sibling=" + shell.sibling) }
}
