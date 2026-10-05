//@ pragma ShellId flea-fencehosts-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/MarkdownPrepared.js" as Prepared
import "fencehosts.js" as Fence

// Every fixture document through the preview column's host and Quick Look's two (prepared entry, then none); no host may draw a fence line, and all three draw the same blocks.
// Sample output: "FENCEHOSTS DOC tick-crlf col blocks=3 leaks=0 kinds=run,fence,run" is one host's reading of one document.
ShellRoot {
    id: root

    // Lines "name|bytes" of the fixture folder, in the order they are read.
    readonly property var docs: Quickshell.env("FENCEHOSTS_DOCS").split("\n").filter(function (l) { return l !== "" }).map(function (l) { var p = l.split("|"); return { name: p[0], size: Number(p[1]) } })
    readonly property string dir: Quickshell.env("FENCEHOSTS_DIR")
    readonly property var hosts: ["col", "prepared", "cold"]
    // A step that never settles is a harness fault; the largest document parses in a few seconds.
    readonly property int watchdogMs: 60000
    readonly property int listedFile: 33188
    // The fences the synthetic sized documents hold: one at the top, two past the head's cut and one at the end.
    readonly property int sizedFences: 4
    property int docIndex: 0
    property int hostIndex: 0
    property int failures: 0
    property var seen: ({})
    property bool finished: false
    // The entry reuses the shared host had counted when the step opened, so a reuse is told from an earlier document's.
    property int reusedBefore: 0

    function log(line) { console.log("FENCEHOSTS " + line) }
    function fail(why) { root.failures++; root.log("FAIL " + why) }
    function row(d) { return { n: d.name, d: false, s: d.size, p: root.listedFile, k: 0 } }
    function host() { return root.hosts[root.hostIndex] === "col" ? column : quick }

    // The stub for the window's pane: the members QuickLookPrepare reads, a listing of the document and a folder that is local.
    QtObject {
        id: pane
        property int cursorIndex: -1
        property var rows: []
        property bool listInFlight: false
        property string storageClass: ""
        property bool storageKnown: true
        property string path: root.dir
        function rowFor(i) { return pane.rows[i] || null }
        function join(a, b) { return a + "/" + b }
    }
    Flea.QuickLookPrepare {
        id: prepare
        pane: pane
        restMs: 1
        onPreparedPathChanged: if (prepare.preparedPath !== "") root.armed()
        onRestedChanged: if (prepare.rested) root.armed()
    }

    // The preview column's own set-up: compact, the surface code colour, no shared parse.
    Flea.PreviewMarkdown {
        id: column
        width: 560
        height: 600
        compact: true
        onContentReadyChanged: Qt.callLater(root.landed, column)
    }
    // Quick Look's: the window colour under code, the shared entry, and a first read that blocks for the named file.
    Flea.PreviewMarkdown {
        id: quick
        width: 560
        height: 600
        shareParse: true
        codeSurface: Flea.Theme.color.background
        onContentReadyChanged: Qt.callLater(root.landed, quick)
    }

    Timer {
        id: watchdog
        interval: root.watchdogMs
        onTriggered: { root.fail("step " + root.docs[root.docIndex].name + " " + root.hosts[root.hostIndex] + " never settled"); root.finish() }
    }

    // The entry Quick Look would hold at rest: prepared for the file's own text, or replaced by another file's for the cold read.
    function prime() {
        var d = root.docs[root.docIndex]
        var kind = root.hosts[root.hostIndex]
        if (kind === "col") return root.open()
        if (kind === "cold") {
            Prepared.store("/none", "x", "/", "", "", [])
            return root.open()
        }
        pane.rows = [root.row(d), root.row(d)]
        pane.cursorIndex = 1
        pane.cursorIndex = 0
    }
    // The prepared entry is in, or the file is past what a rest reads and the rest has settled with nothing.
    function armed() {
        if (root.finished || root.hosts[root.hostIndex] !== "prepared") return
        var d = root.docs[root.docIndex]
        if (prepare.preparedPath === root.dir + "/" + d.name || (prepare.rested && d.size > Prepared.MAX_BYTES)) root.open()
    }
    function open() {
        var d = root.docs[root.docIndex]
        var h = root.host()
        var path = root.dir + "/" + d.name
        root.reusedBefore = h.reusedParses
        h.active = false
        h.size = d.size
        if (h === quick) h.blockPath = path
        h.path = path
        h.active = true
        root.settleCheck(h)
    }
    function settleCheck(h) { if (h.contentReady) Qt.callLater(root.landed, h) }

    // A host whose document is fully parsed and drawn: its blocks are read once, a turn after the ready flag (the whole list lands just behind it), then the next step starts.
    function landed(h) {
        if (!h.contentReady || root.finished) return
        var d = root.docs[root.docIndex]
        var kind = root.hosts[root.hostIndex]
        if (h.path !== root.dir + "/" + d.name || root.seen[d.name + kind] === true) return
        root.seen[d.name + kind] = true
        var blocks = h.blockList
        var n = Fence.leaks(blocks)
        root.log("DOC " + d.name + " " + kind + " blocks=" + blocks.length + " leaks=" + n + " reused=" + (h.reusedParses - root.reusedBefore) + " kinds=" + Fence.kinds(blocks).slice(0, 80))
        if (n > 0) root.fail(d.name + " " + kind + " draws " + n + " fence line(s) as text")
        var key = Fence.neutral(blocks)
        if (root.seen[d.name] === undefined) root.seen[d.name] = key
        else if (root.seen[d.name] !== key) root.fail(d.name + " " + kind + " draws other blocks than the preview column")
        // A file's line endings never change what it draws: the same text in LF, CRLF and CR reads as the same kinds of block.
        var base = d.name.replace(/(-crlf|-cr)?\.md$/, "")
        var shape = Fence.kinds(blocks)
        if (root.seen["kinds " + base] === undefined) root.seen["kinds " + base] = shape
        else if (root.seen["kinds " + base] !== shape) root.fail(d.name + " " + kind + " draws kinds " + shape.slice(0, 60) + " where its other line endings draw " + root.seen["kinds " + base].slice(0, 60))
        if (d.name.indexOf("syn-size") === 0 && Fence.count(blocks, "fence") !== root.sizedFences) root.fail(d.name + " " + kind + " draws " + Fence.count(blocks, "fence") + " code blocks of the " + root.sizedFences + " it holds")
        if (kind === "prepared" && d.size <= Prepared.MAX_BYTES && h.reusedParses - root.reusedBefore < 1) root.fail(d.name + " prepared never took the entry, so it proved nothing")
        Qt.callLater(root.next)
    }
    function next() {
        root.hostIndex++
        if (root.hostIndex >= root.hosts.length) {
            root.hostIndex = 0
            root.docIndex++
        }
        if (root.docIndex >= root.docs.length) return root.finish()
        watchdog.restart()
        root.prime()
    }
    function finish() {
        if (root.finished) return
        root.finished = true
        watchdog.stop()
        root.log("DONE docs=" + root.docIndex + " expected=" + root.docs.length + " failures=" + root.failures)
        Qt.exit(root.failures ? 1 : 0)
    }
    Component.onCompleted: {
        if (root.docs.length === 0) { root.fail("no documents"); root.finish(); return }
        watchdog.restart()
        root.prime()
    }
}
