//@ pragma ShellId flea-quicklook-firstframe-test

import QtQuick
import QtTest
import Quickshell
import "flea/js/PreviewKeys.js" as PreviewKeys

// The real window: Space on a small Markdown file opens a card that already holds the document's first block.
// Sample output: "QLFF CYCLE 1 frames=1 empty=0 content=1" is one open, in frames counted from the key.
// QLFF_MODE=call runs the function the Space binding calls and reads the preview before the event loop turns, which a
// real key through QtTest cannot (it processes events itself); key sends the real key, for the trace.
ShellRoot {
    id: root

    readonly property string uiDir: Quickshell.env("QLFF_UI")
    readonly property string fixture: Quickshell.env("QLFF_DIR")
    readonly property string name: Quickshell.env("QLFF_NAME")
    readonly property bool realKey: Quickshell.env("QLFF_MODE") === "key"
    readonly property int cycleCount: Number(Quickshell.env("QLFF_CYCLES"))
    // Polls of a quiet window before a cycle starts, so the previous close and the listing are done.
    readonly property int quietPolls: 8
    // A cycle that never reaches content is a harness fault, not a duration the product is held to.
    readonly property int watchdogMs: 6000
    readonly property int pollMs: 20

    property int stage: 0
    property int cycle: 0
    property int quiet: 0
    property int frames: 0
    property int emptyFrames: 0
    property int contentFrame: 0
    property int failures: 0
    property double stageAt: Date.now()
    property var keys: null
    property var prepare: null

    function log(line) { console.log("QLFF " + line) }
    function finish() {
        root.log("DONE cycles=" + root.cycle + " failures=" + root.failures)
        Qt.exit(root.failures ? 1 : 0)
    }
    function fail(why) { root.failures++; root.log("FAIL " + why) }
    function pane() { return body.item ? body.item.currentPane : null }
    function pv() { return root.pane() ? root.pane().preview : null }
    // A real item of the shell by its type name, searched down from the preview overlay.
    function find(item, type) {
        if (String(item).indexOf(type) === 0) return item
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) {
            var found = root.find(kids[i], type)
            if (found) return found
        }
        return null
    }
    function firstBlock() {
        var p = root.pv()
        var md = p ? p.markdownItem : null
        return md ? md.blockItem(0) : null
    }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 700
        Loader {
            id: body
            anchors.fill: parent
            source: "file://" + root.uiDir + "/WindowBody.qml"
            onLoaded: item.host = window
            onStatusChanged: if (status === Loader.Error) { root.fail("WindowBody failed to load"); root.finish() }
        }
    }

    // Every frame the window draws while a cycle is open: the card on screen without its first block is an empty frame.
    Connections {
        target: window.contentItem.Window.window
        function onFrameSwapped() {
            if (root.stage !== 2) return
            root.frames++
            var block = root.firstBlock()
            var shown = root.pv() && root.pv().visible
            if (shown && !block) root.emptyFrames++
            if (shown && block && block.height > 0 && root.contentFrame === 0) root.contentFrame = root.frames
            root.log("FRAME " + root.frames + " shown=" + shown + " block=" + (block !== null))
        }
    }

    // A moving cursor reads nothing: twenty moves in one turn leave the read count where it was.
    property bool swept: false
    readonly property int sweepMoves: 20
    function sweep(pane) {
        var reads = root.prepare.reads
        for (var i = 0; i < root.sweepMoves; i++) pane.cursorIndex = i % 2
        pane.cursorIndex = 0
        if (root.prepare.reads !== reads) root.fail("a cursor sweep read " + (root.prepare.reads - reads) + " file(s)")
        root.log("SWEEP reads=" + root.prepare.reads)
        root.swept = true
        root.quiet = 0
    }

    function open() {
        var pane = root.pane()
        pane.listArea.forceActiveFocus()
        root.frames = 0
        root.emptyFrames = 0
        root.contentFrame = 0
        root.stage = 2
        root.stageAt = Date.now()
        root.log("KEY " + (root.cycle + 1))
        if (root.realKey) {
            root.keys.keyClick(Qt.Key_Space, Qt.NoModifier, -1)
        } else {
            PreviewKeys.open(pane)
            // No event has run since the key: the card and the document's blocks must both be there already.
            var md = root.pv().markdownItem
            var blocks = md ? md.blockList.length : 0
            root.log("SYNC " + (root.cycle + 1) + " card=" + root.pv().active + " blocks=" + blocks)
            if (!root.pv().active || blocks === 0)
                root.fail("cycle " + (root.cycle + 1) + " returned from the key with card=" + root.pv().active + " and " + blocks + " blocks")
        }
        root.log("KEYRETURNED " + (root.cycle + 1))
    }

    Timer {
        interval: root.pollMs
        repeat: true
        running: true
        onTriggered: {
            if (Date.now() - root.stageAt > root.watchdogMs) {
                root.fail("stage " + root.stage + " stalled in cycle " + (root.cycle + 1) + " reads=" + (root.prepare ? root.prepare.reads : -1)
                    + " prepared=" + (root.prepare ? root.prepare.preparedPath : "") + " quiet=" + root.quiet + " swept=" + root.swept)
                root.finish()
                return
            }
            var pane = root.pane()
            if (root.stage === 0) {
                if (!pane || pane.listInFlight || pane.listingState !== "ready" || pane.total < 2) return
                root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", pane.listArea)
                root.prepare = root.find(root.pv(), "QuickLookPrepare")
                if (!root.prepare) { root.fail("the preview has no QuickLookPrepare"); root.finish(); return }
                root.stage = 1
                root.quiet = 0
                return
            }
            if (root.stage === 1) {
                // The cursor must rest on the document, and the window must have been quiet for a few polls.
                var row = pane.rowFor(pane.cursorIndex)
                if (!row || row.n !== root.name || root.pv().active) { root.quiet = 0; return }
                if (++root.quiet < root.quietPolls) return
                // The cursor has rested on the document: its parse is in the entry before Space is pressed.
                if (root.prepare.preparedPath !== root.fixture + "/" + root.name) return
                if (!root.swept) { root.sweep(pane); return }
                root.open()
                return
            }
            if (root.stage === 2) {
                if (root.contentFrame === 0) return
                root.log("CYCLE " + (root.cycle + 1) + " frames=" + root.contentFrame + " empty=" + root.emptyFrames
                    + " content=" + root.contentFrame)
                if (root.emptyFrames !== 0)
                    root.fail("cycle " + (root.cycle + 1) + " drew the card " + root.emptyFrames + " time(s) without its first block")
                var doc = root.find(root.pv(), "PreviewMarkdown")
                root.log("REUSED " + (root.cycle + 1) + " " + (doc ? doc.reusedParses : -1))
                if (!doc || doc.reusedParses !== 1)
                    root.fail("cycle " + (root.cycle + 1) + " parsed again instead of taking the prepared entry")
                if (root.contentFrame !== 1)
                    root.fail("cycle " + (root.cycle + 1) + " reached content in frame " + root.contentFrame + ", want 1")
                root.cycle++
                root.stage = 3
                root.stageAt = Date.now()
                // The second Space closes, the same real key.
                root.keys.keyClick(Qt.Key_Space, Qt.NoModifier, -1)
                return
            }
            if (root.stage === 3) {
                if (root.pv().visible) return
                if (root.cycle >= root.cycleCount) { root.finish(); return }
                root.stage = 1
                root.quiet = 0
                root.stageAt = Date.now()
            }
        }
    }
}
