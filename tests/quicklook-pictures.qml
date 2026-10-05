import QtQuick
import Quickshell
import "flea" as Flea

// QuickLookPrepare holds only the pictures under its document's folder, one sizer at a time, and nothing a move or a stale reply leaves behind.
ShellRoot {
    id: root
    readonly property string dir: Quickshell.env("FLEA_PREVIEW_HUNT_PICS") + "/docs"
    // One document with one picture beside it, shown at every cursor index so a move re-prepares it.
    readonly property var names: ["in.md", "in.md", "in.md"]
    // Polls of the probe timer an event may take before it fails by name; counted, never timed.
    readonly property int landPollLimit: 300
    readonly property int tickMs: 20
    property int failures: 0
    property int checks: 0
    property int step: 0
    property int waited: 0

    function check(label, actual, expected) {
        checks++
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) failures++
        console.log("PREVIEW_HUNT " + (ok ? "PASS " : "FAIL ") + label + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    function finish() {
        console.log("PREVIEW_HUNT DONE " + checks + " checks, " + failures + " failed")
        Qt.exit(failures ? 1 : 0)
    }
    function landedWithin(name, ready) {
        if (ready) {
            root.waited = 0
            return true
        }
        if (++root.waited > root.landPollLimit) {
            root.check(name + " lands within " + root.landPollLimit + " polls", "gave up " + JSON.stringify(root.state()), "landed")
            root.finish()
        }
        return false
    }
    function state() {
        return { reads: prep.reads, bytes: prep.readBytes, answers: prep.workerAnswers, prepared: prep.preparedPath, pictures: prep.pictures.length, settled: prep.picturesSettled }
    }
    function preparedAll(path) { return prep.preparedPath === path && prep.picturesSettled && !prep.sizer }

    QtObject {
        id: stub
        property int cursorIndex: 0
        property var rows: []
        property bool listInFlight: false
        property bool storageKnown: true
        property string storageClass: ""
        property string path: root.dir
        function rowFor(i) { return { n: root.names[i], d: false, s: 900, p: 33188, k: 0 } }
        function join(a, b) { return a + "/" + b }
    }
    Flea.QuickLookPrepare {
        id: prep
        pane: stub
        restMs: 1
    }

    Timer {
        interval: root.tickMs
        running: true
        repeat: true
        onTriggered: {
            var inside = "file://" + root.dir + "/img/pixel.png"
            if (root.step === 0) {
                stub.cursorIndex = 1
                root.step = 1
            } else if (root.step === 1) {
                if (!root.landedWithin("the document's picture", root.preparedAll(root.dir + "/in.md") && prep.pictures.length > 0)) return
                root.check("the picture under the folder is held", prep.pictures, [inside])
                root.check("one sizer was started for the document", prep.sizersStarted, 1)
                stub.cursorIndex = 2
                root.check("a move empties the held pictures", prep.pictures, [])
                // A reply sized for the cursor before the move holds nothing.
                prep.sized(prep.seq - 1, [inside], "70\t" + root.dir + "/img/pixel.png\n")
                root.check("a stale sizer reply holds nothing", prep.pictures, [])
                root.step = 2
            } else if (root.step === 2) {
                if (!root.landedWithin("the picture after the move", prep.reads === 2 && root.preparedAll(root.dir + "/in.md") && prep.pictures.length === 1)) return
                // The parser keeps a document's pictures in its folder; the prefetch holds that line itself for a block list from anywhere.
                var away = [{ type: "image", url: "file://" + root.dir + "/../outside/pixel.png" }, { type: "image", url: "file:///mnt/nas/a.png" }]
                prep.startPictures(away, root.dir)
                root.check("pictures outside the folder start no sizer", [prep.sizersStarted, prep.sizersAlive], [2, 0])
                // Two rests in a row, as a cursor that moves and rests again: the first sizer must not outlive the second.
                prep.startPictures([{ type: "image", url: inside }], root.dir)
                prep.startPictures([{ type: "image", url: inside }], root.dir)
                root.check("each rest starts a sizer", prep.sizersStarted, 4)
                root.step = 3
            } else if (root.step === 3) {
                if (!root.landedWithin("the second sizer's answer", !prep.sizer && prep.picturesSettled && prep.pictures.length === 1)) return
                root.check("no sizer outlives the answer", prep.sizersAlive, 0)
                root.finish()
            }
        }
    }
}
