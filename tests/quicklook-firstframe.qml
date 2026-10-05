//@ pragma ShellId flea-quicklook-firstframe-test

import QtQuick
import QtTest
import Quickshell
import "flea/js/Markdown.js" as Markdown
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
    // The first prepared parse of a run is the worker's; later opens reuse the entry Quick Look stored itself.
    property bool compared: false

    function log(line) { console.log("QLFF " + line) }
    function finish() {
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
    function cur() { return root.steps[root.step] }
    function target() { return root.fixture + "/" + root.cur().name }
    function indexOf(name) {
        for (var i = 0; i < root.pane().total; i++) {
            var row = root.pane().rowFor(i)
            if (row && row.n === name) return i
        }
        return -1
    }
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
    function doc() { return root.pv() ? root.find(root.pv(), "PreviewMarkdown") : null }
    function collect(item, type, out) {
        if (!item) return
        if (String(item).indexOf(type) === 0) out.push(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) root.collect(kids[i], type, out)
    }
    // Every picture the open document draws and how many have their pixels: one still loading in the first frame lands a frame later.
    function pictureState() {
        var found = []
        root.collect(root.doc(), "QQuickImage", found)
        return { total: found.length, ready: found.filter(function (one) { return one.status === Image.Ready }).length }
    }
    // The compiled units the idle warm holds: an open before them would compile inside the key, which a user's first Space never does.
    function unitsReady() {
        var p = root.pv()
        // A preview with no swap unit is waited for on the Markdown one alone, so the compile gate in the script is what fails it.
        var units = p ? (p.swapUnit === undefined ? [p.markdownUnit] : [p.markdownUnit, p.swapUnit]) : []
        return units.length > 0 && units.every(function (u) { return u !== null && u !== undefined && u.status === Component.Ready })
    }
    // The first block of the document named by the step: a block left over from the previous file never counts.
    function firstBlock() {
        var p = root.pv()
        var md = p ? p.markdownItem : null
        // A too-deep document draws its notice and its Source, which is its content.
        var inner = root.doc()
        if (root.cur().expect === "deep") return inner && inner.tooDeep && inner.sourceChars > 0 && inner.noticeItem.visible ? inner.noticeItem : null
        var block = md ? md.blockItem(0) : null
        var title = root.cur().name.replace(".md", "")
        return block && block.block && String(block.block.text).indexOf(title) >= 0 ? block : null
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

    // An answer for a cursor that moved on is dropped, and one for the cursor that rests is kept; neither is a read of a file.
    function answerControl() {
        var p = root.prepare
        var held = p.preparedPath
        var seq = p.seq
        var request = { path: "/nowhere/stale.md", text: "# stale\n", dir: "/nowhere/", chrome: "#000000", ink: "#ffffff" }
        p.asked = Object.assign({ seq: seq - 1 }, request)
        p.answered({ seq: seq - 1, blocks: [{ type: "run", text: "stale" }], error: "" })
        if (p.preparedPath !== held || p.workerAnswers !== 0) root.fail("an answer for a cursor that moved on was kept")
        p.asked = Object.assign({ seq: seq }, request)
        p.answered({ seq: seq, blocks: [{ type: "run", text: "stale" }], error: "" })
        if (p.preparedPath !== request.path || p.workerAnswers !== 1) root.fail("an answer for the resting cursor was dropped")
        root.answersBefore = p.workerAnswers
    }

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
        root.log("KEY " + (root.step + 1) + " " + step.name + " " + step.via)
        if (step.via === "move") {
            PreviewKeys.act(root.indexOf(step.name) > pane.cursorIndex ? "cursorDown" : "cursorUp", pane)
        } else if (root.realKey) {
            root.keys.keyClick(Qt.Key_Space, Qt.NoModifier, -1)
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

    // Object keys in sorted order, because a block that crossed the worker's boundary comes back with its keys sorted.
    function canon(v) {
        if (v === null || typeof v !== "object") return JSON.stringify(v)
        if (Array.isArray(v)) return "[" + v.map(root.canon).join(",") + "]"
        return "{" + Object.keys(v).sort().filter(function (k) { return v[k] !== undefined }).map(function (k) { return JSON.stringify(k) + ":" + root.canon(v[k]) }).join(",") + "}"
    }
    // The blocks the card took from the prepared entry (the worker's parse) against a fresh parse of the same text on the merged parser, kinds the stage added among them.
    function sameAsFreshParse(d, n) {
        var fresh = Markdown.blocks(d.rawText, Markdown.dirOf(d.path), d.chromeHex, d.inkHex)
        var kinds = fresh.map(function (b) { return b.type })
        var empty = fresh.some(function (b) { return b.type === "heading" && b.text === "" })
        if (kinds.indexOf("images") < 0 || kinds.indexOf("image") < 0 || kinds.indexOf("quote") < 0 || !empty)
            root.fail("step " + n + " fixture lost a kind the prepared parse must carry: " + kinds.join("+"))
        if (root.canon(d.blockList) !== root.canon(fresh))
            root.fail("step " + n + " drew a prepared parse that differs from a fresh parse of the same text")
        else
            root.log("PARSE " + n + " prepared equals fresh blocks=" + fresh.length)
    }

    // The checks of one finished step, run once its document's first block is in the card.
    function judge() {
        var step = root.cur()
        var n = root.step + 1
        var d = root.doc()
        var blocked = d ? d.blockedReads - root.blockedBefore : -1
        root.log("STEP " + n + " " + step.name + " " + step.expect + " frames=" + root.contentFrame + " empty=" + root.emptyFrames + " blocked=" + blocked
            + " pictures=" + root.syncPictures.ready + "/" + root.syncPictures.total)
        if (!d || (step.expect !== "deep" && d.sourceChars !== 0)) root.fail("step " + n + " laid out " + (d ? d.sourceChars : -1) + " characters of Source text while Rendered shows")
        if (step.expect === "inline") {
            if (root.emptyFrames !== 0) root.fail("step " + n + " drew the card " + root.emptyFrames + " time(s) without its first block")
            if (root.contentFrame !== 1) root.fail("step " + n + " reached content in frame " + root.contentFrame + ", want 1")
            if (blocked !== 1) root.fail("step " + n + " blocked " + blocked + " time(s) for a small local file, want 1")
            if (step.via === "space" && (!d || d.reusedParses !== 1)) root.fail("step " + n + " parsed again instead of taking the prepared entry")
            // A small local picture is held decoded while the cursor rests, so the card builds it ready inside the key and draws it in its first frame.
            if (step.via === "space" && root.syncPictures.total === 0 && root.pictureDocs.indexOf(step.name) >= 0) root.fail("step " + n + " built no picture to check")
            if (step.via === "space" && !root.realKey && root.syncPictures.ready !== root.syncPictures.total)
                root.fail("step " + n + " built " + (root.syncPictures.total - root.syncPictures.ready) + " of " + root.syncPictures.total + " picture(s) still loading when the key returned")
            if (step.via === "space" && d && d.reusedParses === 1 && !root.compared && step.name === "a-notes.md") {
                root.compared = true
                root.sameAsFreshParse(d, n)
            }
        } else if (blocked !== 0) {
            root.fail("step " + n + " blocked " + blocked + " time(s) for " + step.name + ", want 0")
        }
        // A big document's first screen draws from the head of the parse, which is still running, and builds a screenful of delegates.
        if (step.expect === "partial" && (!root.atContent.parsing || root.atContent.delegates > root.firstScreenDelegates))
            root.fail("step " + n + " drew block 0 with the parse " + (root.atContent.parsing ? "running" : "done") + " and " + root.atContent.delegates + " delegates")
        // The swap lets go of its held picture on that head too, or a move to a big document waits out the whole parse.
        if (step.expect === "partial" && !root.atContent.look)
            root.fail("step " + n + " held the swap while the head was drawn")
        // A too-deep document is refused on the UI thread from its head, and only a screenful of its Source is laid out.
        if (step.expect === "deep" && (!d.tooDeep || d.parsedOffThread || root.maxSourceChars === 0 || root.maxSourceChars > root.firstScreenChunks * Markdown.SOURCE_CHUNK_CHARS))
            root.fail("step " + n + " deep=" + d.tooDeep + " offthread=" + d.parsedOffThread + " laid out up to " + root.maxSourceChars + " Source characters")
    }

    // The next step is a move on the open card, or a second Space closes, the same real key.
    function leave() {
        root.stage = 3
        root.stageAt = Date.now()
        var after = root.steps[root.step + 1]
        if (after && after.via === "move") { root.step++; root.stage = 1; root.quiet = 0; root.stageAt = Date.now(); return }
        root.keys.keyClick(Qt.Key_Space, Qt.NoModifier, -1)
    }

    Timer {
        interval: root.pollMs
        repeat: true
        running: true
        onTriggered: {
            if (Date.now() - root.stageAt > root.watchdogMs) {
                root.fail("stage " + root.stage + " stalled in step " + (root.step + 1) + " reads=" + (root.prepare ? root.prepare.reads : -1)
                    + " prepared=" + (root.prepare ? root.prepare.preparedPath : "") + " quiet=" + root.quiet)
                root.finish()
                return
            }
            var pane = root.pane()
            // The first poll that finds the prepare holds it, long before a listing and its rest can complete.
            if (root.stage === 0 && pane && root.pv() && root.forcedClass !== "" && !root.prepare) {
                var held = root.find(root.pv(), "QuickLookPrepare")
                if (held) { held.resting = false; root.prepare = held }
            }
            if (root.stage === 0) {
                if (!pane || pane.listInFlight || pane.listingState !== "ready" || pane.total < 2 || !pane.storageKnown) return
                if (!root.unitsReady()) return
                root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", pane.listArea)
                root.prepare = root.prepare || root.find(root.pv(), "QuickLookPrepare")
                if (!root.prepare) { root.fail("the preview has no QuickLookPrepare"); root.finish(); return }
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
                var open = root.pv().active
                // A move keeps the card open on the previous file; any other step starts from a closed card with the cursor on its file.
                if (step.via === "move" ? !open : open) { root.quiet = 0; return }
                var row = pane.rowFor(pane.cursorIndex)
                if (step.via !== "move" && (!row || row.n !== step.name)) {
                    // A capped or rest step's row says 900 bytes, as a listing does for a file that grew since, so only the file's own type can refuse it.
                    if (step.expect === "capped" || step.expect === "rest") pane.rowFor(root.indexOf(step.name)).s = 900
                    pane.cursorIndex = root.indexOf(step.name)
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
