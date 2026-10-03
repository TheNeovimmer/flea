import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// One event, one parse: count the parses a shown Markdown file really runs for each event, in Quick Look and in the column.
ShellRoot {
    id: root
    property string scenario: Quickshell.env("FLEA_PREVIEW_HUNT_CASE")
    property string dir: Quickshell.env("FLEA_PREVIEW_HUNT_DIR")
    readonly property bool quickCase: scenario === "parse-quick"
    readonly property bool columnCase: scenario === "parse-column"
    readonly property bool workerCase: scenario === "parse-worker"
    property string shownName: workerCase ? "pc-big-a.md" : "pc-a.md"
    readonly property string shownPath: root.dir + "/" + root.shownName
    property int failures: 0
    property int checks: 0
    property int step: -1
    property int settle: 0
    property int countBefore: 0
    property double stamp: Date.now()
    property bool rewritten: false
    property string inkBefore: ""
    property string editScript: ""
    // Ticks of the probe timer a finished event stays quiet for before its parses are read; counted, never timed.
    readonly property int settleTicks: 15
    readonly property int tickMs: 20
    readonly property int probeGiveUpMs: 12000
    readonly property string plainScript: "from pathlib import Path; import sys; Path(sys.argv[1]).write_text(sys.argv[2])"
    // An editor's atomic save: write a sibling, then rename it over the shown file.
    readonly property string renameScript: "import os, sys; from pathlib import Path; t = sys.argv[1] + '.tmp'; Path(t).write_text(sys.argv[2]); os.replace(t, sys.argv[1])"

    function check(label, actual, expected) {
        checks++
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) failures++
        console.log("PREVIEW_HUNT " + (ok ? "PASS " : "FAIL ") + label
            + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    function finish() {
        console.log("PREVIEW_HUNT DONE " + checks + " checks, " + failures + " failed")
        Qt.exit(failures ? 1 : 0)
    }
    function descendants(item) {
        var out = [item]
        for (var i = 0; i < out.length; i++) {
            var kids = out[i].children || []
            for (var j = 0; j < kids.length; j++) out.push(kids[j])
        }
        return out
    }
    // The PreviewMarkdown itself: the only node that both holds a block list and counts its parses.
    function host() {
        var top = root.quickCase ? quick : root.columnCase ? column : md
        return root.descendants(top).filter(function (node) {
            return node.blockList !== undefined && node.parseRuns !== undefined
        })[0] || null
    }
    function edit(script, text) {
        root.rewritten = false
        editor.command = ["python3", "-c", script, root.shownPath, text]
        editor.running = true
    }

    // Each event: what to do, when it has landed, and the parses it may cost.
    readonly property var steps: [
        { name: "open one file", act: function () {}, landed: function (h) { return h.contentReady }, parses: 1 },
        { name: "second file, different text", act: function () { root.shownName = "pc-b.md" },
            landed: function (h) { return h.contentReady && h.rawText === "Beta text.\n" }, parses: 1 },
        { name: "third file, identical text", act: function () { root.shownName = "pc-c.md" },
            landed: function (h) { return h.contentReady && h.path === root.shownPath }, parses: 1 },
        { name: "disk edit of the shown file", act: function () { root.edit(root.plainScript, "After disk edit.\n") },
            landed: function (h) { return root.rewritten && h.contentReady && h.rawText === "After disk edit.\n" }, parses: 1 },
        { name: "rename-over save", act: function () { root.edit(root.renameScript, "After rename.\n") },
            landed: function (h) { return root.rewritten && h.contentReady && h.rawText === "After rename.\n" }, parses: 1 },
        { name: "save with identical text", act: function () { root.edit(root.plainScript, "After rename.\n") },
            landed: function (h) { return root.rewritten && h.contentReady }, parses: 0 },
        { name: "one theme switch", act: function () {
                root.inkBefore = root.host().inkHex
                Flea.Theme.applyColors('background = "#ffffff"\nforeground = "#202020"')
            }, landed: function (h) { return h.inkHex !== root.inkBefore && h.contentReady }, parses: 1 }
    ]

    // The worker path: a request that lands behind a newer one must not be shown.
    function workerStep() {
        var h = root.host()
        if (root.step === 0) {
            if (!h || !h.parsing) return
            // The first request is in flight on the worker; point the pane at the other big file.
            root.shownName = "pc-big-b.md"
            root.step = 1
            return
        }
        if (root.step === 1 && h.contentReady && h.path === root.shownPath) {
            root.check("the newer file is the one shown", h.blockList[0].items[0].indexOf("beta") === 0, true)
            root.check("the pane settled on the newest request", h.appliedSeq === h.parseSeq && !h.parsing, true)
            root.check("two files, two worker parses", h.parseRuns, 2)
            root.step = 2
            root.settle = 0
            return
        }
        if (root.step === 2 && ++root.settle > root.settleTicks) {
            root.check("the newer file stays shown after the old reply is due", h.blockList[0].items[0].indexOf("beta") === 0, true)
            root.finish()
        }
    }

    FloatingWindow {
        implicitWidth: 760
        implicitHeight: 700
        color: Flea.Theme.color.background
        Flea.PreviewMarkdown {
            id: md
            width: 600
            height: 580
            active: root.workerCase
            path: root.shownPath
            size: 200000
        }
        Flea.Preview {
            id: quick
            active: root.quickCase
            kind: "text"
            path: root.shownPath
            size: 100
        }
        Flea.PreviewColumn {
            id: column
            width: 300
            height: 600
            visible: root.columnCase
            row: ({ n: root.shownName, d: false, t: false, s: 100, i: "text-x-generic" })
            meta: ({})
            path: root.shownPath
            kindName: "Markdown document"
        }
    }
    Process {
        id: editor
        onExited: function (exitCode, exitStatus) {
            root.check("fixture rewrite completed", exitCode, 0)
            root.rewritten = true
        }
    }
    Timer {
        interval: root.tickMs
        running: true
        repeat: true
        onTriggered: {
            if (Date.now() - root.stamp > root.probeGiveUpMs) {
                root.check("probe completes", "timeout step " + root.step, "complete")
                root.finish()
                return
            }
            var h = root.host()
            if (root.workerCase) {
                if (root.step < 0) root.step = 0
                root.workerStep()
                return
            }
            if (!h) return
            if (root.step < 0) {
                root.step = 0
                root.settle = -1
                root.countBefore = 0
            }
            var s = root.steps[root.step]
            if (root.settle < 0) {
                // Started: wait for the event to land, then let it go quiet.
                if (s.landed(h)) root.settle = 0
                return
            }
            if (++root.settle <= root.settleTicks) return
            var ran = h.parseRuns - root.countBefore
            console.log("PREVIEW_HUNT PARSES " + root.scenario + " | " + s.name + " | " + ran)
            root.check(s.name + " parses " + s.parses + " time(s)", ran, s.parses)
            root.check(s.name + " leaves the blocks applied", h.blocksReady, true)
            // A skipped reload must not leave a remembered scroll to be restored over a later, unrelated parse.
            root.check(s.name + " leaves no scroll waiting for a model", h.keepScroll, false)
            root.step++
            if (root.step >= root.steps.length) {
                root.finish()
                return
            }
            root.countBefore = h.parseRuns
            root.settle = -1
            root.steps[root.step].act()
        }
    }
}
