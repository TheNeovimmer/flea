//@ pragma ShellId flea-quicklook-firstframe-test

import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "quicklook-firstframe.js" as Fresh
import "flea/js/PreviewKeys.js" as PreviewKeys

// Sample output: "QLFF STEP 1 a-notes.md inline frames=1 empty=0" is one open, in frames counted from the card's first.
// QLFF_MODE=call returns from the Space binding before the event loop turns, which a real key through QtTest cannot; key is the trace.
ShellRoot {
    id: root

    readonly property string uiDir: Quickshell.env("QLFF_UI")
    readonly property string fixture: Quickshell.env("QLFF_DIR")
    // Steps "name:expect:via": expect inline (content in the card's first frame), async (no blocking read), rest (no read) or capped (a stale row's file read to the cap).
    readonly property var steps: Quickshell.env("QLFF_STEPS").split(",").map(function (s) { var p = s.split(":"); return { name: p[0], expect: p[1], via: p[2] || "space" } })
    // A storage class the leg forces, or "unknown" to hold the pane before its class reply (storageKnown false, class "").
    readonly property string forcedClass: Quickshell.env("QLFF_CLASS")
    readonly property bool realKey: Quickshell.env("QLFF_MODE") === "key"
    // The fixture documents that link a local picture, which a step on them must find drawn.
    readonly property var pictureDocs: ["a-notes.md", "h-html.md"]
    // QLFF_REENTER=1 runs one poll tick inside the close key's event loop, which a loaded host does by chance.
    readonly property bool reenter: Quickshell.env("QLFF_REENTER") === "1"
    // A keyClick delay pumps a nested loop, so the reenter kicker fires inside the key.
    readonly property int pressDelayMs: 10
    // QLFF_LATEROWS=1 pins the harness's own restore of a late rows reply on a loaded host: a capped or rest step's first rest answers with one listing the file's real size again.
    readonly property bool lateRows: Quickshell.env("QLFF_LATEROWS") === "1"
    // The size a capped or rest step's row lists, as a listing does for a file that grew since.
    readonly property int staleBytes: 900
    // Polls of a quiet window before a step starts, so the previous close and the listing are done.
    readonly property int quietPolls: 8
    // A step that never reaches content is a harness fault, not a duration the product is held to; a 1 MiB parse is the slowest.
    readonly property int watchdogMs: 20000
    readonly property int pollMs: 20
    // A held key repeats every 30 ms; the sweep widens the rest to 300 ms so a late tick on a loaded host cannot pass for a rested cursor.
    readonly property int sweepPaceMs: 30
    readonly property int sweepMoves: 20
    readonly property int sweepRestMs: 300
    // One byte past the 64 KiB cap, so a read that returns it knows the file is over.
    readonly property int capBytes: 65537
    // A big document's first frame builds this many block delegates at most, and a too-deep one lays out this many Source chunks at most.
    readonly property int firstScreenDelegates: 40
    readonly property int firstScreenChunks: 6

    property int stage: 0
    property int step: 0
    property int quiet: 0
    property int frames: 0
    property int emptyFrames: 0
    property int contentFrame: 0
    // The card's pictures and how many are ready, counted as the key returns before any event has run, so a decode finishing meanwhile never passes for a held one.
    property var syncPictures: ({ total: 0, ready: 0 })
    property var atContent: ({ parsing: false, look: false, delegates: -1 })
    property int maxSourceChars: 0
    property int failures: 0
    property int sweepLeft: 0
    property int restedMs: 0
    property double lastTick: 0
    property bool sweeping: Quickshell.env("QLFF_SWEEP") === "1"
    property int readsBefore: 0
    property int answersBefore: 0
    property real blockedBefore: 0
    property double stageAt: Date.now()
    property var keys: null
    property var prepare: null
    // The window's QuickLookWarm, built by the cursor's first landing on a Markdown file, long before Quick Look.
    property var warm: null
    // QLFF_NOBUILD=1 rests on a Markdown file and never opens: no card may be built while the entry and the units are made.
    readonly property bool nobuildWanted: Quickshell.env("QLFF_NOBUILD") === "1"
    // The first prepared parse of a run is the worker's; later opens reuse the entry Quick Look stored itself.
    property bool compared: false
    // True while a real key's event loop runs: a poll tick inside it must not finish the run, as Qt.exit there tears the root down under the key's own handler.
    property bool inKey: false
    property int reentered: 0
    property int realBytes: 0
    property int lateRowsAt: -1

    function log(line) { console.log("QLFF " + line) }
    // Sample input: "Pss:                 28438 kB" in /proc/self/smaps_rollup answers 28438; the window's own resident memory, logged and never judged.
    function pssKb() {
        smaps.reload()
        var m = /Pss:\s+(\d+) kB/.exec(smaps.text())
        return m ? Number(m[1]) : -1
    }
    FileView { id: smaps; path: "/proc/self/smaps_rollup"; blockLoading: true }
    property double keyAt: 0
    property double returnedAt: 0
    property double contentAt: 0
    function finish() {
        if (root.reenter && root.reentered < 1) root.fail("reenter leg saw no kicker tick inside the key")
        root.log("DONE steps=" + root.step + " failures=" + root.failures)
        Qt.exit(root.failures ? 1 : 0)
    }
    function fail(why) { root.failures++; root.log("FAIL " + why) }
    function pane() { return body.item ? body.item.currentPane : null }
    function pv() { return root.pane() ? root.pane().preview : null }
    // The class is forced while Quick Look's prepare is held (resting false), so no rest can read under the backend's own answer.
    function forceClass() {
        var pane = root.pane()
        if (root.forcedClass === "" || !pane) return
        if (root.forcedClass === "unknown") {
            if (pane.storageClass !== "") pane.storageClass = ""
            if (pane.storageKnown) pane.storageKnown = false
        } else if (pane.storageClass !== root.forcedClass) {
            pane.storageClass = root.forcedClass
        }
    }
    function press() {
        if (root.reenter) kicker.start()
        root.inKey = true
        root.keys.keyClick(Qt.Key_Space, Qt.NoModifier, root.reenter ? root.pressDelayMs : -1)
        root.inKey = false
    }
    function cur() { return root.steps[root.step] }
    function target() { return root.fixture + "/" + root.cur().name }
    function indexOf(name) { return Fresh.indexOf(root, name) }
    function find(item, type) { return Fresh.find(item, type) }
    function doc() { return Fresh.doc(root) }
    function pictureState() { return Fresh.pictureState(root, Image.Ready) }
    function unitsReady() { return Fresh.unitsReady(root, Component.Ready) }
    function firstBlock() { return Fresh.firstBlock(root) }

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

    // Every frame the window draws while a step is open: the card on screen without its document's first block is an empty frame.
    Connections {
        target: window.contentItem.Window.window
        function onFrameSwapped() {
            if (root.stage !== 2) return
            var p = root.pv()
            var on = root.cur().via === "move" ? (p && p.path === root.target()) : (p && p.visible)
            if (!on) return
            root.frames++
            var block = root.firstBlock()
            if (!block) root.emptyFrames++
            else if (block.height > 0 && root.contentFrame === 0) {
                root.contentFrame = root.frames
                root.contentAt = Date.now()
                root.atContent = { parsing: root.doc().parsing, look: root.pv().lookReady, delegates: root.doc().delegateCount() }
            }
            if (root.doc()) root.maxSourceChars = Math.max(root.maxSourceChars, root.doc().sourceChars)
            root.log("FRAME " + root.frames + " block=" + (block !== null))
        }
    }

    // A held key moves the cursor between two small documents across event-loop turns: nothing is read until it rests.
    Timer {
        id: sweepTimer
        interval: root.sweepPaceMs
        repeat: true
        onTriggered: {
            var pane = root.pane()
            var names = ["a-notes.md", "d-small.md"]
            var now = Date.now()
            // A tick that came a whole rest late let the rest timer fire legitimately, so the sweep starts over.
            if (root.sweepLeft > 0 && now - root.lastTick >= root.sweepRestMs) {
                root.log("SWEEP stalled, rerun")
                root.readsBefore = root.prepare.reads
                root.sweepLeft = root.sweepMoves
            }
            root.lastTick = now
            if (root.sweepLeft > 0) {
                pane.cursorIndex = root.indexOf(names[root.sweepLeft % 2])
                root.sweepLeft--
                if (root.prepare.reads !== root.readsBefore) {
                    root.fail("a held key read " + (root.prepare.reads - root.readsBefore) + " file(s) before it rested")
                    root.sweepLeft = 0
                }
                return
            }
            sweepTimer.stop()
            root.prepare.restMs = root.restedMs
            root.log("SWEEP reads=" + root.prepare.reads)
            pane.cursorIndex = root.indexOf(root.cur().name)
            root.sweeping = false
            root.quiet = 0
        }
    }

    function answerControl() { return Fresh.answerControl(root) }

    function open() {
        var pane = root.pane()
        var step = root.cur()
        pane.listArea.forceActiveFocus()
        root.frames = 0
        root.emptyFrames = 0
        root.contentFrame = 0
        root.syncPictures = { total: 0, ready: 0 }
        root.maxSourceChars = 0
        var before = root.doc()
        root.blockedBefore = before ? Number(before.blockedReads) : 0
        root.stage = 2
        root.stageAt = Date.now()
        root.keyAt = Date.now()
        root.log("KEY " + (root.step + 1) + " " + step.name + " " + step.via + " built=" + (root.pv() !== null))
        if (step.via === "move") {
            PreviewKeys.act(root.indexOf(step.name) > pane.cursorIndex ? "cursorDown" : "cursorUp", pane)
        } else if (root.realKey) {
            root.press()
        } else {
            PreviewKeys.open(pane)
            // No event has run since the key: an inline document's blocks are already in the card, and a big one has not been read.
            var d = root.doc()
            var blocks = d ? d.blockList.length : 0
            var loads = d ? d.loadRuns : -1
            root.syncPictures = root.pictureState()
            root.log("SYNC " + (root.step + 1) + " card=" + root.pv().active + " blocks=" + blocks + " loads=" + loads
                + " pictures=" + root.syncPictures.ready + "/" + root.syncPictures.total + " held=" + (root.prepare.pictures ? root.prepare.pictures.length : -1))
            if (!root.pv().active) root.fail("step " + (root.step + 1) + " returned from the key without the card")
            if (step.expect === "inline" && blocks === 0)
                root.fail("step " + (root.step + 1) + " returned from the key with 0 blocks")
            if ((step.expect === "async" || step.expect === "partial" || step.expect === "deep") && loads !== 0)
                root.fail("step " + (root.step + 1) + " read " + step.name + " inside the key (" + loads + " load(s) landed before the event loop turned)")
        }
        root.returnedAt = Date.now()
        root.log("KEYRETURNED " + (root.step + 1))
    }

    function next() {
        root.step++
        root.stage = 1
        root.quiet = 0
        root.stageAt = Date.now()
        root.readsBefore = root.prepare.reads
        if (root.step >= root.steps.length) root.finish()
    }

    function judge() { return Fresh.judge(root) }

    // The next step is a move on the open card, or a second Space closes, the same real key.
    function leave() {
        root.stage = 3
        root.stageAt = Date.now()
        var after = root.steps[root.step + 1]
        if (after && after.via === "move") { root.step++; root.stage = 1; root.quiet = 0; root.stageAt = Date.now(); return }
        root.press()
    }

    Timer {
        id: kicker
        interval: 0
        onTriggered: poll.triggered()
    }

    Timer {
        id: poll
        interval: root.pollMs
        repeat: true
        running: true
        onTriggered: {
            if (root.inKey) {
                root.reentered++
                root.log("REENTERED " + root.reentered)
                return
            }
            var pane = root.pane()
            if (Date.now() - root.stageAt > root.watchdogMs) {
                var at = pane ? pane.rowFor(pane.cursorIndex) : null
                root.fail("stage " + root.stage + " stalled in step " + (root.step + 1) + " reads=" + (root.prepare ? root.prepare.reads : -1)
                    + " prepared=" + (root.prepare ? root.prepare.preparedPath : "") + " quiet=" + root.quiet
                    + " cursor=" + (at ? at.n + ":" + at.s : "none") + " resting=" + (root.prepare ? root.prepare.resting : "") + " listInFlight=" + (pane ? pane.listInFlight : "")
                    + " storageKnown=" + (pane ? pane.storageKnown : "") + " class=" + (pane ? pane.storageClass : ""))
                root.finish()
                return
            }
            if (root.stage === 0) {
                if (!pane || pane.listInFlight || pane.listingState !== "ready" || pane.total < 2) return
                if (!root.prepare) {
                    // The class reply is awaited once; a leg that forces it unknown holds it so from then on.
                    if (!pane.storageKnown) return
                    // A user's cursor lands on the file first, which builds the warm and none of Quick Look; it is held before any event turn, so no rest can read under the class.
                    if (root.pv() !== null) { root.fail("Quick Look is built before the first Space"); root.finish(); return }
                    root.forceClass()
                    root.log("PSS rest-no-markdown " + root.pssKb())
                    pane.cursorIndex = root.indexOf(root.cur().name)
                    root.warm = root.find(body.item, "QuickLookWarm")
                    root.prepare = root.find(body.item, "QuickLookPrepare")
                    if (!root.warm || !root.prepare) { root.fail("the cursor rests on " + root.cur().name + " and no prepare or unit warm is built before the first Space"); root.finish(); return }
                    root.prepare.resting = false
                    return
                }
                if (!root.unitsReady()) return
                if (root.pv() !== null) { root.fail("Quick Look is built before the first Space"); root.finish(); return }
                root.log("PSS rest-markdown " + root.pssKb())
                root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", pane.listArea)
                root.forceClass()
                // The class is forced, so the held prepare rests again and the cursor's rest starts over under it.
                root.prepare.resting = true
                root.prepare.moved()
                root.answerControl()
                root.readsBefore = root.prepare.reads
                root.stage = 1
                root.quiet = 0
                return
            }
            // The backend's own class answer never wins over the one the leg forces.
            root.forceClass()
            if (sweepTimer.running) return
            if (root.stage === 1) {
                var step = root.cur()
                var open = root.pv() !== null && root.pv().active
                // A move keeps the card open on the previous file; any other step starts from a closed card with the cursor on its file.
                if (step.via === "move" ? !open : open) { root.quiet = 0; return }
                var row = pane.rowFor(pane.cursorIndex)
                if (step.via !== "move" && (!row || row.n !== step.name)) {
                    // A capped or rest step's row says 900 bytes, as a listing does for a file that grew since, so only the file's own type can refuse it.
                    if (step.expect === "capped" || step.expect === "rest") {
                        var stale = pane.rowFor(root.indexOf(step.name))
                        if (stale.s !== root.staleBytes) root.realBytes = stale.s
                        stale.s = root.staleBytes
                    }
                    pane.cursorIndex = root.indexOf(step.name)
                    root.quiet = 0
                    return
                }
                if (root.lateRows && root.lateRowsAt !== root.step && (step.expect === "capped" || step.expect === "rest")) {
                    root.lateRowsAt = root.step
                    var late = pane.rows.map(function (r) { return Object.assign({}, r) })
                    late[pane.cursorIndex - pane.held].s = root.realBytes
                    pane.rows = late
                    root.quiet = 0
                    return
                }
                // A late rows reply lists the real size again, which no read at rest answers: the harness puts the stale size back and rests the cursor again.
                if ((step.expect === "capped" || step.expect === "rest") && row.s !== root.staleBytes) {
                    row.s = root.staleBytes
                    root.prepare.moved()
                    root.quiet = 0
                    return
                }
                if (++root.quiet < root.quietPolls) return
                if (root.sweeping) {
                    root.readsBefore = root.prepare.reads
                    root.sweepLeft = root.sweepMoves
                    root.restedMs = root.prepare.restMs
                    root.prepare.restMs = root.sweepRestMs
                    root.lastTick = Date.now()
                    sweepTimer.start()
                    return
                }
                if (step.expect === "inline" && step.via === "space" && (root.prepare.preparedPath !== root.target() || root.prepare.picturesSettled === false)) return
                if (step.expect === "inline" && step.via === "space" && root.prepare.workerAnswers <= root.answersBefore) {
                    root.fail("step " + (root.step + 1) + " found " + step.name + " prepared without the worker answering")
                    root.finish()
                    return
                }
                if (step.expect !== "inline" && step.expect !== "capped" && step.via === "space" && root.prepare.preparedPath === root.target()) {
                    root.fail("step " + (root.step + 1) + " prepared " + step.name + ", which no read may touch")
                    root.finish()
                    return
                }
                if (step.expect !== "inline" && step.expect !== "capped" && step.via === "space" && root.prepare.reads !== root.readsBefore) {
                    root.fail("step " + (root.step + 1) + " read " + (root.prepare.reads - root.readsBefore) + " file(s) at rest for " + step.name)
                    root.finish()
                    return
                }
                // The nobuild leg never opens: a rest holds the entry and the units with no card, and a move off drops the entry.
                if (root.nobuildWanted) { Fresh.proveGone(root); pane.cursorIndex = root.indexOf(step.name) + 1; Fresh.proveMoved(root); root.next(); return }
                if (step.expect === "capped") {
                    if (root.prepare.readBytes === 0) return
                    root.log("CAPPED reads=" + root.prepare.reads + " bytes=" + root.prepare.readBytes)
                    if (root.prepare.readBytes !== root.capBytes) root.fail("step " + (root.step + 1) + " read " + root.prepare.readBytes + " bytes of a stale row's file, want the cap " + root.capBytes)
                    if (root.prepare.preparedPath === root.target()) root.fail("step " + (root.step + 1) + " prepared a file past the cap")
                    root.next()
                    return
                }
                if (step.expect === "rest") { root.next(); return }
                root.open()
                return
            }
            if (root.stage === 2) {
                // Content in the card is the new document's own first block; the frame counter has seen it by the poll after.
                if (!root.firstBlock() || root.contentFrame === 0) return
                root.judge()
                root.stageAt = Date.now()
                // A head step lets the whole parse land before a next step that needs the worker, which a small file's parse never does.
                var upcoming = root.steps[root.step + 1]
                if (root.cur().expect === "partial" && upcoming && upcoming.expect !== "inline") { root.stage = 4; return }
                root.leave()
                return
            }
            if (root.stage === 4) {
                if (!root.doc().parsing) root.leave()
                return
            }
            if (root.stage === 3) {
                if (root.pv().visible) return
                root.next()
            }
        }
    }
}
