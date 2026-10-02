//@ pragma ShellId flea-preview-decode-test

import Quickshell
import QtQuick
import Quickshell.Io

// tests/preview-decode.sh's harness: the real SelectionPreview swept and rested over a stub pane, then the real PreviewImage.
ShellRoot {
    id: shell

    readonly property string uiDir: Quickshell.env("PREVIEW_UI")
    readonly property string photoDir: Quickshell.env("PREVIEW_PHOTOS")
    readonly property int sweepCount: 50
    readonly property int restRow: 51

    property int movesLeft: 0
    // The interim phase's expected original size, read by the meta stub when Quick Look asks.
    property var metaWH: [640, 480]
    property string interimPhase: ""
    property string interimOrig: ""
    property string interimCache: ""
    property string pendingInterim: ""
    // The interim phase's cursor row, naming the shown file the way production always does.
    property int interimRowOverride: -1
    // e81f-r3 guard overrides: guardMap names drifted rows, guardAskLog every ask, guardHold parks replies.
    property var guardMap: ({})
    property var guardAskLog: []
    property bool guardHold: false

    function log(line) { console.log("PREVIEW " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    // Sentinel handshake: touch runs as a Process so CREATE lands before the next open.
    Process {
        id: markProc
        property string touchName: ""
        command: ["touch", shell.photoDir + "/sentinel-" + touchName]
        onExited: function(exitCode) {
            if (exitCode !== 0) { shell.log("FAIL marker " + touchName); shell.quit(); return }
            shell.onMarkDone(touchName)
        }
    }
    function onMarkDone(name) {
        if (name === "sweep") { shell.log("SWEEP START"); shell.movesLeft = shell.sweepCount; moveTimer.restart() }
        else if (name === "rest") {
            stub.cursorIndex = shell.restRow
            shell.log("REST START")
            restPoll.restart()
        }
        else if (name === "done") {
            shell.log("DONE")
            quickLook.active = true
            shell.lookAt("portrait", shell.photoDir + "/portrait.jpg")
        }
        else if (name === "istart-held" || name === "istart-heldbad") { heldKick.restart() }
        else if (name.indexOf("istart-") === 0) { shell.openAfterMark() }
        else if (name === "iend-small") { shell.beginInterim("large", "seed0.jpg", "thumb.png", 640, 480) }
        else if (name === "iend-large") { shell.beginHeld("held", "big.png", "smallcache.png", 6016, 3900) }
        else if (name === "iend-held") { shell.beginHeld("heldbad", "big2.png", "missing-cache.png", 6016, 3900) }
        else if (name === "iend-heldbad") { shell.runGuards() }
    }
    function openAfterMark() {
        quickPreview.item.open(shell.photoDir + "/" + shell.interimOrig, "image-x-generic", 1000, "", shell.photoDir + "/" + shell.interimCache)
        interimPoll.waited = 0
        interimPoll.restart()
    }

    // Backend row shape: text start row, fifty sweep photos, big PNG rest row, interim override names shown file.
    function rowFor(i) {
        if (shell.guardMap.hasOwnProperty(i))
            return { n: shell.guardMap[i], d: false, t: true, s: 1000, m: 1000, p: 33188, i: "image-x-generic" }
        if (i === shell.interimRowOverride && shell.interimOrig !== "")
            return { n: shell.interimOrig, d: false, t: true, s: 1000, m: 1000, p: 33188, i: "image-x-generic" }
        if (i < 0 || i > shell.restRow) return null
        if (i === 0) return { n: "note.txt", d: false, t: false, s: 64, m: 1000, p: 33188, i: "text-x-generic" }
        if (i === shell.restRow) return { n: "big.png", d: false, t: true, s: 2000000, m: 1051, p: 33188, i: "image-x-generic" }
        return { n: "s" + (i - 1) + ".jpg", d: false, t: true, s: 100000 + i, m: 1000 + i, p: 33188, i: "image-x-generic" }
    }

    // The stub backend answers meta for every row and asks for no thumbnail, since every row already has one.
    Item {
        id: stubBackend
        signal metaResult(var message)
        signal meta(int row, int w, int h, int orient)
        property int nextToken: 0
        property var pending: []
        property var thumbCalls: []
        function askMeta(index, text, media, archive) {
            shell.guardAskLog.push(index)
            nextToken += 1
            pending.push({ token: nextToken, index: index })
            metaTimer.restart()
            return nextToken
        }
        function thumb(rows) { thumbCalls.push(rows) }
    }

    // Local disk answers in milliseconds, so a settled selection is never left waiting on a reply.
    Timer {
        id: metaTimer
        interval: 5
        onTriggered: {
            if (shell.guardHold) return
            for (var i = 0; i < stubBackend.pending.length; i++) {
                var req = stubBackend.pending[i]
                var big = req.index === shell.restRow
                stubBackend.metaResult({ token: req.token, w: big ? 6016 : shell.metaWH[0], h: big ? 3900 : shell.metaWH[1] })
                stubBackend.meta(req.index, big ? 6016 : shell.metaWH[0], big ? 3900 : shell.metaWH[1], 1)
            }
            stubBackend.pending = []
        }
    }

    // The stub pane says local btrfs, so a rule that read originals on a local disk would fire here.
    Item {
        id: stub
        property int cursorIndex: -1
        property string path: ""
        property int settleMs: 120
        property var thumbState: ({ file: {} })
        property string fsPath: ""
        property string fsName: "btrfs"
        // The fsinfo line has named the class, and "" is local, which ui/Pane.qml holds unknown until it lands.
        property string storageClass: ""
        property bool storageKnown: true
        property bool listInFlight: false
        property var kindNames: []
        property var preview: ({ active: false })
        property var backend: stubBackend
        signal rowsChanged()
        signal selectionVersionChanged()
        function rowFor(i) { return shell.rowFor(i) }
        function join(base, name) { return base + "/" + name }
        function selectionCount() { return 1 }
        function selectedIndices() { return [stub.cursorIndex] }
    }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 600
        color: "#303030"

        Rectangle {
            id: host
            color: "#101315"
            x: 20
            y: 20
            width: 760
            height: 560

            Loader {
                id: loader
                anchors.fill: parent
                source: "file://" + shell.uiDir + "/SelectionPreview.qml"
                onLoaded: {
                    item.pane = stub
                    shell.begin()
                }
                onStatusChanged: if (status === Loader.Error) { shell.log("FAIL the preview did not load"); shell.quit() }
            }
        }

        // Quick Look's box on this test, the Columns frame's own 754x471, loaded only after the column's windows close.
        Loader {
            id: quickLook
            x: 20
            y: 20
            width: 754
            height: 471
            active: false
            source: "file://" + shell.uiDir + "/PreviewImage.qml"
            onStatusChanged: if (status === Loader.Error) { shell.log("FAIL Quick Look's image pane did not load"); shell.quit() }
        }

        // The production overlay, for the interim phase: the cached thumbnail under the full decode.
        Loader {
            id: quickPreview
            x: 20
            y: 20
            width: 754
            height: 471
            active: false
            source: "file://" + shell.uiDir + "/Preview.qml"
            onLoaded: {
                item.pane = stub
                if (shell.pendingInterim !== "") shell.openInterim()
            }
            onStatusChanged: if (status === Loader.Error) { shell.log("FAIL Quick Look did not load"); shell.quit() }
        }
    }

    // Every row pre-thumbnailed, so a load during the sweep opens its cache file and the sweep window counts it.
    function begin() {
        stub.path = shell.photoDir
        stub.fsPath = shell.photoDir
        var files = {}
        for (var i = 1; i < shell.restRow; i++) files[i] = shell.photoDir + "/t" + (i - 1) + ".png"
        files[shell.restRow] = shell.photoDir + "/t50.png"
        stub.thumbState = ({ file: files })
        stub.cursorIndex = 0
        shell.log("READY pid=" + Quickshell.processId)
        settleTimer.restart()
    }

    Timer {
        id: settleTimer
        interval: 400
        // Text row loaded, so sweep window opens on sweep alone; touch handshake orders CREATE first.
        onTriggered: { markProc.touchName = "sweep"; markProc.running = true }
    }

    // Fifty cursor moves at key-repeat rate: the first loads at once after idle, the rest trail one settle.
    Timer {
        id: moveTimer
        interval: 30
        repeat: true
        onTriggered: {
            stub.cursorIndex = shell.sweepCount + 1 - shell.movesLeft
            shell.movesLeft -= 1
            if (shell.movesLeft <= 0) {
                stop()
                shell.log("SWEEP END")
                markProc.touchName = "rest"
                markProc.running = true
            }
        }
    }

    // The rest has loaded once the column holds a path; whatever it opens is what the done window counts.
    Timer {
        id: restPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            if (loader.item.path !== "") {
                stop()
                shell.log("RESTED")
                doneTimer.restart()
            } else if (waited > 1000) {
                stop()
                shell.log("FAIL the rest never loaded")
                shell.quit()
            }
        }
    }

    // Two seconds, longer than the 0.3.5 candidate's 580 ms sharp decode, then Quick Look's half.
    Timer {
        id: doneTimer
        interval: 2000
        onTriggered: {
            markProc.touchName = "done"
            markProc.running = true
        }
    }

    // Final picture finder: only it sets autoTransform true, interim leaves false.
    function picture() {
        var kids = quickLook.item ? quickLook.item.children : []
        for (var i = 0; i < kids.length; i++)
            if (kids[i].autoTransform === true) return kids[i]
        return null
    }

    property string looking: ""
    property string lookingName: ""
    function lookAt(label, path) {
        shell.looking = label
        shell.lookingName = path.substring(path.lastIndexOf("/") + 1)
        quickLook.item.path = path
        lookPoll.waited = 0
        lookPoll.restart()
    }

    // Sample log line: "PREVIEW QL portrait decoded=400x600 drawn=314x471", the turned photo decoded whole and upright, drawn at the exact fit.
    Timer {
        id: lookPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            var img = shell.picture()
            // The source check keeps the portrait's Ready from answering for the small PNG.
            if (quickLook.item && quickLook.item.status === "image" && img && String(img.source).endsWith("/" + shell.lookingName)) {
                stop()
                shell.log("QL " + shell.looking + " decoded=" + img.implicitWidth + "x" + img.implicitHeight
                          + " drawn=" + Math.round(img.width) + "x" + Math.round(img.height))
                if (shell.looking === "portrait") shell.lookAt("banner", shell.photoDir + "/banner.png")
                else if (shell.looking === "banner") shell.lookAt("small", shell.photoDir + "/small.png")
                else shell.beginInterim("small", "small.png", "smallcache.png", 120, 68)
            } else if (waited > 5000) {
                stop()
                shell.log("FAIL Quick Look never drew " + shell.looking + " (status " + (quickLook.item ? quickLook.item.status : "none") + ")")
                shell.quit()
            }
        }
    }

    // Interim opens the production overlay the way Space does: cache under full decode, each once.
    function beginInterim(label, orig, cache, w, h) {
        shell.interimPhase = label
        shell.interimOrig = orig
        shell.interimCache = cache
        shell.metaWH = [w, h]
        shell.interimRowOverride = 7
        stub.cursorIndex = 7
        shell.pendingInterim = label
        if (quickPreview.status === Loader.Ready) shell.openInterim()
        else quickPreview.active = true
    }

    function openInterim() {
        shell.pendingInterim = ""
        // Touch handshake queues CREATE before the open, so the count window holds every open.
        markProc.touchName = "istart-" + shell.interimPhase
        markProc.running = true
    }

    function findAll(item, out) {
        var kids = item ? item.children : []
        for (var i = 0; i < kids.length; i++) {
            out.push(kids[i])
            shell.findAll(kids[i], out)
        }
        return out
    }

    // Interim/final finder: interim keeps autoTransform false, final sets true, sources differ.
    function interimPair() {
        var all = shell.findAll(quickPreview.item, [])
        var inter = null, final = null
        for (var i = 0; i < all.length; i++) {
            var src = String(all[i].source || "")
            if (all[i].autoTransform !== undefined && src.endsWith("/" + shell.interimOrig)) final = all[i]
            else if (src.endsWith("/" + shell.interimCache)) inter = all[i]
        }
        return [inter, final]
    }

    function geom(item) {
        return Math.round(item.x) + "," + Math.round(item.y) + "," + Math.round(item.width) + "," + Math.round(item.height)
    }

    // The interim sits above the ground and below the final picture as siblings.
    function stackOk() {
        var pair = shell.interimPair()
        if (!pair[0] || !pair[1] || pair[0].parent !== pair[1].parent) return false
        var kids = pair[0].parent.children
        var gi = -1, ii = -1, fi = -1
        for (var i = 0; i < kids.length; i++) {
            if (kids[i] === pair[0]) ii = i
            else if (kids[i] === pair[1]) fi = i
            else if (gi < 0 && kids[i].source === undefined && kids[i].color !== undefined) gi = i
        }
        return gi >= 0 && gi < ii && ii < fi && kids[gi].z === pair[0].z && pair[0].z === pair[1].z
    }

    // Sample log line: "PREVIEW INTERIM small irect=317,201,120,68 frect=317,201,120,68".
    Timer {
        id: interimPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            var pair = shell.interimPair()
            var done = quickPreview.item && quickPreview.item.status === "image" && quickPreview.item.imageW > 0
                && pair[0] && pair[0].status === Image.Ready && pair[1]
            if (done) {
                stop()
                shell.log("INTERIM " + shell.interimPhase + " irect=" + shell.geom(pair[0]) + " frect=" + shell.geom(pair[1]))
                shell.log("INTERIMSTACK " + shell.interimPhase + " " + (shell.stackOk() ? "ok" : "bad"))
                markProc.touchName = "iend-" + shell.interimPhase
                markProc.running = true
            } else if (waited > 8000) {
                stop()
                shell.log("FAIL the interim never settled for " + shell.interimPhase)
                shell.quit()
            }
        }
    }

    // The held phase opens the production overlay with a slow original, so the interim settles while the final still decodes.
    function beginHeld(label, orig, cache, w, h) {
        shell.interimPhase = label
        shell.interimOrig = orig
        shell.interimCache = cache
        shell.metaWH = [w, h]
        shell.interimRowOverride = 7
        stub.cursorIndex = 7
        if (quickPreview.status !== Loader.Ready) {
            shell.log("FAIL Quick Look left before the held phase")
            shell.quit()
            return
        }
        markProc.touchName = "istart-" + label
        markProc.running = true
    }
    // After the touch handshake, so the CREATE lands first and the open meets a settled loader.
    Timer {
        id: heldKick
        interval: 100
        repeat: false
        onTriggered: {
            quickPreview.item.open(shell.photoDir + "/" + shell.interimOrig, "image-x-generic",
                1000, "", shell.photoDir + "/" + shell.interimCache)
            heldPoll.waited = 0
            heldPoll.restart()
        }
    }

    // Sample log line: "PREVIEW HELD held shown=true ready=true status=loading", sampled while the final still decodes.
    Timer {
        id: heldPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            var qp = quickPreview.item
            var pair = shell.interimPair()
            var settled = pair[0] && (pair[0].status === Image.Ready || pair[0].status === Image.Error)
            if (qp && pair[0] && pair[1] && qp.imageW > 0 && qp.status === "loading" && settled) {
                stop()
                shell.log("HELD " + shell.interimPhase + " shown=" + qp.interimShown + " ready=" + qp.lookReady + " status=" + qp.status)
                markProc.touchName = "iend-" + shell.interimPhase
                markProc.running = true
            } else if (waited > 8000) {
                stop()
                shell.log("FAIL the held phase never settled for " + shell.interimPhase)
                shell.quit()
            }
        }
    }

    // e81f-r3: guards 1 to 4 pin the drifted reply, the cursor re-ask, the quiet no-match and capture-first.
    function guardShow(shown, row) {
        stubBackend.pending = []
        shell.guardAskLog = []
        quickPreview.item.show(shell.photoDir + "/" + shown, "image-x-generic",
            1000, "", shell.photoDir + "/smallcache.png", row)
    }
    function guardEnd() {
        stubBackend.pending = []
        metaTimer.stop()
    }
    function runGuards() {
        shell.guardHold = true
        // Guard 1: reply-time drift. Row 7 names guard1.jpg at the ask; an insert
        // above it moves s6.jpg there before the held reply lands with other sizes.
        shell.guardMap = ({ 7: "guard1.jpg" })
        stub.cursorIndex = 7
        shell.guardShow("guard1.jpg", 7)
        var g1asked = shell.guardAskLog.length === 1 && shell.guardAskLog[0] === 7
        shell.guardMap = ({ 7: "s6.jpg" })
        stubBackend.meta(7, 999, 888, 1)
        var g1kept = quickPreview.item.imageW === 0 && quickPreview.item.imageH === 0
        shell.log("GUARD1 " + (g1asked && g1kept ? "PASS" : "FAIL")
            + " asked7=" + g1asked + " kept=" + g1kept
            + " w=" + quickPreview.item.imageW + " h=" + quickPreview.item.imageH)
        shell.guardEnd()
        // Guard 2 asks at cursor row 3 while shown row 7 names s6.jpg, taking row 3 reply.
        shell.guardMap = ({ 7: "s6.jpg", 3: "guard2.jpg" })
        stub.cursorIndex = 3
        shell.guardShow("guard2.jpg", 7)
        var g2asked = shell.guardAskLog.length === 1 && shell.guardAskLog[0] === 3
        stubBackend.meta(3, 321, 222, 1)
        var g2took = quickPreview.item.imageW === 321 && quickPreview.item.imageH === 222
        shell.log("GUARD2 " + (g2asked && g2took ? "PASS" : "FAIL")
            + " asked3=" + g2asked + " took=" + g2took
            + " w=" + quickPreview.item.imageW + " h=" + quickPreview.item.imageH)
        shell.guardEnd()
        // Guard 3 asks nothing when neither shown row 7 nor cursor row 5 names ghost.jpg.
        shell.guardMap = ({ 7: "s6.jpg", 5: "s4.jpg" })
        stub.cursorIndex = 5
        shell.guardShow("ghost.jpg", 7)
        var g3quiet = shell.guardAskLog.length === 0
        var g3dropped = quickPreview.item.imageRow === -1
        var g3bare = quickPreview.item.imageW === 0 && quickPreview.item.imageH === 0
        shell.log("GUARD3 " + (g3quiet && g3dropped && g3bare ? "PASS" : "FAIL")
            + " quiet=" + g3quiet + " dropped=" + g3dropped + " bare=" + g3bare)
        shell.guardEnd()
        // Guard 4: capture-first. Row 7 names the shown file while cursor 3 names another.
        shell.guardMap = ({ 7: "guard4.jpg", 3: "other4.jpg" })
        stub.cursorIndex = 3
        shell.guardShow("guard4.jpg", 7)
        var g4asked = shell.guardAskLog.length === 1 && shell.guardAskLog[0] === 7
        stubBackend.meta(7, 444, 333, 1)
        var g4took = quickPreview.item.imageW === 444 && quickPreview.item.imageH === 333
        shell.log("GUARD4 " + (g4asked && g4took ? "PASS" : "FAIL")
            + " asked7=" + g4asked + " took=" + g4took
            + " w=" + quickPreview.item.imageW + " h=" + quickPreview.item.imageH)
        shell.guardEnd()
        shell.guardHold = false
        shell.guardMap = ({})
        stub.cursorIndex = shell.restRow
        quitTimer.restart()
    }

    Timer {
        id: quitTimer
        interval: 500
        onTriggered: shell.quit()
    }
}
