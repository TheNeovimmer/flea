//@ pragma ShellId flea-preview-settle-test

import QtQuick
import Quickshell
import "flea" as Flea

// Production previews use the real 120ms timer; count backend asks and loads in automatic and seeded manual modes.
ShellRoot {
    id: root

    property var failures: []
    property int stage: 0
    property int metaMark: 0
    // A backdated duplicate tells same apart from a re-arm without reading the clock.
    property int duplicateBackdateMs: 60
    property int pollWant: -2
    property int pollNext: -1
    property int qlLoads: 0
    property var flow: []
    property bool manual: Quickshell.env("FLEA_PREVIEWSETTLE_MANUAL") === "1"
    // e80q: the held Quick Look move's pre-landing path and mid-frame count.
    property string qlOld: ""
    property int qlMid0: 0

    function buildRows() {
        var rows = []
        for (var i = 0; i < 8; i++)
            rows.push({ n: "img" + i + ".jpg", d: false, i: "image-x-generic", p: 420,
                s: 1000 + i, m: 1758835200 + i, t: true, k: 0 })
        return rows
    }

    function imagePath(index) { return pane.join(pane.path, "img" + index + ".jpg") }

    function check(name, cond, detail) {
        if (!cond)
            failures.push(name)
        console.log("PREVIEWSETTLE " + (cond ? "PASS" : "FAIL") + " " + name
            + " meta=" + backend.metaCalls + " loaded=" + preview.loadedIndex
            + " canRead=" + preview.canRead + " visible=" + preview.visible
            + " automatic=" + Flea.ViewState.previewAutomatic + " storage=" + pane.storageClass
            + " known=" + pane.storageKnown + (detail ? " " + detail : ""))
    }

    function step(index) {
        pane.cursorIndex = index
        preview.followSelection()
    }

    function later(ms) {
        waiter.interval = ms
        waiter.restart()
    }

    function go(next) {
        root.stage = next
        root.flow[next]()
    }

    function pollFor(want, timeoutMs, next) {
        root.pollWant = want
        root.pollNext = next
        poller.deadline = Date.now() + timeoutMs
        poller.start()
    }

    function done() {
        var line = "PREVIEWSETTLE DONE failures=" + root.failures.length
        for (var i = 0; i < root.failures.length; i++)
            line += " [" + root.failures[i] + "]"
        console.log(line)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    QtObject {
        id: backend
        property int metaCalls: 0
        property int thumbCalls: 0
        property int token: 0
        signal metaResult(var message)
        signal meta(int row, int w, int h, int orient, real durationMs, int sampleRate,
            int entries, real unpacked, bool archiveFailed, var names, real lines,
            bool partial, bool linesFailed, string target, bool targetDir, string owner)
        function askMeta(index, wantText, wantMedia, wantArchive) {
            metaCalls += 1
            token += 1
            return token
        }
        function thumb(ask, cacheOnly) { thumbCalls += 1 }
        function thumbcancel(rows) {}
    }

    QtObject {
        id: swap
        property bool fellBack: false
        property bool capturing: false
        property var order: []
        property var queue: []
        property int starts: 0
        function hold(apply, key, atWork) {
            order.push(atWork === true ? "load" : "clear")
            if (capturing) {
                if (apply)
                    queue.push(apply)
            } else if (apply) {
                apply()
            }
        }
        function start(isPdf) { starts += 1 }
        function release() {
            var pending = queue
            queue = []
            for (var i = 0; i < pending.length; i++)
                pending[i]()
        }
        function reset() {
            order = []
            queue = []
            starts = 0
        }
    }

    QtObject {
        id: pane
        property string path: Quickshell.env("FLEA_PREVIEWSETTLE_DIR")
        property int cursorIndex: -1
        property int selectionVersion: 0
        property var rows: root.buildRows()
        property var kindNames: ({ 0: "" })
        property int settleMs: 120
        property bool storageKnown: true
        property string storageClass: "local"
        property bool listInFlight: false
        property var thumbState: ({ file: {}, order: [] })
        property var backend: backend
        property var listArea: ({ forceActiveFocus: function () {} })
        function rowFor(index) { return (index >= 0 && index < rows.length) ? rows[index] : null }
        function join(path, name) { return path + "/" + name }
        function selectionCount() { return 1 }
        function selectedIndices() { return [cursorIndex] }
    }

    // A real window gives SelectionPreview the effective visibility it has in the product.
    Window {
        visible: true
        width: 800
        height: 600

        Flea.SelectionPreview {
            id: preview
            width: 800
            height: 600
            pane: pane
            swap: swap
        }
    }

    // Quick Look in its own window, so its swap is visible and takes a picture offscreen.
    Window {
        visible: true
        width: 800
        height: 600

        Flea.Preview {
            id: quick
            width: 800
            height: 600
            pane: pane
            onPathChanged: root.qlLoads += 1
        }
    }

    Timer {
        id: waiter
        repeat: false
        onTriggered: root.go(root.stage + 1)
    }

    Timer {
        id: poller
        interval: 10
        repeat: true
        property double deadline: 0
        onTriggered: {
            if (preview.loadedIndex === root.pollWant) {
                poller.stop()
                root.go(root.pollNext)
            } else if (Date.now() > poller.deadline) {
                poller.stop()
                root.failures.push("timeout waiting for loaded " + root.pollWant)
                root.done()
            }
        }
    }

    Timer {
        id: qpoll
        interval: 10
        repeat: true
        property double deadline: 0
        property string want: ""
        onTriggered: {
            if (quick.path === qpoll.want) {
                qpoll.stop()
                root.go(root.stage + 1)
            } else if (Date.now() > qpoll.deadline) {
                qpoll.stop()
                root.failures.push("timeout waiting for quick path " + qpoll.want)
                root.done()
            }
        }
    }

    function qpollFor(want, timeoutMs) {
        qpoll.want = want
        qpoll.deadline = Date.now() + timeoutMs
        qpoll.start()
    }

    property var autoStages: [
        function () { root.later(200) },
        function () {
            root.check("startup sends no backend work", backend.metaCalls === 0 && backend.thumbCalls === 0)
            root.step(1)
            root.check("idle first move loads synchronously", preview.loadedIndex === 1 && backend.metaCalls === 1)
            root.later(200)
        },
        function () {
            root.step(2)
            root.check("idle second move loads at once", preview.loadedIndex === 2 && backend.metaCalls === 2)
            root.step(3)
            root.check("burst holds first repeat", backend.metaCalls === 2)
            root.step(4)
            root.check("burst holds second repeat", backend.metaCalls === 2)
            root.step(5)
            root.check("burst holds third repeat", backend.metaCalls === 2)
            root.later(300)
        },
        function () {
            root.check("burst lands one trailing load", backend.metaCalls === 3 && preview.loadedIndex === 5)
            root.check("trailing load names the final row", preview.loadedDirectory === pane.path
                && preview.loadedIdentity === JSON.stringify(["img5.jpg", 1005, 1758835205, 420, "image-x-generic"]))
            root.later(200)
        },
        function () {
            root.step(6)
            root.check("post-burst idle move loads at once", preview.loadedIndex === 6 && backend.metaCalls === 4)
            root.metaMark = backend.metaCalls
            root.step(7)
            root.check("rapid move trails", backend.metaCalls === root.metaMark)
            var heldAt = preview.lastMoveAt - root.duplicateBackdateMs
            preview.lastMoveAt = heldAt
            // The settle Timer is the one Timer under preview; its root type declares none.
            var settleTimer = null
            var timers = 0
            for (var i = 0; i < preview.resources.length; i++) {
                if (preview.resources[i] instanceof Timer) {
                    timers += 1
                    settleTimer = preview.resources[i]
                }
            }
            var settleRestarts = 0
            var counted = function () {
                settleRestarts += 1
            }
            if (timers === 1) {
                settleTimer.runningChanged.connect(counted)
            }
            root.step(7)
            if (timers === 1) {
                settleTimer.runningChanged.disconnect(counted)
            }
            root.check("duplicate moves no second arm", backend.metaCalls === root.metaMark
                && preview.lastMoveKey === pane.path + "\n7" && preview.lastMoveAt === heldAt && settleRestarts === 0
                && timers === 1, "timers=" + timers)
            root.pollFor(7, 400, root.stage + 1)
        },
        function () {
            root.check("duplicate lands one trailing load", backend.metaCalls === root.metaMark + 1)
            pane.storageClass = "network"
            root.later(150)
        },
        function () {
            root.metaMark = backend.metaCalls
            root.step(0)
            root.check("off class holds with no decode", backend.metaCalls === root.metaMark
                && preview.manualHold === true && preview.loadedIndex === 0)
            pane.storageClass = "local"
            pane.storageKnown = false
            root.later(150)
        },
        function () {
            root.metaMark = backend.metaCalls
            swap.reset()
            root.step(1)
            root.check("unknown class waits on the swap cap", backend.metaCalls === root.metaMark && swap.starts === 1)
            pane.storageKnown = true
            root.later(250)
        },
        function () {
            root.check("class landing loads the cursor row", preview.loadedIndex === 1)
            root.metaMark = backend.metaCalls
            preview.visible = false
            root.step(2)
            preview.followSelection()
            root.check("hidden preview does no work", backend.metaCalls === root.metaMark)
            preview.visible = true
            root.check("unhidden preview loads at once", preview.loadedIndex === 2
                && backend.metaCalls === root.metaMark + 1)
            root.later(150)
        },
        function () {
            swap.reset()
            swap.capturing = true
            root.later(200)
        },
        function () {
            root.metaMark = backend.metaCalls
            root.step(3)
            root.check("picture hold runs before the load", swap.order.join(",") === "clear,load")
            root.check("capturing queues both callbacks", swap.queue.length === 2
                && backend.metaCalls === root.metaMark && preview.loadedIndex === 2)
            swap.release()
            root.check("released queue lands the move", preview.loadedIndex === 3
                && backend.metaCalls === root.metaMark + 1)
            swap.capturing = false
            root.later(150)
        },
        function () {
            var touched = pane.rows.slice()
            touched[3] = Object.assign({}, touched[3], { s: touched[3].s + 1, m: touched[3].m + 1 })
            root.metaMark = backend.metaCalls
            pane.rows = touched
            root.check("same-index identity refresh reloads", backend.metaCalls === root.metaMark + 1
                && preview.loadedIndex === 3 && preview.loadedIdentity === preview.identity(pane.rowFor(3)))
            root.later(150)
        },
        function () {
            root.metaMark = backend.metaCalls
            preview.visible = false
            preview.visible = true
            root.check("same-target hide and show restores", preview.loadedIndex === 3
                && backend.metaCalls === root.metaMark + 1 && preview.pending === false)
            root.later(150)
        },
        function () {
            root.metaMark = backend.metaCalls
            preview.followSelection()
            root.check("settled duplicate keeps showing", backend.metaCalls === root.metaMark
                && preview.loadedIndex === 3 && preview.pending === false)
            root.later(150)
        },
        function () {
            preview.swap = null
            root.later(200)
        },
        function () {
            root.metaMark = backend.metaCalls
            root.step(4)
            root.check("no-swap idle move loads at once", preview.loadedIndex === 4
                && backend.metaCalls === root.metaMark + 1)
            root.step(5)
            root.check("no-swap rapid move trails", backend.metaCalls === root.metaMark + 1)
            root.later(300)
        },
        function () {
            root.check("no-swap trailing load lands", preview.loadedIndex === 5
                && backend.metaCalls === root.metaMark + 2)
            root.later(200)
        },
        function () {
            var touched = pane.rows.slice()
            touched[5] = Object.assign({}, touched[5], { s: touched[5].s + 1, m: touched[5].m + 1 })
            root.metaMark = backend.metaCalls
            pane.rows = touched
            root.check("no-swap same-target refresh works", backend.metaCalls === root.metaMark + 1
                && preview.loadedIndex === 5 && preview.loadedIdentity === preview.identity(pane.rowFor(5)))
            root.later(200)
        },
        function () {
            quick.follow(root.imagePath(6), "image-x-generic", 1006, "")
            root.check("quick follow stages its pending row", quick.pendingPath === root.imagePath(6))
            root.qpollFor(root.imagePath(6), 3000)
        },
        function () {
            root.check("quick idle follow opens the row", quick.active && quick.path === root.imagePath(6))
            quick.lastMoveAt = Date.now()
            var loads = root.qlLoads
            quick.follow(root.imagePath(7), "image-x-generic", 1007, "")
            root.check("quick fresh move defers", quick.pendingPath === root.imagePath(7)
                && quick.path === root.imagePath(6) && root.qlLoads === loads)
            root.qpollFor(root.imagePath(7), 3000)
        },
        function () {
            root.check("quick trailing follow lands once", quick.path === root.imagePath(7) && root.qlLoads === 2)
            quick.lastMoveAt = Date.now()
            var loads = root.qlLoads
            quick.follow(root.imagePath(0), "image-x-generic", 1000, "")
            quick.follow(root.imagePath(0), "image-x-generic", 1000, "")
            root.check("quick duplicate stages once", quick.pendingPath === root.imagePath(0)
                && root.qlLoads === loads)
            root.qpollFor(root.imagePath(0), 3000)
        },
        function () {
            root.check("quick duplicate lands once", quick.path === root.imagePath(0) && root.qlLoads === 3)
            quick.close()
            root.check("close resets the move key", quick.lastMoveKey === "" && !quick.active)
            quick.follow(root.imagePath(1), "image-x-generic", 1001, "")
            root.qpollFor(root.imagePath(1), 3000)
        },
        function () {
            root.check("quick reopens the fresh row", quick.active && quick.path === root.imagePath(1)
                && quick.pendingPath === root.imagePath(1) && root.qlLoads === 4)
            root.qlOld = quick.path
            root.qlMid0 = quick.swapState().midFrames
            quick.lastMoveAt = 0
            var target = root.imagePath(2)
            quick.follow(target, "image-x-generic", 1002, "")
            root.check("quick held move captures before it starts",
                quick.swap && quick.swap.capturing === true && quick.swap.started === false,
                "capturing=" + (quick.swap && quick.swap.capturing) + " started=" + (quick.swap && quick.swap.started))
            root.check("quick held move keeps the old path until the capture lands",
                quick.path === root.qlOld, "path=" + quick.path)
            root.qpollFor(target, 3000)
        },
        function () {
            root.check("quick held move lands whole", quick.path === root.imagePath(2)
                && quick.swapState().midFrames === root.qlMid0,
                "mid=" + quick.swapState().midFrames + " mid0=" + root.qlMid0)
            root.done()
        }
    ]

    property var manualStages: [
        function () { root.later(200) },
        function () {
            root.check("manual startup sends no backend work", backend.metaCalls === 0)
            root.step(1)
            root.step(2)
            root.check("manual moves schedule nothing", backend.metaCalls === 0)
            preview.loadSelection()
            root.check("explicit load still works", backend.metaCalls === 1 && preview.loadedIndex === 2)
            root.done()
        }
    ]

    Component.onCompleted: {
        if (pane.path.length === 0 || pane.path.charAt(0) !== "/") {
            root.failures.push("runner image directory missing")
            root.done()
            return
        }
        root.flow = root.manual ? root.manualStages : root.autoStages
        root.go(0)
    }
}
