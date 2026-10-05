import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// The reader's place against the disk: a file written without pause, a reader who moves while a place is held, a list of blocks of uneven height.
ShellRoot {
    id: root
    property string scenario: Quickshell.env("FLEA_PREVIEW_HUNT_CASE")
    property string fixture: Quickshell.env("FLEA_PREVIEW_HUNT_DIR") + "/" + scenario + ".md"
    property int stage: 0
    property int settle: 0
    property int waited: 0
    property double stamp: Date.now()
    property int failures: 0
    property int checks: 0
    property bool editDone: false
    property string fullText: ""
    property real scrolledY: 0
    // The uneven phase: the block at the view's top and its offset before the edit.
    property var placeBefore: null
    // The stream phase: the writer's state, and the reloads that landed while it was still running.
    property bool writerDone: true
    property int reloadsWhileRunning: 0
    // The regrow phase: where the reader left the view.
    property real readerY: 0
    // The uneven phase: the document's real height, the height the list reported in the turn its model was replaced, and the smallest it reported after.
    property int loadsBefore: 0
    property real realHeight: 0
    // The walk's content height on the tick before: the walk ends once the view rests at the end and this stops growing.
    property real walkHeight: -1
    property real heightAtReset: 0
    property real smallestHeight: Infinity
    property bool measuring: false
    // Every contentY the list took after the model reset, kept as harness evidence for the INFO line.
    property var moves: []
    readonly property int tickMs: 20
    // The most contentY moves the INFO line lists.
    readonly property int moveLogLimit: 40
    readonly property int probeGiveUpMs: 12000
    // A place deep inside a 300 paragraph file, well past the first screen.
    readonly property int scrollTargetY: 1200
    // The file must be this many viewports tall before a place inside it means anything.
    readonly property int tallScreens: 3
    // Ticks of the probe timer a finished save stays quiet for before the place is read; counted, never timed.
    readonly property int settleTicks: 15
    // Ticks the probe waits for one event to land before it fails that event by name; counted, never timed.
    readonly property int landPollLimit: 300
    // The stream phase: a writer appends this many times, this many ms apart, so the run spans several coalescing windows.
    readonly property int streamWrites: 40
    readonly property int streamGapMs: 20
    // The burst spans 16 coalescing windows of 50 ms, so a window that reloads on its own start lands at least this many while the writer runs.
    readonly property int streamMinReloads: 3
    // A shortened document that still fills the viewport yet ends far above scrollTargetY.
    readonly property int shortParagraphs: 40
    // The regrow phase: how far the reader moves the view up from where a short file left it.
    readonly property int readerMovePx: 200
    // The uneven phase: the reader this share of the way down the document (the check wants past three quarters), and each walk step a share of a view.
    readonly property real unevenDepth: 0.8
    readonly property real unevenPastShare: 0.75
    readonly property real walkScreens: 0.9
    readonly property string writeScript: "from pathlib import Path; import sys; Path(sys.argv[1]).write_text(sys.argv[2])"
    readonly property string shortScript: "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('\\n\\n'.join('short paragraph %d.' % i for i in range(int(sys.argv[2]))) + '\\n')"
    readonly property string streamScript: "import sys, time; f = open(sys.argv[1], 'a'); [(f.write('\\n\\nstream %d.' % i), f.flush(), time.sleep(int(sys.argv[3]) / 1000)) for i in range(int(sys.argv[2]))]; f.close()"
    readonly property string unevenScript: "from pathlib import Path; import sys; p = Path(sys.argv[1]); p.write_text(p.read_text().replace('uneven paragraph 0.', 'edited paragraph 0.'))"

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
    function edit(script, arg) {
        root.editDone = false
        editor.command = ["python3", "-c", script, root.fixture].concat(arg === undefined ? [] : [arg])
        editor.running = true
    }
    // The lowest contentY a list can rest at, and the highest: its content never ends above its view.
    function lowest(list) { return list.originY - list.topMargin }
    function highest(list) {
        return Math.max(root.lowest(list), list.originY + list.contentHeight - list.height + list.bottomMargin)
    }
    // Counted ticks, not a duration: the reparse lands and the list lays out over a few turns.
    function quiet() { return ++root.settle > root.settleTicks }
    function tall(item) { return item && item.contentReady && item.flickContentHeight > item.height * root.tallScreens }
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

    FloatingWindow {
        implicitWidth: 760
        implicitHeight: 700
        color: Flea.Theme.color.background
        Flea.PreviewMarkdown {
            id: md
            width: 600
            height: 580
            active: true
            path: root.fixture
            size: 2000
        }
    }
    Connections {
        target: md.bodyItem
        function onContentHeightChanged() {
            if (root.measuring && md.bodyItem.contentHeight > 0)
                root.smallestHeight = Math.min(root.smallestHeight, md.bodyItem.contentHeight)
        }
        function onContentYChanged() {
            if (root.measuring && root.moves.length < root.moveLogLimit)
                root.moves.push(Math.round(md.bodyItem.contentY))
        }
        // The turn the model is replaced, where restoreScroll bounds the place by what the list reports.
        function onModelChanged() {
            if (root.measuring)
                root.heightAtReset = md.bodyItem.contentHeight
        }
    }
    Connections {
        target: md
        function onLoadRunsChanged() {
            if (!root.writerDone)
                root.reloadsWhileRunning++
        }
    }
    Process {
        id: writer
        onExited: function (exitCode, exitStatus) {
            root.check("the writer completed", exitCode, 0)
            root.writerDone = true
        }
    }
    Process {
        id: editor
        onExited: function (exitCode, exitStatus) {
            root.check("fixture edit completed", exitCode, 0)
            root.editDone = true
        }
    }

    // A file written every few ms for several coalescing windows reloads while the writer runs, not only after it stops.
    function streamStep() {
        if (root.stage === 0 && root.tall(md)) {
            root.fullText = md.rawText
            root.reloadsWhileRunning = 0
            root.writerDone = false
            writer.command = ["python3", "-c", root.streamScript, root.fixture, String(root.streamWrites), String(root.streamGapMs)]
            writer.running = true
            root.stage = 1
            return
        }
        if (root.stage === 1 && root.writerDone) {
            root.check("the file reloads at least " + root.streamMinReloads + " times while the writer is still running",
                root.reloadsWhileRunning >= root.streamMinReloads, true)
            root.check("a burst is absorbed, not reloaded per write", root.reloadsWhileRunning < root.streamWrites, true)
            root.stage = 2
            return
        }
        var pieces = []
        for (var i = 0; i < root.streamWrites; i++) pieces.push("\n\nstream " + i + ".")
        var finalText = root.fullText + pieces.join("")
        if (root.stage === 2 && root.landedWithin("the final text", md.rawText === finalText && md.contentReady)) {
            root.stage = 3
            root.settle = 0
            return
        }
        if (root.stage === 3 && root.quiet()) {
            root.check("the final text is shown after the writer stops", md.rawText === finalText, true)
            root.finish()
        }
    }

    // A reader who moves a held place away ends the hold: the next taller content does not drag the view back to the old place.
    function regrowStep() {
        if (root.stage === 0 && root.tall(md)) {
            md.bodyItem.contentY = root.scrollTargetY
            root.scrolledY = md.bodyItem.contentY
            root.check("scrolled into the document", root.scrolledY, root.scrollTargetY)
            root.fullText = md.rawText
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
            root.check("the saved place lies past the shortened content", root.scrolledY > root.highest(list), true)
            root.readerY = root.highest(list)
            root.check("a hold waits at the resting end before the reader moves",
                [md.keepScroll, Math.abs(md.heldY - root.readerY) < md.samePlacePx], [true, true])
            list.contentY = root.readerY - root.readerMovePx
            root.check("moving the view releases the held place", [md.keepScroll, isNaN(md.heldY)], [false, true])
            list.contentY = root.readerY
            root.edit(root.writeScript, root.fullText)
            root.stage = 3
            return
        }
        if (root.stage === 3 && root.editDone && root.landedWithin("the full text", md.rawText === root.fullText && md.contentReady)) {
            root.stage = 4
            root.settle = 0
            return
        }
        if (root.stage === 4 && root.quiet()) {
            root.check("the full text is drawn", md.rawText === root.fullText, true)
            root.check("the view stays where the reader left it", md.bodyItem.contentY, root.readerY)
            root.check("the view is not at the old deep place", md.bodyItem.contentY !== root.scrolledY, true)
            root.finish()
        }
    }

    // The place by block: the one at the view's top and the pixels the view lies past its top edge; the list's own contentY is an estimate that moves when blocks are built.
    function placeOf() {
        var item = md.topBlockItem()
        return item === null ? null : [item.blockIndex, Math.round(md.bodyItem.contentY - item.y)]
    }
    // A list of blocks of very different heights: the place is kept exactly, though the list's own height is an estimate after a reset.
    function unevenStep() {
        var list = md.bodyItem
        if (root.stage === 0 && root.tall(md)) {
            root.stage = 1
            return
        }
        // Walk the whole document top to bottom so every block has been laid out and the height is the real one.
        if (root.stage === 1) {
            list.contentY = Math.min(list.contentY + list.height * root.walkScreens, root.highest(list))
            var atEnd = Math.abs(list.contentY - root.highest(list)) < md.samePlacePx
            var steady = list.contentHeight === root.walkHeight
            root.walkHeight = list.contentHeight
            if (atEnd && steady) {
                root.realHeight = list.contentHeight
                root.stage = 2
            }
            return
        }
        if (root.stage === 2) {
            list.contentY = list.originY + Math.floor(root.unevenDepth * root.realHeight)
            root.stage = 3
            root.settle = 0
            return
        }
        if (root.stage === 3 && root.quiet()) {
            root.scrolledY = list.contentY
            root.placeBefore = root.placeOf()
            root.check("the reader is past three quarters of the real height", root.scrolledY - list.originY > root.unevenPastShare * root.realHeight, true)
            root.loadsBefore = md.loadRuns
            root.measuring = true
            root.edit(root.unevenScript)
            root.stage = 4
            return
        }
        if (root.stage === 4 && root.editDone && root.landedWithin("the edit", md.rawText.indexOf("edited paragraph 0.") === 0
                && md.loadRuns > root.loadsBefore && md.contentReady)) {
            root.stage = 5
            root.settle = 0
            return
        }
        if (root.stage === 5 && root.quiet()) {
            console.log("PREVIEW_HUNT INFO uneven: height at the model reset " + Math.round(root.heightAtReset)
                + ", smallest height seen while reloading " + Math.round(root.smallestHeight)
                + ", real height " + Math.round(root.realHeight) + ", place " + JSON.stringify(root.placeBefore) + " at y " + Math.round(root.scrolledY)
                + ", moves " + root.moves.join(" "))
            root.check("the place before the edit is built", root.placeBefore !== null, true)
            if (root.placeBefore !== null)
                root.check("the place is kept exactly across a same-length edit", root.placeOf(), root.placeBefore)
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
            if (root.scenario === "disk-stream") root.streamStep()
            else if (root.scenario === "disk-regrow") root.regrowStep()
            else root.unevenStep()
        }
    }
}
