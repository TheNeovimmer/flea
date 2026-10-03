import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// One event, one parse, in Quick Look and in the column; parse-fallback runs on tests/preview-hunt.sh's scratch ui (a silent worker, a parser that throws).
ShellRoot {
    id: root
    property string scenario: Quickshell.env("FLEA_PREVIEW_HUNT_CASE")
    property string dir: Quickshell.env("FLEA_PREVIEW_HUNT_DIR")
    readonly property bool quickCase: scenario === "parse-quick"
    readonly property bool columnCase: scenario === "parse-column"
    readonly property bool workerCase: scenario === "parse-worker"
    readonly property bool fallbackCase: scenario === "parse-fallback"
    property string shownName: workerCase ? "pc-big-a.md" : fallbackCase ? "pc-fb.md" : "pc-a.md"
    readonly property string shownPath: root.dir + "/" + root.shownName
    property int failures: 0
    property int checks: 0
    property int step: -1
    property int settle: 0
    property int countBefore: 0
    property double stamp: Date.now()
    property bool rewritten: false
    property string inkBefore: ""
    property int loadsBefore: 0
    property real placeBefore: 0
    // Ticks the probe waits for one event to land before it fails that event by name; counted, never timed.
    property int waited: 0
    // The worker phase: the first request's number, whether it was still unanswered at the switch, and every model and applied number seen.
    property int firstSeq: 0
    property bool switched: false
    property bool firstUnanswered: false
    property var appliedSeqs: []
    property var shownFirsts: []
    property int blocksShown: 0
    property real scrolledY: 0
    property string editScript: ""
    // Ticks of the probe timer a finished event stays quiet for before its parses are read; counted, never timed.
    readonly property int settleTicks: 15
    readonly property int tickMs: 20
    readonly property int probeGiveUpMs: 12000
    readonly property int landPollLimit: 300
    // A place deep inside the 1500 item fallback file, past the first screen, and the screens that make a file scroll.
    readonly property int scrollTargetY: 1200
    readonly property int scrollableScreens: 3
    readonly property string replaceScript: "from pathlib import Path; import sys; p = Path(sys.argv[1]); p.write_text(p.read_text().replace('fallback item 0 ', 'edited item 0 '))"
    readonly property string throwScript: "from pathlib import Path; import sys; p = Path(sys.argv[1]); p.write_text('FLEA-SCRATCH-THROW\\n' + p.read_text())"
    readonly property string sameScript: "from pathlib import Path; import sys; p = Path(sys.argv[1]); p.write_text(p.read_text())"
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
        editor.command = ["python3", "-c", script, root.shownPath].concat(text === undefined ? [] : [text])
        editor.running = true
    }
    // True once the event has landed; past landPollLimit ticks it fails by name and ends the run.
    function landedWithin(name, ready) {
        if (ready) {
            root.waited = 0
            return true
        }
        if (++root.waited > root.landPollLimit) {
            root.check(name + " lands within " + root.landPollLimit + " polls", "gave up", "landed")
            root.finish()
        }
        return false
    }

    // Each event: what to do, when it has landed, and the parses it may cost.
    readonly property var steps: [
        { name: "open one file", act: function () {}, landed: function (h) { return h.contentReady }, parses: 1 },
        { name: "second file, different text", act: function () { root.shownName = "pc-b.md" },
            landed: function (h) { return h.contentReady && h.rawText === "Beta text.\n" }, parses: 1 },
        { name: "third file, identical text", act: function () { root.shownName = "pc-c.md" },
            landed: function (h) { return h.contentReady && h.path === root.shownPath }, parses: 1 },
        { name: "disk edit of the shown file", act: function () { root.edit(root.plainScript, "After disk edit.\n") },
            landed: function (h) { return root.rewritten && h.loadRuns > root.loadsBefore && h.contentReady && h.rawText === "After disk edit.\n" },
            parses: 1, reads: true, keeps: true },
        { name: "rename-over save", act: function () { root.edit(root.renameScript, "After rename.\n") },
            landed: function (h) { return root.rewritten && h.loadRuns > root.loadsBefore && h.contentReady && h.rawText === "After rename.\n" },
            parses: 1, reads: true, keeps: true },
        { name: "save with identical text", act: function () { root.edit(root.plainScript, "After rename.\n") },
            landed: function (h) { return root.rewritten && h.loadRuns > root.loadsBefore && h.contentReady },
            parses: 0, reads: true, keeps: true },
        { name: "one theme switch", act: function () {
                root.inkBefore = root.host().inkHex
                Flea.Theme.applyColors('background = "#ffffff"\nforeground = "#202020"')
            }, landed: function (h) { return h.inkHex !== root.inkBefore && h.contentReady }, parses: 1, keeps: true }
    ]

    // Asked from the turn the first request is sent (parseRuns reaches one), so it is never sampled late.
    function switchAway() {
        if (root.switched) return
        root.firstSeq = md.parseSeq
        root.firstUnanswered = md.parsing && md.appliedSeq !== md.parseSeq
        root.switched = true
        root.shownName = "pc-big-b.md"
    }
    function isBeta(h) { return h.blockList.length > 0 && h.blockList[0].items[0].indexOf("beta") === 0 }

    // The worker path: a request that lands behind a newer one is dropped, never applied and never shown.
    function workerStep() {
        var h = root.host()
        if (root.step === 0) {
            if (!root.switched) return
            root.check("the first request was still unanswered at the switch", root.firstUnanswered, true)
            root.step = 1
            return
        }
        if (root.step === 1 && h.contentReady && h.path === root.shownPath) {
            root.check("the newer file is the one shown", root.isBeta(h), true)
            root.check("the pane settled on the newest request", h.appliedSeq === h.parseSeq && !h.parsing, true)
            root.check("two files, two worker parses", h.parseRuns, 2)
            root.step = 2
            root.settle = 0
            return
        }
        if (root.step === 2 && ++root.settle > root.settleTicks) {
            root.check("the newer file stays shown after the old reply is due", root.isBeta(h), true)
            root.check("the first request's number is never the applied one", root.appliedSeqs.indexOf(root.firstSeq), -1)
            root.check("the first file's blocks are never the model", root.shownFirsts.filter(function (t) { return t.indexOf("alpha") === 0 }), [])
            root.finish()
        }
    }

    // The fallback path on the scratch ui: the worker never answers, so the recovery parse is the only landing.
    function fallbackStep() {
        var h = root.host()
        var list = h.bodyItem
        if (root.step === 0) {
            if (!root.landedWithin("open: the recovery parse", h.contentReady)) return
            root.check("open: the recovery parse shows its blocks once", root.blocksShown, 1)
            root.check("open: one parse counted", h.parseRuns, 1)
            root.check("open: no worker reply landed", h.parsedOffThread, false)
            root.check("the fallback file scrolls", h.flickContentHeight > h.height * root.scrollableScreens, true)
            list.contentY = root.scrollTargetY
            root.scrolledY = list.contentY
            root.countBefore = h.parseRuns
            root.loadsBefore = h.loadRuns
            root.edit(root.replaceScript)
            root.step = 1
            return
        }
        if (root.step === 1) {
            if (!root.landedWithin("edit: the recovery parse", root.rewritten && h.loadRuns > root.loadsBefore
                    && h.rawText.indexOf("- edited item 0 ") === 0 && h.contentReady)) return
            root.settle = 0
            root.step = 2
            return
        }
        if (root.step === 2 && ++root.settle > root.settleTicks) {
            root.check("edit: one parse", h.parseRuns - root.countBefore, 1)
            root.check("edit: the recovery parse keeps the scroll position", list.contentY, root.scrolledY)
            root.check("edit: the recovery parse leaves no scroll waiting for a model", h.keepScroll, false)
            root.check("edit: no error", h.parseError, "")
            root.countBefore = h.parseRuns
            root.loadsBefore = h.loadRuns
            root.edit(root.throwScript)
            root.step = 3
            return
        }
        if (root.step === 3) {
            if (!root.landedWithin("throwing save: the failed recovery parse", root.rewritten && h.loadRuns > root.loadsBefore
                    && h.parseError !== "")) return
            root.settle = 0
            root.step = 4
            return
        }
        if (root.step === 4 && ++root.settle > root.settleTicks) {
            root.check("throwing save: one parse", h.parseRuns - root.countBefore, 1)
            root.check("throwing save: the pane shows the error", h.status, "This file could not be read.")
            root.countBefore = h.parseRuns
            root.loadsBefore = h.loadRuns
            root.edit(root.sameScript)
            root.step = 5
            return
        }
        if (root.step === 5) {
            if (!root.landedWithin("equal save: the second read", root.rewritten && h.loadRuns > root.loadsBefore)) return
            root.settle = 0
            root.step = 6
            return
        }
        if (root.step === 6 && ++root.settle > root.settleTicks) {
            root.check("equal save after a failed parse: the error is still shown", h.status, "This file could not be read.")
            root.check("equal save after a failed parse: the text is parsed again", h.parseRuns - root.countBefore, 1)
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
            active: root.workerCase || root.fallbackCase
            path: root.shownPath
            size: 200000
        }
        Connections {
            target: md
            // The turn the first worker request is asked, before any reply can be sampled.
            function onParseRunsChanged() {
                if (root.workerCase && md.parseRuns === 1) Qt.callLater(root.switchAway)
            }
            function onAppliedSeqChanged() { root.appliedSeqs.push(md.appliedSeq) }
            function onBlockListChanged() {
                if (md.blockList.length === 0) return
                root.blocksShown++
                var item = md.blockList[0].items
                root.shownFirsts.push(item ? item[0] : "")
            }
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
            if (root.workerCase || root.fallbackCase) {
                if (root.step < 0) root.step = 0
                if (root.workerCase) root.workerStep()
                else root.fallbackStep()
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
                if (root.landedWithin(s.name, s.landed(h))) root.settle = 0
                return
            }
            if (++root.settle <= root.settleTicks) return
            var ran = h.parseRuns - root.countBefore
            console.log("PREVIEW_HUNT PARSES " + root.scenario + " | " + s.name + " | " + ran)
            // A disk step must have read the file again, or a zero-parse result would also be true of a watcher that never fired.
            if (s.reads === true) root.check(s.name + " read the file again", h.loadRuns > root.loadsBefore, true)
            // A reader at rest stays at rest: the restore bounds come from the list's own margins.
            if (s.keeps === true) root.check(s.name + " keeps the place", h.bodyItem.contentY, root.placeBefore)
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
            root.loadsBefore = h.loadRuns
            root.placeBefore = h.bodyItem.contentY
            root.settle = -1
            root.steps[root.step].act()
        }
    }
}
