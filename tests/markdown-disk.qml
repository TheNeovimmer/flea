import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// The shown Markdown file's place and failures across saves: a read that fails, a save that truncates first, a shorter file, a file past the worker threshold, a file switched mid-save.
ShellRoot {
    id: root
    property string scenario: Quickshell.env("FLEA_PREVIEW_HUNT_CASE")
    property string fixture: Quickshell.env("FLEA_PREVIEW_HUNT_DIR") + "/" + scenario + ".md"
    property string otherFixture: Quickshell.env("FLEA_PREVIEW_HUNT_DIR") + "/" + scenario + "-b.md"
    property int loadsAtSwitch: 0
    property int stage: 0
    property int settle: 0
    property double stamp: Date.now()
    property int failures: 0
    property int checks: 0
    property bool editDone: false
    property string fullText: ""
    property string partialText: ""
    // The furthest the list has rested past the end of its content since the edit, sampled on every contentY and contentHeight change.
    property real overshoot: 0
    // The worker phase: counters read before the edit, the watcher events one save raised, and whether the parse was still pending a turn after it was asked.
    property int loadsBefore: 0
    property int parseRunsBefore: 0
    property int saveEvents: 0
    property bool parsingAfterAsk: false
    property int waited: 0
    property real scrolledY: 0
    property real scrolledColumnY: 0
    readonly property bool failCase: scenario === "disk-fail"
    readonly property int tickMs: 20
    readonly property int probeGiveUpMs: 8000
    // A place deep inside a 300 paragraph file, well past the first screen.
    readonly property int scrollTargetY: 1200
    // The file must be this many viewports tall before a place inside it means anything.
    readonly property int tallScreens: 3
    // Ticks of the probe timer a finished save stays quiet for before the place is read; counted, never timed.
    readonly property int settleTicks: 15
    // Ticks the probe waits for one event to land before it fails that event by name; counted, never timed.
    readonly property int landPollLimit: 300
    // The worker phase's save truncates, waits this long, then writes: two watcher events, as the kernel merges two that arrive unread together.
    readonly property int saveGapMs: 10
    // A shortened document that still fills the viewport yet ends far above scrollTargetY.
    readonly property int shortParagraphs: 40
    readonly property string unlinkScript: "import os, sys; os.unlink(sys.argv[1])"
    readonly property string truncateScript: "import sys; open(sys.argv[1], 'w').close()"
    readonly property string writeScript: "from pathlib import Path; import sys; Path(sys.argv[1]).write_text(sys.argv[2])"
    readonly property string shortScript: "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('\\n\\n'.join('short paragraph %d.' % i for i in range(int(sys.argv[2]))) + '\\n')"
    readonly property string splitSaveScript: "from pathlib import Path; import sys, time; p = Path(sys.argv[1]); t = p.read_text().replace('scroll paragraph 0.', 'edited paragraph 0.'); f = open(p, 'w'); f.flush(); time.sleep(" + root.saveGapMs / 1000 + "); f.write(t); f.close()"
    readonly property string replaceScript: "from pathlib import Path; import sys; p = Path(sys.argv[1]); p.write_text(p.read_text().replace('scroll paragraph 0.', 'edited paragraph 0.'))"

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
    // Quick Look wraps the preview in a pane; the PreviewMarkdown itself is the node that holds a block list and counts its loads.
    function quickMarkdown() {
        return root.descendants(quick).filter(function (node) {
            return node.blockList !== undefined && node.loadRuns !== undefined
        })[0] || null
    }
    function edit(script, arg) {
        root.editDone = false
        editor.command = ["python3", "-c", script, root.fixture].concat(arg === undefined ? [] : [arg])
        editor.running = true
    }
    // The text of the 300 paragraph file with its first paragraph changed.
    function editedOf(text) {
        return text.replace("scroll paragraph 0.", "edited paragraph 0.")
    }
    // The lowest contentY a list can rest at, and the highest: its content never ends above its view.
    function lowest(list) { return list.originY - list.topMargin }
    function highest(list) {
        return Math.max(root.lowest(list), list.originY + list.contentHeight - list.height + list.bottomMargin)
    }

    FloatingWindow {
        implicitWidth: 760
        implicitHeight: 700
        color: Flea.Theme.color.background
        Flea.PreviewMarkdown {
            id: md
            width: 600
            height: 580
            active: !root.failCase
            path: root.fixture
            size: 2000
        }
        Flea.Preview {
            id: quick
            active: root.failCase
            kind: "text"
            path: root.fixture
            size: 100
        }
        Flea.PreviewColumn {
            id: column
            width: 300
            height: 600
            visible: root.failCase
            row: ({ n: "disk-fail.md", d: false, t: false, s: 100, i: "text-x-generic" })
            meta: ({})
            path: root.fixture
            kindName: "Markdown document"
        }
    }
    // One sampler for both: a content that shrinks under an unchanged contentY is seen as well as a view that moves.
    function sampleList() {
        var list = md.bodyItem
        if (root.stage < 1 || list.contentHeight <= 0)
            return
        root.overshoot = Math.max(root.overshoot, list.contentY - root.highest(list))
    }
    Connections {
        target: md.bodyItem
        function onContentYChanged() { root.sampleList() }
        function onContentHeightChanged() { root.sampleList() }
    }
    // The shown file's watcher events and the preview's reloads, counted where they happen.
    Connections {
        id: watcher
        target: null
        function onFileChanged() { root.saveEvents++ }
    }
    Connections {
        target: md
        // A synchronous parse is over before the next turn, a worker's reply is not.
        function onParseRunsChanged() {
            if (root.stage === 1)
                Qt.callLater(function () { root.parsingAfterAsk = md.parsing })
        }
    }
    // The file switches in the turn the save's event starts the coalescing window, so the reload is still pending.
    Connections {
        id: switchWatch
        target: null
        function onRunningChanged() {
            if (root.stage !== 1 || !switchWatch.target.running) return
            root.loadsAtSwitch = md.loadRuns
            md.path = root.otherFixture
            root.check("the pending reload dies with the old file", switchWatch.target.running, false)
            root.stage = 2
        }
    }
    Process {
        id: editor
        onExited: function (exitCode, exitStatus) {
            root.check("fixture edit completed", exitCode, 0)
            root.editDone = true
        }
    }
    // Counted ticks, not a duration: the reparse lands and the list lays out over a few turns.
    function quiet() { return ++root.settle > root.settleTicks }
    // True once an event has landed; a count of polls that never sees it fails the event by name.
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
    // The preview's FileView, found among its non-visual children by the watcher it carries.
    function fileView() {
        var parts = md.resources
        for (var i = 0; i < parts.length; i++)
            if (parts[i].watchChanges === true && parts[i].loaded !== undefined) return parts[i]
        return null
    }
    function tall(item) { return item && item.contentReady && item.flickContentHeight > item.height * root.tallScreens }

    // Quick Look and the column each read the removed file as a failure, then the recreated one as text with the place kept.
    function failStep() {
        var q = root.quickMarkdown()
        var c = column.markdown
        if (root.stage === 0 && root.tall(q) && root.tall(c)) {
            q.bodyItem.contentY = root.scrollTargetY
            c.bodyItem.contentY = root.scrollTargetY
            root.scrolledY = q.bodyItem.contentY
            root.scrolledColumnY = c.bodyItem.contentY
            root.fullText = c.rawText
            root.edit(root.unlinkScript)
            root.stage = 1
            return
        }
        if (root.stage === 1 && root.editDone && q.readFailed && c.readFailed) {
            root.check("Quick Look reports the removed file as unreadable", q.status, "This file could not be read.")
            root.check("column reports the removed file as unreadable", c.status, "This file could not be read.")
            root.edit(root.writeScript, root.editedOf(root.fullText))
            root.stage = 2
            return
        }
        if (root.stage === 2 && root.editDone && c.rawText.indexOf("edited paragraph 0.") === 0
                && q.rawText.indexOf("edited paragraph 0.") === 0) {
            root.stage = 3
            root.settle = 0
            return
        }
        if (root.stage === 3 && root.quiet()) {
            root.check("Quick Look shows the recreated file", q.rawText, root.editedOf(root.fullText))
            root.check("column shows the recreated file", c.rawText, root.editedOf(root.fullText))
            root.check("Quick Look clears the failure once the file is back", [q.readFailed, q.status], [false, "ready"])
            root.check("column clears the failure once the file is back", [c.readFailed, c.status], [false, "ready"])
            root.check("Quick Look keeps the place across the failed read", q.bodyItem.contentY, root.scrolledY)
            root.check("column keeps the place across the failed read", c.bodyItem.contentY, root.scrolledColumnY)
            root.finish()
        }
    }

    // A save that truncates, then writes in pieces, the watcher reading the empty file and the half-written one: the place survives both.
    function partialStep() {
        if (root.stage === 0 && root.tall(md)) {
            md.bodyItem.contentY = root.scrollTargetY
            root.scrolledY = md.bodyItem.contentY
            root.check("scrolled into the document", root.scrolledY, root.scrollTargetY)
            root.fullText = md.rawText
            root.partialText = md.rawText.split("\n\n").slice(0, root.shortParagraphs).join("\n\n") + "\n"
            root.edit(root.truncateScript)
            root.stage = 1
            return
        }
        // Each reload is the watcher event under test, so wait for it to land.
        if (root.stage === 1 && root.editDone && md.rawText === "" && md.contentReady) {
            root.check("the watcher read the truncated file", md.rawText, "")
            root.edit(root.writeScript, root.partialText)
            root.stage = 2
            return
        }
        if (root.stage === 2 && root.editDone && md.rawText === root.partialText && md.contentReady) {
            root.stage = 3
            root.settle = 0
            return
        }
        // The half-written model is shorter than the place; let it lay out before the rest of the save arrives.
        if (root.stage === 3 && root.quiet()) {
            root.check("the half-written file ends above the saved place", md.flickContentHeight < root.scrolledY + md.height, true)
            root.edit(root.writeScript, root.editedOf(root.fullText))
            root.stage = 4
            return
        }
        if (root.stage === 4 && root.editDone && md.rawText === root.editedOf(root.fullText) && md.contentReady) {
            root.stage = 5
            root.settle = 0
            return
        }
        if (root.stage === 5 && root.quiet()) {
            root.check("the full text is drawn", md.rawText === root.editedOf(root.fullText), true)
            root.check("a save written in pieces keeps the place", md.bodyItem.contentY, root.scrolledY)
            root.finish()
        }
    }

    // An edit that leaves the document far shorter than the saved place: the view ends inside the content.
    function shrinkStep() {
        if (root.stage === 0 && root.tall(md)) {
            md.bodyItem.contentY = root.scrollTargetY
            root.scrolledY = md.bodyItem.contentY
            root.check("scrolled into the document", root.scrolledY, root.scrollTargetY)
            root.edit(root.shortScript, String(root.shortParagraphs))
            root.stage = 1
            return
        }
        if (root.stage === 1 && root.editDone && md.rawText.indexOf("short paragraph 0.") === 0 && md.contentReady) {
            root.stage = 2
            root.settle = 0
            return
        }
        if (root.stage === 2 && root.quiet()) {
            var list = md.bodyItem
            root.check("the shortened document still fills the view", md.flickContentHeight > md.height, true)
            root.check("the saved place lies past the shortened content", root.scrolledY > root.highest(list), true)
            root.check("the view rests inside the shortened content", list.contentY >= root.lowest(list)
                && list.contentY <= root.highest(list), true)
            root.check("the view never rested past the end on the way", root.overshoot <= 0, true)
            root.finish()
        }
    }

    // The same place-keeping edit on a file past workerThreshold, so the worker parse lands the model.
    function workerStep() {
        if (root.stage === 0 && root.tall(md)) {
            root.check("the file is past the worker threshold", md.rawText.length > md.workerThreshold, true)
            md.bodyItem.contentY = root.scrollTargetY
            root.scrolledY = md.bodyItem.contentY
            root.check("scrolled into the document", root.scrolledY, root.scrollTargetY)
            watcher.target = root.fileView()
            root.check("the file view is found", watcher.target !== null, true)
            root.loadsBefore = md.loadRuns
            root.parseRunsBefore = md.parseRuns
            root.saveEvents = 0
            root.parsingAfterAsk = false
            root.edit(root.splitSaveScript)
            root.stage = 1
            return
        }
        // The edit's own parse: asked once, still pending a turn after it was asked, and landed with the list in step.
        if (root.stage === 1 && root.editDone && root.landedWithin("the edit's parse", md.parseRuns > root.parseRunsBefore
                && md.rawText.indexOf("edited paragraph 0.") === 0 && md.contentReady)) {
            root.stage = 2
            root.settle = 0
            return
        }
        if (root.stage === 2 && root.quiet()) {
            root.check("the edit asked one parse", md.parseRuns - root.parseRunsBefore, 1)
            root.check("the edit's parse landed", [md.parsing, md.appliedSeq === md.parseSeq], [false, true])
            root.check("the worker landed the edit, not a synchronous parse", root.parsingAfterAsk, true)
            root.check("the worker parsed the edit", md.parsedOffThread, true)
            // The save is a truncate and a write, and each raises its own watcher event: both land in one load.
            console.log("PREVIEW_HUNT INFO the save raised " + root.saveEvents + " watcher events")
            root.check("the save raised more than one watcher event", root.saveEvents > 1, true)
            root.check("one save is one load", md.loadRuns - root.loadsBefore, 1)
            root.check("edited text is drawn", md.rawText.indexOf("edited paragraph 0.") === 0, true)
            root.check("a worker parse keeps the scroll position", md.bodyItem.contentY, root.scrolledY)
            root.finish()
        }
    }

    // The preview's own coalescing timer, found among its non-visual children by its named interval.
    function coalesceTimer() {
        var parts = md.resources
        for (var i = 0; i < parts.length; i++)
            if (parts[i].interval === md.reloadCoalesceMs && parts[i].repeat === false) return parts[i]
        return null
    }
    // A file switched inside a save's coalescing window: the new file loads once and opens at its top.
    function switchStep() {
        if (root.stage === 0 && root.tall(md)) {
            switchWatch.target = root.coalesceTimer()
            root.check("the coalescing timer is found", switchWatch.target !== null, true)
            md.bodyItem.contentY = root.scrollTargetY
            root.edit(root.replaceScript)
            root.stage = 1
            return
        }
        if (root.stage === 2 && md.rawText.indexOf("other paragraph 0.") === 0 && md.contentReady) {
            root.stage = 3
            root.settle = 0
            return
        }
        if (root.stage === 3 && root.quiet()) {
            root.check("the new file loads once", md.loadRuns - root.loadsAtSwitch, 1)
            root.check("the new file opens at its top", md.bodyItem.contentY, root.lowest(md.bodyItem))
            root.finish()
        }
    }

    Timer {
        interval: root.tickMs
        running: true
        repeat: true
        onTriggered: {
            if (Date.now() - root.stamp > root.probeGiveUpMs) {
                root.check("probe completes", "timeout stage " + root.stage, "complete")
                root.finish()
                return
            }
            if (root.scenario === "disk-fail") root.failStep()
            else if (root.scenario === "disk-partial") root.partialStep()
            else if (root.scenario === "disk-shrink") root.shrinkStep()
            else if (root.scenario === "disk-switch") root.switchStep()
            else root.workerStep()
        }
    }
}
