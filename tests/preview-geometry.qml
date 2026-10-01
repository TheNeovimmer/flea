//@ pragma ShellId flea-preview-geometry-test

import QtQuick
import Quickshell
import "flea" as Flea

// Headless preview geometry gate: every preview surface, kind and source-size class against one
// rule table (AGENTS.md "The preview swap"). Images draw at min(own size, aspect-fit), never
// enlarged; video posters fill the frame like the player; office thumbnails fill it only when the
// embedded picture reaches cache size; a PDF page contains. tests/preview-geometry.sh drives it.
ShellRoot {
    id: root

    readonly property string dir: Quickshell.env("FLEA_PREVIEW_GEOMETRY_DIR")
    readonly property string out: Quickshell.env("FLEA_PREVIEW_GEOMETRY_OUT")
    property var failures: []
    property int index: 0
    property int waited: 0
    property int saved: 0
    property bool showing: false

    function fail(what) { root.failures.push("cell " + root.index + ": " + what) }
    function near(a, b) { return Math.abs(a - b) <= 1 }

    // surf: C wide column, N narrow column, W wide Quick Look image, S narrow one.
    // leg: orig (the file itself), cache (a 256 px thumbnail of an original), doc (a PDF page).
    property var cases: [
        { surf: "C", kind: "image", src: "64x48", decW: 64, decH: 48, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "C", kind: "image", src: "120x68", decW: 120, decH: 68, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "N", kind: "image", src: "64x48", decW: 64, decH: 48, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "N", kind: "image", src: "120x68", decW: 120, decH: 68, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "C", kind: "image", src: "1920x1080", decW: 256, decH: 144, leg: "cache", rule: "image-cache-cap", limit: 1920 / 256, metaW: 1920, metaH: 1080 },
        { surf: "C", kind: "image", src: "1080x1920", decW: 144, decH: 256, leg: "cache", rule: "image-cache-cap", limit: 1080 / 144, metaW: 1080, metaH: 1920 },
        { surf: "C", kind: "image", src: "6000x4000", decW: 256, decH: 171, leg: "cache", rule: "image-cache-cap", limit: 6000 / 256, metaW: 6000, metaH: 4000 },
        { surf: "N", kind: "image", src: "1920x1080", decW: 256, decH: 144, leg: "cache", rule: "image-cache-cap", limit: 1920 / 256, metaW: 1920, metaH: 1080 },
        { surf: "N", kind: "image", src: "1080x1920", decW: 144, decH: 256, leg: "cache", rule: "image-cache-cap", limit: 1080 / 144, metaW: 1080, metaH: 1920 },
        { surf: "N", kind: "image", src: "6000x4000", decW: 256, decH: 171, leg: "cache", rule: "image-cache-cap", limit: 6000 / 256, metaW: 6000, metaH: 4000 },
        { surf: "C", kind: "video", src: "64x64", decW: 256, decH: 256, leg: "cache", rule: "video-poster-fill", limit: Infinity, metaW: 64, metaH: 64 },
        { surf: "C", kind: "video", src: "320x240", decW: 256, decH: 192, leg: "cache", rule: "video-poster-fill", limit: Infinity, metaW: 320, metaH: 240 },
        { surf: "C", kind: "video", src: "1920x1080", decW: 256, decH: 144, leg: "cache", rule: "video-poster-fill", limit: Infinity, metaW: 1920, metaH: 1080 },
        { surf: "C", kind: "video", src: "1080x1920", decW: 144, decH: 256, leg: "cache", rule: "video-poster-fill", limit: Infinity, metaW: 1080, metaH: 1920 },
        { surf: "N", kind: "video", src: "64x64", decW: 256, decH: 256, leg: "cache", rule: "video-poster-fill", limit: Infinity, metaW: 64, metaH: 64 },
        { surf: "N", kind: "video", src: "320x240", decW: 256, decH: 192, leg: "cache", rule: "video-poster-fill", limit: Infinity, metaW: 320, metaH: 240 },
        { surf: "N", kind: "video", src: "1920x1080", decW: 256, decH: 144, leg: "cache", rule: "video-poster-fill", limit: Infinity, metaW: 1920, metaH: 1080 },
        { surf: "N", kind: "video", src: "1080x1920", decW: 144, decH: 256, leg: "cache", rule: "video-poster-fill", limit: Infinity, metaW: 1080, metaH: 1920 },
        { surf: "C", kind: "office", src: "120x68", decW: 120, decH: 68, leg: "cache", rule: "office-own-size", limit: 1 },
        { surf: "C", kind: "office", src: "181x256", decW: 181, decH: 256, leg: "cache", rule: "office-fill", limit: Infinity },
        { surf: "N", kind: "office", src: "120x68", decW: 120, decH: 68, leg: "cache", rule: "office-own-size", limit: 1 },
        { surf: "N", kind: "office", src: "181x256", decW: 181, decH: 256, leg: "cache", rule: "office-fill", limit: Infinity },
        { surf: "C", kind: "pdf", src: "400x560", leg: "doc", rule: "pdf-contain" },
        { surf: "C", kind: "pdf", src: "560x400", leg: "doc", rule: "pdf-contain" },
        { surf: "N", kind: "pdf", src: "400x560", leg: "doc", rule: "pdf-contain" },
        { surf: "N", kind: "pdf", src: "560x400", leg: "doc", rule: "pdf-contain" },
        { surf: "W", kind: "image", src: "64x48", decW: 64, decH: 48, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "W", kind: "image", src: "120x68", decW: 120, decH: 68, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "W", kind: "image", src: "1920x1080", decW: 1920, decH: 1080, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "W", kind: "image", src: "1080x1920", decW: 1080, decH: 1920, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "W", kind: "image", src: "6000x4000", decW: 6000, decH: 4000, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "S", kind: "image", src: "64x48", decW: 64, decH: 48, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "S", kind: "image", src: "120x68", decW: 120, decH: 68, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "S", kind: "image", src: "1920x1080", decW: 1920, decH: 1080, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "S", kind: "image", src: "1080x1920", decW: 1080, decH: 1920, leg: "orig", rule: "image-own-size", limit: 1 },
        { surf: "S", kind: "image", src: "6000x4000", decW: 6000, decH: 4000, leg: "orig", rule: "image-own-size", limit: 1 }
    ]

    FloatingWindow {
        implicitWidth: 1300
        implicitHeight: 1560
        color: "black"

        Flea.PreviewColumn {
            id: colWide
            x: 10
            y: 10
            width: 760
            height: 860
        }
        Flea.PreviewColumn {
            id: colNarrow
            x: 780
            y: 10
            width: 380
            height: 860
        }
        Item {
            id: qlWide
            x: 10
            y: 880
            width: 800
            height: 600
            Flea.PreviewImage {
                id: qlWideImage
                anchors.fill: parent
            }
        }
        Item {
            id: qlNarrow
            x: 820
            y: 880
            width: 400
            height: 300
            Flea.PreviewImage {
                id: qlNarrowImage
                anchors.fill: parent
            }
        }
    }

    function columnFor(c) { return c.surf === "N" ? colNarrow : colWide }
    function qlFor(c) { return c.surf === "S" ? qlNarrowImage : qlWideImage }
    function qlBox(c) { return c.surf === "S" ? qlNarrow : qlWide }

    // The row and the backend-shaped extras each cell stands in for. A clear phase runs first:
    // a new source reports Loading synchronously, but a PDF settle keeps the old page for 120 ms,
    // so a check taken at once would measure the previous cell as this one.
    function clear(c) {
        if (c.surf === "W" || c.surf === "S") {
            qlFor(c).path = ""
            return
        }
        var column = root.columnFor(c)
        column.row = null
        column.thumb = ""
        column.meta = null
        column.path = ""
        column.noThumbComing = false
    }
    function begin(c) {
        if (c.surf === "W" || c.surf === "S") {
            qlFor(c).path = root.dir + "/img-" + c.src + ".png"
            return
        }
        var column = root.columnFor(c)
        var row = null
        var kindName = ""
        var extra = {}
        if (c.kind === "image" && c.leg === "orig") {
            row = { n: "img.png", d: false, s: 1, m: 1, p: 33188, i: "image-png", t: false, k: 0 }
            kindName = "PNG image"
            extra = { path: root.dir + "/img-" + c.src + ".png", noThumbComing: true }
        } else if (c.kind === "image") {
            row = { n: "img.jpg", d: false, s: 1, m: 1, p: 33188, i: "image-jpeg", t: true, k: 0 }
            kindName = "JPEG image"
            extra = { thumb: root.dir + "/thumb-" + c.decW + "x" + c.decH + ".png",
                      path: root.dir + "/img-" + c.src + ".jpg",
                      meta: { w: c.metaW, h: c.metaH } }
        } else if (c.kind === "video") {
            row = { n: "clip.mp4", d: false, s: 1, m: 1, p: 33188, i: "video-x-generic", t: true, k: 0 }
            kindName = "MPEG-4 video"
            extra = { thumb: root.dir + "/thumb-" + c.decW + "x" + c.decH + ".png",
                      path: root.dir + "/clip.mp4",
                      meta: { w: c.metaW, h: c.metaH, durationMs: 1000 } }
        } else if (c.kind === "office") {
            row = { n: "report.odt", d: false, s: 1, m: 1, p: 33188, i: "x-office-document", t: true, k: 0 }
            kindName = "ODT document"
            extra = { thumb: root.dir + "/office-" + c.decW + "x" + c.decH + ".png",
                      path: root.dir + "/report.odt", meta: {} }
        } else {
            row = { n: "doc.pdf", d: false, s: 1, m: 1, p: 33188, i: "x-office-document", t: false, k: 0 }
            kindName = "PDF document"
            extra = { path: root.dir + "/doc-" + c.src + ".pdf", meta: {} }
        }
        column.noThumbComing = extra.noThumbComing === true
        column.thumb = extra.thumb || ""
        column.row = row
        column.kindName = kindName
        column.meta = extra.meta !== undefined ? extra.meta : {}
        column.path = extra.path
    }

    function ready(c) {
        if (c.surf === "W" || c.surf === "S")
            return qlFor(c).status === "image"
        var column = root.columnFor(c)
        if (c.leg === "doc")
            return column.pdfDrawn && column.pdfPages > 0
        return column.frameStatus === Image.Ready
    }

    // The rule table as arithmetic: the aspect-fit of the box, capped by the kind's limit.
    function checkBox(c, boxW, boxH, drawnW, drawnH, x, y, frameW, frameH) {
        var fit = Math.min(c.limit, boxW / c.decW, boxH / c.decH)
        var wantW = c.decW * fit
        var wantH = c.decH * fit
        var wantX = Math.round((frameW - wantW) / 2)
        var wantY = Math.round((frameH - wantH) / 2)
        if (!root.near(drawnW, wantW) || !root.near(drawnH, wantH))
            return "drawn " + drawnW.toFixed(1) + "x" + drawnH.toFixed(1) + ", rule wants " + wantW.toFixed(1) + "x" + wantH.toFixed(1)
        if (!root.near(x, wantX) || !root.near(y, wantY))
            return "not centred at " + x.toFixed(1) + "," + y.toFixed(1) + ", rule wants " + wantX + "," + wantY
        return ""
    }

    function check(c) {
        if (c.leg === "doc") {
            var column = root.columnFor(c)
            var page = column.pdfPageItem()
            if (!page) return "no page item to measure"
            var box = page.parent
            var fillsW = root.near(page.width, box.width)
            var fillsH = root.near(page.height, box.height)
            if (!fillsW && !fillsH)
                return "page " + page.width.toFixed(1) + "x" + page.height.toFixed(1) + " fills neither side of " + box.width.toFixed(1) + "x" + box.height.toFixed(1)
            if (page.width > box.width + 1 || page.height > box.height + 1)
                return "page overflows its box"
            if (!root.near(page.x, (box.width - page.width) / 2) || !root.near(page.y, (box.height - page.height) / 2))
                return "page not centred"
            return ""
        }
        var boxW = 0
        var boxH = 0
        var frameW = 0
        var frameH = 0
        var item = null
        if (c.surf === "W" || c.surf === "S") {
            var ql = qlFor(c)
            var qbox = root.qlBox(c)
            item = ql.pictureItem
            boxW = qbox.width
            boxH = qbox.height
            frameW = qbox.width
            frameH = qbox.height
            if (item.implicitWidth < 1) return "picture never decoded"
        } else {
            var col = root.columnFor(c)
            item = col.pictureItem
            boxW = item.boxWidth
            boxH = item.boxHeight
            frameW = col.frameItem.width
            frameH = col.frameItem.height
            if (!root.near(item.implicitWidth, c.decW) || !root.near(item.implicitHeight, c.decH))
                return "decoded " + item.implicitWidth + "x" + item.implicitHeight + ", fixture is " + c.decW + "x" + c.decH
        }
        return root.checkBox(c, boxW, boxH, item.width, item.height, item.x, item.y, frameW, frameH)
    }

    function grabTarget(c) {
        if (c.surf === "W" || c.surf === "S") return root.qlBox(c)
        return root.columnFor(c).frameItem
    }

    // The drawn size each cell line carries, read off the same item the check measured.
    function drawnOf(c) {
        if (c.leg === "doc") {
            var page = root.columnFor(c).pdfPageItem()
            return page ? [page.width, page.height] : [0, 0]
        }
        var item = (c.surf === "W" || c.surf === "S") ? root.qlFor(c).pictureItem : root.columnFor(c).pictureItem
        return [item.width, item.height]
    }

    function report(c, problem, drawnW, drawnH) {
        var box = c.surf === "W" || c.surf === "S"
            ? root.qlBox(c).width + "x" + root.qlBox(c).height
            : Math.round(root.columnFor(c).frameItem.width) + "x" + Math.round(root.columnFor(c).frameItem.height)
        var drawn = Math.round(drawnW) + "x" + Math.round(drawnH)
        var status = problem === "" ? "ok" : "FAIL " + problem
        console.log("GEOMETRY " + (c.surf === "C" ? "columns-wide" : c.surf === "N" ? "columns-narrow" : c.surf === "W" ? "quicklook-wide" : "quicklook-narrow")
            + " " + c.kind + " " + c.src + " frame=" + box + " drawn=" + drawn + " rule=" + c.rule + " " + status)
        if (problem !== "") root.fail(problem + " [" + c.surf + " " + c.kind + " " + c.src + "]")
    }

    Timer {
        id: tick
        interval: 25
        repeat: true
        onTriggered: {
            if (root.index >= root.cases.length) {
                if (root.saved === root.cases.length) root.finish()
                return
            }
            if (++root.waited > 400) { root.fail("timed out"); root.finish(); return }
            var c = root.cases[root.index]
            if (!root.showing) {
                root.clear(c)
                root.showing = true
                root.waited = 0
                return
            }
            if (root.waited === 1) {
                root.begin(c)
                return
            }
            if (!root.ready(c)) return
            var problem = root.check(c)
            var drawn = root.drawnOf(c)
            root.report(c, problem, drawn[0], drawn[1])
            var name = "geometry-" + root.index + "-" + c.surf + "-" + c.kind + "-" + c.src + ".png"
            root.grabTarget(c).grabToImage(function (result) {
                result.saveToFile(root.out + "/" + name)
                root.saved++
            })
            root.index++
            root.showing = false
            root.waited = 0
        }
    }

    function finish() {
        tick.stop()
        for (var f = 0; f < root.failures.length; f++)
            console.log("GEOMETRY FAIL " + root.failures[f])
        console.log("GEOMETRY DONE cells=" + root.cases.length + " saved=" + root.saved + " fail=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Component.onCompleted: tick.start()
}
