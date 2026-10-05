//@ pragma ShellId flea-markdown-draw-test

import QtQuick
import Quickshell
import "flea" as Flea
import "markdown-draw.js" as Draw

// The real PreviewMarkdown over the nesting and inline-maths fixtures: pinned geometry of quote bars and list columns, and the ink of drawn formulas.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_DRAW " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property string dir: Quickshell.env("FLEA_DRAW_DIR")
    // Nesting twice and maths twice: the second visit is served from the figure cache, so only the failed formula asks again.
    readonly property var plan: ["nesting", "maths", "nesting", "maths", "far"]
    readonly property var groundRgb: [16, 19, 21]
    readonly property int bodySize: 14
    readonly property int nestingBlocks: 7
    readonly property int quoteFirst: 3
    readonly property var listMarkers: [["•", "◦", "▪", "•", "◦"]]
    readonly property var listDepths: [0, 1, 2, 0, 1]
    property int step: -1
    property bool armed: false
    property bool done: false
    property bool grabbing: false
    property int checks: 0
    property int failures: 0
    property int loadsMark: 0
    property int sendsMark: 0
    property int farState: 0
    property string shotPath: Quickshell.env("XDG_RUNTIME_DIR") + "/markdown-draw-" + Quickshell.processId + ".png"
    Component.onCompleted: Flea.ViewState.setTextSize({ mode: shell.bodySize })

    function check(error, name) {
        shell.checks++
        if (error !== "")
            shell.failures++
        shell.log((error === "" ? "CHECK " : "FAIL ") + name + (error === "" ? "" : ": " + error))
    }
    function finish(why) {
        if (shell.done)
            return
        shell.done = true
        shell.log(why !== undefined ? "FAIL " + why : shell.checks + " checks, " + shell.failures + " failed")
        shell.quit()
    }

    FloatingWindow {
        implicitWidth: 560
        implicitHeight: 900
        color: "#101315"

        Item {
            id: grabRoot
            anchors.fill: parent
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(shell.groundRgb[0] / 255, shell.groundRgb[1] / 255, shell.groundRgb[2] / 255, 1)
            }
            Flea.PreviewMarkdown {
                id: md
                anchors.fill: parent
                active: true
                size: 1
                view: "rendered"
            }
        }
        Image {
            id: shot
            width: 1
            height: 1
            opacity: 0
            onStatusChanged: if (status === Image.Ready && shell.grabbing) probe.requestPaint()
        }
        Canvas {
            id: probe
            width: 560
            height: 900
            opacity: 0
            onPaint: if (shot.status === Image.Ready && shell.grabbing) shell.pixels(getContext("2d"))
        }
    }

    function start(at) {
        shell.step = at
        shell.loadsMark = md.loadRuns
        shell.sendsMark = Flea.FigureService.sends
        shell.farState = 0
        md.path = shell.dir + "/" + shell.plan[at] + ".md"
    }

    // Every block has a delegate, and every inline formula in the document has answered or failed.
    function settled() {
        for (var i = 0; i < md.blockList.length; i++) {
            var delegate = md.blockItem(i)
            if (delegate === null)
                return false
            var maths = Draw.child(delegate, "mathsText")
            if (maths !== null && maths.unsettled !== 0)
                return false
        }
        return true
    }

    function nestingChecks() {
        var types = md.blockList.map(function (b) { return b.type }).join(",")
        shell.check(types === "heading,list,list,quote,quote,quote,run" ? "" : types, "nesting fixture block types")
        // Each depth's marker column starts at its parent's text column, with the marker by depth.
        var column = Draw.drawn(md, 1, "listColumn")
        var entries = column === null ? [] : Draw.rows(column)
        shell.check(entries.length === 5 ? "" : entries.length + " rows, want 5", "nested list builds its five entries")
        if (entries.length === 5) {
            var text = entries.map(function (e) { return e.marker.text }).join(" ")
            shell.check(text === shell.listMarkers[0].join(" ") ? "" : text, "markers by depth: disc, circle, square")
            var want = [0, 0, 0, 0, 0]
            for (var k = 1; k < 5; k++) {
                var depth = shell.listDepths[k]
                var parent = k - 1
                while (shell.listDepths[parent] !== depth - 1 && parent > 0)
                    parent--
                want[k] = depth === 0 ? 0 : Draw.textColumn(entries[parent])
            }
            var wrong = ""
            for (var j = 0; j < 5; j++)
                if (!Draw.near(entries[j].row.x, want[j], 0.5))
                    wrong += " entry " + j + " marker at x " + entries[j].row.x + " want " + want[j] + ";"
            shell.check(wrong, "a nested marker starts at its parent's text column")
            var step = 0
            for (var s = 0; s < 4; s++)
                step += Math.abs(entries[s + 1].row.y - (entries[s].row.y + entries[s].row.height)) > 0.5 ? 1 : 0
            shell.check(step === 0 ? "" : step + " tight entries are not flush", "tight list has no gap between entries")
        }
        var loose = Draw.drawn(md, 2, "listColumn")
        var pair = loose === null ? [] : Draw.rows(loose)
        if (pair.length === 2) {
            var gap = (pair[1].row.y + pair[1].text.y) - (pair[0].row.y + pair[0].text.y + pair[0].text.height)
            shell.check(Draw.near(gap, md.blockGap, 0.5) ? "" : "gap " + gap + ", want " + md.blockGap, "loose list has the paragraph gap")
        } else {
            shell.check(pair.length + " rows, want 2", "loose list builds its two entries")
        }
        // A depth-3 quote shows three bars, the outer ones running the full height of the inner block, joined blocks flush.
        var rows = []
        for (var q = 0; q < 3; q++) {
            var row = Draw.drawn(md, shell.quoteFirst + q, "quoteRow")
            rows.push(row)
            shell.check(row === null ? "no quote row" : Draw.quoteBarsError(row, q + 1, 2 + row.spacing), "quote depth " + (q + 1) + " bars")
        }
        if (rows[0] !== null && rows[1] !== null && rows[2] !== null) {
            for (var f = 0; f < 2; f++) {
                var above = Draw.rectOf(md, rows[f]), below = Draw.rectOf(md, rows[f + 1])
                shell.check(Draw.near(below.y, above.y + above.h, 0.5) ? "" : "block starts at " + below.y + ", predecessor ends at " + (above.y + above.h),
                    "joined quote " + (f + 2) + " sits flush under its predecessor")
            }
        }
        var maths = Draw.drawn(md, 6, "mathsText")
        shell.check(maths !== null && maths.text.indexOf("<img") >= 0 && maths.text.indexOf("&#94;") < 0 ? "" : "the line still shows its TeX span",
            "inline formula in the nesting fixture is drawn")
    }

    function mathsChecks() {
        var types = md.blockList.map(function (b) { return b.type }).join(",")
        shell.check(types === "heading,run,heading,run,heading,run,heading,run" ? "" : types, "maths fixture block types")
        var bad = Draw.drawn(md, 5, "mathsText")
        shell.check(bad !== null && bad.text.indexOf("<code data-math=\"inline\"") >= 0 && bad.text.indexOf("<img") < 0 ? "" : "the failed formula lost its code span",
            "a failing formula stays as its code span")
        var twice = Draw.drawn(md, 7, "mathsText")
        shell.check(twice !== null && twice.formulas.length === 1 && twice.text.split("<img").length === 3 ? "" : "a repeated formula asked or drew twice",
            "a repeated formula asks once and draws twice")
    }

    function grab() {
        shell.grabbing = true
        grabRoot.grabToImage(function (result) {
            shell.check(result.saveToFile(shell.shotPath) ? "" : "grab could not be saved", "maths grab")
            shot.source = "file://" + shell.shotPath
        })
    }

    function lineRect(index) {
        var item = Draw.drawn(md, index, "mathsText")
        var at = item.mapToItem(grabRoot, 0, 0)
        return { x: Math.floor(at.x), y: Math.floor(at.y), w: Math.floor(item.width), h: Math.floor(item.height) }
    }

    function pixels(ctx) {
        shell.grabbing = false
        ctx.drawImage(shot, 0, 0)
        var data = ctx.getImageData(0, 0, 560, 900).data
        var first = lineRect(1), second = lineRect(3)
        var groups = Draw.inkGroups(data, 560, first, shell.groundRgb)
        shell.check(Draw.levelError(groups, first), "inline x stands on the prose baseline at the prose x-height")
        var baseline = groups.length > 0 ? groups[0].bottom - first.y : 0
        var depth = Draw.inkGroups(data, 560, second, shell.groundRgb)
        shell.check(Draw.depthError(depth, second.y + baseline, md.bodyPx), "inline y has its own depth below the baseline")
        shell.next()
    }

    function next() {
        if (shell.step + 1 >= shell.plan.length)
            return shell.finish()
        shell.start(shell.step + 1)
    }

    function drive() {
        if (shell.step < 0)
            return shell.start(0)
        if (!md.contentReady || md.loadRuns === shell.loadsMark || shell.grabbing)
            return
        var name = shell.plan[shell.step]
        if (name === "far")
            return shell.farStep()
        if (!shell.settled())
            return
        var sends = Flea.FigureService.sends - shell.sendsMark
        if (name === "nesting") {
            shell.nestingChecks()
            shell.check(sends === (shell.step === 0 ? 1 : 0) ? "" : sends + " requests", "nesting visit " + shell.step + " asked only for what the cache lacked")
            shell.next()
        } else {
            shell.mathsChecks()
            // x, y, the failing formula and a once: four asks cold, and on a revisit the cache serves all but the one that never succeeded.
            shell.check(sends === (shell.step === 1 ? 4 : 1) ? "" : sends + " requests", "maths visit " + shell.step + " asked only for what the cache lacked")
            if (shell.step === 1)
                shell.grab()
            else
                shell.next()
        }
    }

    // A formula below the cache asks for nothing until the list brings it into view.
    function farStep() {
        var last = md.blockList.length - 1
        if (shell.farState === 0) {
            if (md.blockItem(0) === null)
                return
            shell.check(md.blockItem(last) === null && Flea.FigureService.sends === shell.sendsMark ? "" : "the formula below the cache was built or asked for",
                "a formula past the cache is not asked for")
            md.bodyItem.positionViewAtEnd()
            shell.farState = 1
        } else if (shell.farState === 1) {
            var item = md.blockItem(last)
            if (item === null || Draw.child(item, "mathsText") === null || Draw.child(item, "mathsText").unsettled !== 0)
                return
            var delta = Flea.FigureService.sends - shell.sendsMark
            shell.check(delta === 1 && Draw.child(item, "mathsText").text.indexOf("<img") >= 0 ? "" : delta + " requests", "a formula scrolled into view asks once and draws")
            shell.next()
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: !shell.done
        onTriggered: shell.drive()
    }

    readonly property int watchdogMs: 60000
    Timer {
        interval: shell.watchdogMs
        repeat: false
        running: !shell.done
        onTriggered: shell.finish("watchdog at step " + shell.step + " (" + shell.plan[Math.max(0, shell.step)] + ")")
    }
}
