//@ pragma ShellId flea-markdown-blockcost-test

import QtQuick
import Quickshell
import "flea" as Flea

// Time the model assignment that builds a document's blocks and count the objects each block kind builds, over the real preview.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_BLOCKCOST " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    // Sample input: "/work/docs/a.md|/work/docs/b.md", the documents in the order they are measured.
    property var docs: Quickshell.env("FLEA_BLOCKCOST_LIST").split("|").filter(function (d) { return d.length > 0 })
    property int next: 0
    property int loadsSeen: 0
    property var times: []
    property bool timed: false
    property bool done: false
    readonly property int sampleRuns: 5
    // The census treats these parts as another kind's, so a text block that builds one has built more than its own.
    readonly property var foreignParts: ["Repeater", "Column", "Row", "Rectangle", "Image", "MarkdownFigure", "TextMetrics", "Glyph"]

    FloatingWindow {
        id: window
        implicitWidth: 900
        implicitHeight: 600
        color: "#101315"

        Flea.PreviewMarkdown {
            id: md
            anchors.fill: parent
            active: true
            size: 1
            view: "rendered"
        }
    }

    // Every object a built block holds, children and resources alike, by type name.
    function census(start) {
        var seen = [], counts = {}
        function walk(object) {
            if (!object || seen.indexOf(object) >= 0) return
            seen.push(object)
            // Sample input: "QQuickColumn(0x1234)" becomes "Column", "MarkdownText_QMLTYPE_42(0x1234)" becomes "MarkdownText".
            var type = String(object).split("(")[0].replace(/_QML(TYPE)?_\d+/g, "").replace(/^QQuick/, "")
            counts[type] = (counts[type] || 0) + 1
            var groups = [object.children, object.data, object.resources]
            for (var g = 0; g < groups.length; g++) {
                var group = groups[g]
                if (!group) continue
                for (var i = 0; i < group.length; i++) walk(group[i])
            }
            if (object.item) walk(object.item)
        }
        walk(start)
        return { total: seen.length, counts: counts }
    }

    // Sample input: a run block whose mathsText still waits on one of its formulas answers true.
    function formulasWaiting() {
        function waiting(object) {
            if (object.objectName === "mathsText" && object.unsettled !== 0) return true
            for (var i = 0; i < object.children.length; i++)
                if (waiting(object.children[i])) return true
            return false
        }
        for (var i = 0; i < md.blockList.length; i++) {
            var item = md.blockItem(i)
            if (item && waiting(item)) return true
        }
        return false
    }

    // The distinct formulas of a block that hold a picture, so a census of the drawn state can tell it from the failed one.
    function drawnFormulas(item) {
        var drawn = 0
        function walk(object) {
            if (object.objectName === "mathsText")
                drawn += object.formulas.filter(function (tex) { return object.svgs[tex] }).length
            for (var i = 0; i < object.children.length; i++) walk(object.children[i])
        }
        walk(item)
        return drawn
    }

    function median(values) {
        var sorted = values.slice().sort(function (a, b) { return a - b })
        return sorted[Math.floor(sorted.length / 2)]
    }

    // The reassignments rebuild every delegate, so each formula asks again; the census reads them after they answer.
    function timeBuilds() {
        var blocks = md.blockList
        shell.times = []
        for (var run = 0; run < shell.sampleRuns; run++) {
            md.blockList = []
            var started = Date.now()
            md.blockList = blocks
            shell.times.push(Date.now() - started)
        }
        shell.timed = true
    }

    function measure() {
        var blocks = md.blockList
        var times = shell.times
        // Each kind reports its largest block, the bound a count gate holds, with the foreign parts that block built.
        var kinds = {}, total = 0, built = 0
        for (var i = 0; i < blocks.length; i++) {
            var item = md.blockItem(i)
            if (!item) continue
            var c = shell.census(item)
            built++
            total += c.total
            // A run with inline formulas builds its own component, so it is counted as its own kind.
            var kind = blocks[i].type === "run" && blocks[i].maths !== undefined ? "maths" : blocks[i].type
            var foreign = shell.foreignParts.filter(function (part) { return c.counts[part] > 0 }).join("+")
            if (!kinds[kind] || kinds[kind].objects < c.total)
                kinds[kind] = { objects: c.total, foreign: foreign || "none", counts: c.counts, drawn: shell.drawnFormulas(item) }
        }
        shell.log("doc=" + shell.docs[shell.next].split("/").pop() + " blocks=" + blocks.length + " built=" + built
            + " objects=" + total + " ms=" + times.join(",") + " median=" + shell.median(times))
        for (var k in kinds)
            shell.log("kind=" + k + " objects=" + kinds[k].objects + " foreign=" + kinds[k].foreign
                + " drawn=" + kinds[k].drawn + " parts=" + JSON.stringify(kinds[k].counts))
    }

    // One document per turn: the model is swapped by path, and a landed load of that file is what lets the next one start.
    function advance() {
        if (shell.next >= shell.docs.length) {
            shell.done = true
            shell.log("DONE " + shell.docs.length + " documents")
            shell.quit()
            return
        }
        shell.loadsSeen = md.loadRuns
        shell.timed = false
        md.path = shell.docs[shell.next]
    }

    Connections {
        target: md
        function onContentReadyChanged() { if (md.contentReady) Qt.callLater(shell.landed) }
    }

    // A formula's drawn state builds its pictures, so the census waits until every formula has answered.
    function landed() {
        if (shell.done || !md.contentReady || md.loadRuns === shell.loadsSeen) return
        if (!shell.timed) shell.timeBuilds()
        if (shell.formulasWaiting()) return
        shell.measure()
        shell.next++
        shell.advance()
    }

    Component.onCompleted: {
        if (shell.docs.length === 0) shell.fail("no documents arrived in FLEA_BLOCKCOST_LIST")
        else shell.advance()
    }

    readonly property int settlePollMs: 100
    readonly property int watchdogMs: 50000
    Timer {
        interval: shell.watchdogMs
        repeat: false
        running: !shell.done
        onTriggered: shell.fail("watchdog waiting for a document")
    }

    Timer {
        interval: shell.settlePollMs
        repeat: true
        running: !shell.done
        onTriggered: shell.landed()
    }

    function fail(why) {
        if (shell.done) return
        shell.done = true
        shell.log("FAIL " + why)
        shell.quit()
    }
}
