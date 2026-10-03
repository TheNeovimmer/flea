//@ pragma ShellId flea-preview-layout-loop-test

import QtQuick
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
    property int sibling: -1
    property bool done: false
    property bool toggled: false
    property bool preludeDone: false
    property string expectedPath: ""
    readonly property bool columnHost: scenario < 4
    readonly property string view: scenario % 2 === 0 ? "rendered" : "source"

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
    function markdown() { return shell.find(shell.columnHost ? column : look, "PreviewMarkdown") }
    function flick(item) { return shell.find(item, "Flickable") }
    function extent(md) {
        if (md.view !== "source") return md.bodyItem.height
        var children = shell.flick(md).contentItem.children
        for (var i = 0; i < children.length; i++)
            if (String(children[i]).indexOf("QQuickText") === 0 && children[i].text === md.rawText)
                return children[i].height
        shell.fail("source text is absent")
        return 0
    }

    FloatingWindow {
        implicitWidth: 1400
        implicitHeight: 920
        color: Flea.Theme.color.background
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
        if (shell.scenario === 8) {
            shell.nextSibling()
            return
        }
        look.close()
        column.row = null
        column.width = shell.scenario < 2 ? 380 : 760
        lookHost.width = shell.scenario < 6 ? 500 : 1000
        lookHost.height = shell.scenario < 6 ? 400 : 800
        Flea.ViewState.changeLeaf("preview", { markdownView: shell.view })
        shell.low = 1
        shell.high = 96
        shell.below = 0
        shell.above = 0
        shell.stage = 0
        shell.showCount(48)
    }
    function cell(label, md) {
        var f = shell.flick(md)
        var h = shell.extent(md)
        if (!shell.check(md.width === f.width && md.height === f.height, "reader left its viewport")) return
        if (!shell.check(md.bodyItem.width === f.width, "rendered text width changed")) return
        if (!shell.check(Math.abs(f.contentHeight - Math.max(f.height, h)) < 0.1, "content height is stale")) return
        var bar = shell.find(f, "ViewportScrollBar")
        if (!shell.check(bar && bar.parent === f && bar.width === Flea.Theme.spacing.rowPaddingX,
            "scroll lane changed its fixed overlay geometry")) return
        if (!shell.check(bar.overflow === (h - f.height > 0.5), "overflow disagrees with laid-out content")) return
        shell.cases++
        shell.log("CASE " + shell.cases + " " + (shell.columnHost ? "column" : "quicklook")
            + " " + md.view + " " + label + " frame=" + md.width + "x" + md.height + " content=" + h)
    }
    function advanceMarkdown() {
        var md = shell.markdown()
        if (!md || !md.contentReady || md.path !== shell.expectedPath) {
            if (shell.ticks === 10) shell.log("WAIT markdown=" + md + " ready=" + (md ? md.contentReady : false)
                + " path=" + (md ? md.path : "") + " column=" + column.previewState)
            return
        }
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
        } else if (shell.stage === 2) {
            if (!shell.check(h > md.height && h - shell.belowHeight < 40, "tall document missed overflow edge")) return
            shell.cell("tall", md)
            var f = shell.flick(md)
            f.contentY = f.contentHeight - f.height
            if (!shell.check(f.contentY > 0, "overflow could not scroll")) return
            shell.stage = 3
            shell.show("mixed.md", "text-plain")
        } else {
            if (!shell.check(md.blockList.some(function(b) { return b.type === "table" })
                && md.blockList.some(function(b) { return b.type === "image" }), "mixed blocks never arrived")) return
            var imageBlock = md.blockList.findIndex(function(b) { return b.type === "image" })
            var image = shell.find(md.blockItem(imageBlock), "Image")
            if (!image || image.status !== Image.Ready) return
            shell.cell("image-table-fence", md)
            if (shell.done) return
            shell.begin()
        }
    }
    function nextSibling() {
        shell.sibling++
        shell.scenario = shell.sibling < 4 ? 0 : 4
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
                f.contentY = f.contentHeight - f.height
                if (!shell.check(f.contentY > 0, "text/code did not scroll")) return
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
