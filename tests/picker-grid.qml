//@ pragma ShellId flea-picker-grid-test

import QtQuick
import Quickshell
import "flea" as Flea

// The picker grid asks thumbnails for visible tiles only: unknown storage holds
// every ask, the first settle asks the first screen alone, and a scroll restarts
// the settle so newly visible tiles are asked and nothing else ever is. The
// listing worker answers the fsinfo ask the window sends when its listed line
// lands; without that ask storageKnown never flips and the grid stays iconic.
ShellRoot {
    id: root

    property var failures: []
    property int rowCount: 60
    property var asked: []
    property int stage: 0
    property double stageSince: 0
    property int screenLast: -1
    property int scrolledLast: -1
    property bool fsinfoSeen: false
    property string fsinfoClass: "?"

    function fail(text) { root.failures.push(text) }
    function buildRows() {
        var rows = []
        for (var i = 0; i < root.rowCount; i++)
            rows.push({ n: "photo" + i + ".jpg", d: false, i: "image-x-generic",
                        p: 33188, s: 20480, m: 1758835200, t: true, k: 0 })
        return rows
    }

    Component {
        id: backendStub
        QtObject {
            property int windowCalls: 0
            property var thumbAsks: []
            function window(start, count) { windowCalls += 1 }
            function thumb(rows, cacheOnly) { thumbAsks.push(rows.slice()) }
            function thumbcancel(rows) {}
        }
    }

    Component {
        id: pickerStub
        QtObject {
            property int total: 60
            property int held: 0
            property var rows: []
            property int cursorIndex: 0
            property var thumbState: ({ file: {}, order: [] })
            property bool backendUnavailable: false
            property int pendingListings: 0
            property bool recent: false
            property bool storageKnown: false
            property string storageClass: ""
            property string path: "/probe"
            property var marks: []
            property bool folderMode: false
            property int windowSize: 60
            function rowFor(index) {
                var at = index - held
                return at >= 0 && at < rows.length ? rows[at] : null
            }
            function stepFocus(item, back) {}
            function toggleMark(index) {}
            function setView(mode) {}
            function activate(index) {}
            function doubleActivate(index, rowPath, firstPath) {}
            function goUp() {}
            function goBack() {}
            function requestSort(order) {}
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubPicker: pickerStub.createObject(root, { rows: root.buildRows() })

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 500
        Flea.PickerGrid {
            id: grid
            width: 700
            height: 300
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            picker: root.stubPicker
            backend: root.stubBackend
        }
    }

    // The listing half: a real worker against a stub backend that answers listed
    // and, only when asked, one fsinfo line. The window asks on listed; here the
    // probe asks there too, so a worker with no fsinfo ask reddens this instead.
    Flea.PickerListing {
        id: listing
        onMessage: function (message) {
            if (message.t === "listed" && root.stage === 10 && !root.fsinfoAsked) {
                root.fsinfoAsked = true
                try {
                    listing.fsinfo()
                } catch (error) {
                    root.fail("the listing worker has no fsinfo ask: " + error)
                    root.report()
                }
            } else if (message.t === "fsinfo" && root.stage === 10) {
                root.fsinfoSeen = true
                root.fsinfoClass = message.class
                root.report()
            }
        }
    }
    property bool fsinfoAsked: false

    function flatAsks() {
        var out = []
        for (var i = 0; i < stubBackend.thumbAsks.length; i++)
            for (var j = 0; j < stubBackend.thumbAsks[i].length; j++)
                out.push(stubBackend.thumbAsks[i][j])
        return out
    }
    function inBounds(rows, lo, hi) {
        for (var i = 0; i < rows.length; i++)
            if (rows[i] < lo || rows[i] > hi) return false
        return true
    }

    Timer {
        interval: 10
        repeat: true
        running: true
        onTriggered: root.step()
    }
    Timer { interval: 30000; running: true; onTriggered: { root.fail("probe timed out"); root.report() } }

    function step() {
        if (root.failures.length > 0) { root.report(); return }
        switch (root.stage) {
        case 0: {
            // The window itself is never instantiated here, so compile it: a
            // broken onListed never reaches a running probe otherwise.
            var comp = Qt.createComponent("flea/PickerWindow.qml")
            if (comp.status !== Component.Ready) {
                root.fail("PickerWindow does not compile: " + comp.errorString())
                return
            }
            // Unknown storage holds: an ask now must plan nothing.
            grid.requestThumbs()
            if (stubBackend.thumbAsks.length !== 0) {
                root.fail("unknown storage asked " + stubBackend.thumbAsks.length + " thumb rows")
                return
            }
            root.stubPicker.storageKnown = true
            grid.primeSettle()
            grid.restartSettle()
            root.stageSince = Date.now()
            root.stage = 1
            return
        }
        case 1: {
            if (stubBackend.thumbAsks.length === 0) {
                if (Date.now() - root.stageSince > 5000) { root.fail("the first settle never asked"); }
                return
            }
            var cols = Math.max(1, grid.columns)
            var tileRows = Math.max(1, grid.visibleTileRows)
            root.screenLast = Math.min(root.rowCount - 1, tileRows * cols - 1)
            var first = root.flatAsks()
            if (first.length !== root.screenLast + 1) {
                root.fail("the first screen asked " + first.length + " tiles, want " + (root.screenLast + 1))
                return
            }
            if (!root.inBounds(first, 0, root.screenLast)) { root.fail("the first screen asked outside itself"); return }
            grid.contentY = 2 * grid.cellHeightPx
            root.stageSince = Date.now()
            root.stage = 2
            return
        }
        case 2: {
            var before = root.screenLast + 1
            var now = root.flatAsks()
            var fresh = now.filter(function (r) { return r >= before })
            if (fresh.length === 0) {
                if (Date.now() - root.stageSince > 5000) { root.fail("a scroll asked no newly visible tile"); }
                return
            }
            var cols2 = Math.max(1, grid.columns)
            var tileRows2 = Math.max(1, grid.visibleTileRows)
            var first2 = Math.floor(grid.contentY / grid.cellHeightPx) * cols2
            root.scrolledLast = Math.min(root.rowCount - 1, first2 + tileRows2 * cols2 - 1 + cols2)
            if (!root.inBounds(now, 0, root.scrolledLast)) { root.fail("an ask named a tile never scrolled into view"); return }
            if (root.stubBackend.windowCalls !== 0) { root.fail("the held window covered the scroll, yet " + root.stubBackend.windowCalls + " refetch ran"); return }
            root.stage = 10
            root.stageSince = Date.now()
            listing.request({ c: "list", path: "/probe", first: root.rowCount })
            return
        }
        case 10:
            if (!root.fsinfoSeen && Date.now() - root.stageSince > 5000) { root.fail("no fsinfo line arrived after the ask"); }
            return
        }
    }

    function report() {
        if (root.stage === 10 && root.fsinfoSeen && root.fsinfoClass !== "") {
            root.fail("the fsinfo line carried class " + JSON.stringify(root.fsinfoClass) + ", want local \"\"")
        }
        if (root.failures.length === 0)
            console.log("PICKERGRID PASS screen=0.." + root.screenLast + " scrolled<=" + root.scrolledLast + " fsinfo=\"" + root.fsinfoClass + "\"")
        else
            for (var i = 0; i < root.failures.length; i++)
                console.log("PICKERGRID FAIL " + root.failures[i])
        listing.quit()
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
