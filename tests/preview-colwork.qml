//@ pragma ShellId flea-preview-colwork

import QtQuick
import Quickshell
import "flea" as Flea

// Count gate for the column preview's per-move work: one decode request per idle
// move at the target size, never the departing row's cache file again. The real
// ColumnsArea, SelectionPreview, PreviewColumn, PreviewSwap and Preview over a
// stub pane and 8 real files; 7 idle column steps, Quick Look per kind, then the
// JPEG to PNG follow. Exact counts, never wall-clock time.
ShellRoot {
    id: root

    readonly property string dir: Quickshell.env("CW_DIR")
    readonly property string cache: Quickshell.env("CW_CACHE")
    readonly property int gapMs: parseInt(Quickshell.env("CW_GAP") || "1800")

    property var c: ({ meta: 0, thumb: 0, loads: 0, ready: 0, qlShow: 0 })
    property var loadLog: []
    property int passed: 0
    property int failed: 0

    function bump(k, n) { var x = root.c; x[k] = (x[k] || 0) + (n === undefined ? 1 : n); root.c = x }
    function snap() { return JSON.parse(JSON.stringify(root.c)) }
    function deltaObj(a, b) {
        var out = {}
        for (var k in b) out[k] = b[k] - (a[k] || 0)
        return out
    }
    function log(line) { console.log("COLWORK " + line) }
    function check(name, got, want) {
        if (got === want) { root.passed += 1; root.log("PASS " + name + " got=" + got) }
        else { root.failed += 1; root.log("FAIL " + name + " got=" + got + " want=" + want) }
    }
    function touch(name) { Quickshell.execDetached(["touch", root.dir + "/.mark-" + name]) }

    QtObject {
        id: backend
        signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
        signal metaResult(var message)
        signal meta(int row, int w, int h, int orient, real durationMs, int sampleRate, int entries, real unpacked,
            bool archiveFailed, var names, real lines, bool partial, bool linesFailed, string target, bool targetDir, string owner)
        property int dirDev: 0
        property int seq: 0
        property var pending: []
        function peek(path, size, hidden) {}
        function askMeta(index, wantLines, wantMedia, wantArchive) {
            root.bump("meta")
            seq += 1
            pending.push({ token: seq, index: index })
            metaReply.restart()
            return seq
        }
        function thumb(rows, cacheOnly) { root.bump("thumb", rows ? rows.length : 0) }
        function thumbcancel(rows) {}
        function dirsize(rows) {}
        function dirsizecancel() {}
        function window(start, count) {}
    }

    // Local disk answers meta in a few milliseconds.
    Timer {
        id: metaReply
        interval: 3
        onTriggered: {
            var p = backend.pending
            backend.pending = []
            for (var i = 0; i < p.length; i++) {
                var r = root.rowsList[p[i].index]
                backend.metaResult({ token: p[i].token, w: r.w || 0, h: r.h || 0, ms: r.ms || 0, rate: 0, entries: 0,
                    unpacked: 0, afailed: false, names: [], lines: r.lines || 0, partial: false, lfailed: false,
                    target: "", targetdir: "", owner: "", orient: 1 })
            }
        }
    }

    readonly property var rowsList: [
        { n: "00-start.txt", d: false, k: 0, p: 33188, s: 4096, m: 1758835200, t: false, i: "text-x-generic", lines: 80 },
        { n: "10-photo.jpg", d: false, k: 1, p: 33188, s: 900000, m: 1758835201, t: true, i: "image-x-generic", w: 2400, h: 1600 },
        { n: "20-large.png", d: false, k: 2, p: 33188, s: 5000000, m: 1758835202, t: true, i: "image-x-generic", w: 3000, h: 2000 },
        { n: "30-clip.mp4", d: false, k: 3, p: 33188, s: 300000, m: 1758835203, t: true, i: "video-x-generic", w: 640, h: 360, ms: 3000 },
        { n: "40-notes.txt", d: false, k: 0, p: 33188, s: 4096, m: 1758835204, t: false, i: "text-x-generic", lines: 80 },
        { n: "50-manual.pdf", d: false, k: 4, p: 33188, s: 200000, m: 1758835205, t: true, i: "x-office-document" },
        { n: "60-photo.heic", d: false, k: 5, p: 33188, s: 900000, m: 1758835206, t: true, i: "image-x-generic", w: 2400, h: 1600 },
        { n: "70-code.rs", d: false, k: 6, p: 33188, s: 20000, m: 1758835207, t: false, i: "text-x-generic", lines: 600 }
    ]

    QtObject {
        id: pane
        property string path: root.dir
        property var rows: root.rowsList
        property int cursorIndex: 0
        property bool showHidden: false
        property int windowSize: 35
        property bool listInFlight: false
        property string listingState: "ready"
        property string searchMode: ""
        property var thumbState: ({ file: { 1: root.cache + "/t1.png", 2: root.cache + "/t2.png", 3: root.cache + "/t3.png",
                                            5: root.cache + "/t5.png", 6: root.cache + "/t6.png" }, order: [1, 2, 3, 5, 6] })
        property var dirSizeState: ({ file: {}, order: [] })
        property var kindNames: ["Plain text", "JPEG image", "PNG image", "MPEG-4 video", "PDF document", "HEIF image", "Rust source"]
        property bool storageKnown: true
        property string storageClass: "local"
        property int firstSettleMs: 70
        property int settleMs: 120
        property int coalesceMs: 16
        property int refetchMargin: 25
        property int buffer: 150
        property int total: 8
        property int held: 0
        property var shown: null
        property int shownTotal: 8
        property int renamingIndex: -1
        property int selectionVersion: 0
        property var clipboard: null
        property var trash: ({ opened: false })
        property var preview: quick
        property var listArea: ({ forceActiveFocus: function () {} })
        readonly property int previewIndex: area.previewIndex
        property var backend: backend
        function join(base, name) { return String(base) + "/" + String(name) }
        function rowFor(index) { return (index >= 0 && index < rows.length) ? rows[index] : null }
        function isSelected(index) { return selectionVersion < 0 }
        function selectedIndices() { return [cursorIndex] }
        function selectionCount() { return 1 }
        function thumbFor(index) { var v = thumbState.file[index]; return typeof v === "string" ? v : "" }
        function open(path) {}
        function openFile(path) {}
        function focusRequested() {}
    }

    QtObject { id: menu; function close() {} function openBackground(point) {} }

    FloatingWindow {
        id: win
        implicitWidth: 1200
        implicitHeight: 700
        color: Flea.Theme.color.background

        Flea.ColumnsArea {
            id: area
            anchors.fill: parent
            pane: pane
            menu: menu
        }

        Flea.Preview {
            id: quick
            pane: pane
            onPathChanged: if (path !== "") root.bump("qlShow")
        }
    }

    function frameImage() {
        var f = area.frameItem()
        var kids = f ? f.children : []
        for (var i = 0; i < kids.length; i++)
            if (kids[i].autoTransform !== undefined && kids[i].fillMode !== undefined && kids[i].sourceSize !== undefined) return kids[i]
        return null
    }

    property var img: null
    Connections {
        target: root.img
        function onStatusChanged() {
            if (root.img.status === Image.Loading) {
                root.bump("loads")
                var s = String(root.img.source)
                root.loadLog.push(s.substring(s.lastIndexOf("/") + 1) + "@" + root.img.sourceSize.width + "x" + root.img.sourceSize.height)
            } else if (root.img.status === Image.Ready) root.bump("ready")
        }
    }

    property var plan: []
    property int planAt: 0
    property var before: null
    property string label: ""

    function move(r) {
        pane.cursorIndex = r
        if (area.visible) { area.activeColumn().showCursor(r); area.restartCoalesce() }
        pane.selectionVersion += 1
    }
    function rowPath(r) { return pane.join(pane.path, root.rowsList[r].n) }
    function qlOpen(r) { var w = root.rowsList[r]; quick.open(root.rowPath(r), w.i, w.s, pane.kindNames[w.k]) }
    function qlFollow(r) { root.move(r); var w = root.rowsList[r]; quick.follow(root.rowPath(r), w.i, w.s, pane.kindNames[w.k]) }

    // One decode request per idle move: 1 meta ask always, 1 frame load on a row
    // with a picture, none on text or code. A Quick Look open or follow shows once.
    function judged(d) {
        var m = /^col([1-7])$/.exec(root.label)
        if (m) {
            var r = parseInt(m[1], 10)
            var want = (r === 4 || r === 7) ? 0 : 1
            root.check(root.label + " meta", d.meta || 0, 1)
            root.check(root.label + " loads", d.loads || 0, want)
            root.check(root.label + " ready", d.ready || 0, want)
            return
        }
        if (root.label.indexOf("qlopen") === 0 || root.label === "qlfollow2")
            root.check(root.label + " show", d.qlShow || 0, 1)
    }

    Timer {
        id: stepper
        repeat: false
        onTriggered: root.next()
    }

    function next() {
        if (root.before !== null) root.judged(root.deltaObj(root.before, root.snap()))
        if (root.planAt >= root.plan.length) { root.finish(); return }
        var p = root.plan[root.planAt]
        root.planAt += 1
        root.before = root.snap()
        root.label = p.label
        if (p.mark) root.touch(p.mark)
        if (p.row !== undefined) root.move(p.row)
        if (p.act) p.act()
        stepper.interval = p.wait
        stepper.start()
    }

    function finish() {
        root.touch("done")
        root.log("QMLTALLY passed=" + root.passed + " failed=" + root.failed)
        quitTimer.start()
    }

    Timer { id: quitTimer; interval: 4000; onTriggered: Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    Timer {
        id: boot
        interval: 2000
        onTriggered: {
            root.img = root.frameImage()
            if (!root.img) { root.log("FAIL frame image not found"); root.failed += 1; root.finish(); return }
            var p = []
            p.push({ label: "settle0", wait: 500, mark: "leg" })
            for (var r = 1; r <= 7; r++) p.push({ label: "col" + r, row: r, wait: root.gapMs })
            // Quick Look over the hidden column: open per kind, then a follow from the JPEG onto the PNG.
            p.push({ label: "listview", wait: 1000, mark: "ql", act: function () { area.visible = false } })
            var kinds = [0, 1, 2, 4, 5, 6, 7]
            for (var q = 0; q < kinds.length; q++) {
                (function (r) {
                    p.push({ label: "listto" + r, row: r, wait: 800 })
                    p.push({ label: "qlopen" + r, wait: r === 2 ? 3000 : 1500, act: function () { root.qlOpen(r) } })
                    p.push({ label: "qlclose" + r, wait: 600, act: function () { quick.close() } })
                })(kinds[q])
            }
            p.push({ label: "listto1", row: 1, wait: 800, mark: "qlf" })
            p.push({ label: "qlopen1f", wait: 1500, act: function () { root.qlOpen(1) } })
            p.push({ label: "qlfollow2", wait: 3000, act: function () { root.qlFollow(2) } })
            p.push({ label: "qlclosef", wait: 600, act: function () { quick.close() } })
            root.plan = p
            root.next()
        }
    }

    Component.onCompleted: boot.start()
}
