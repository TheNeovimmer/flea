//@ pragma ShellId flea-picker-grid-test

import QtQuick
import Quickshell
import "flea" as Flea

// Visible tiles only: unknown storage holds every ask, one screen asks after movement stops.
// Real window chain below proves onListed asks fsinfo and the grid asks thumb after it.
ShellRoot {
    id: root

    property var failures: []
    property int rowCount: 60
    property int stage: 0
    property double stageSince: 0
    property int screenLast: -1
    property int scrolledLast: -1
    property int hiddenShown: -1
    property string folderClass: "?"
    property var winShell: null
    property var win: null
    readonly property int askWaitMs: 5000
    readonly property int probeTimeoutMs: 30000

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
            property int shownTotal: 60
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
            property int coalesceMs: 16
            property real windowLead: 0.25
            property var kindNames: []
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
        Flea.PickerList {
            id: listProbe
            visible: false
            width: 400
            height: 300
            picker: root.stubPicker
            backend: root.stubBackend
        }
    }

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
    function winThumbPending() {
        if (!root.win || !root.win.thumbState || !root.win.thumbState.file) return false
        return Object.keys(root.win.thumbState.file).length > 0
    }

    Timer {
        interval: 10
        repeat: true
        running: true
        onTriggered: root.step()
    }
    Timer { interval: root.probeTimeoutMs; running: true; onTriggered: { root.fail("probe timed out"); root.report() } }

    function step() {
        if (root.failures.length > 0) { root.report(); return }
        switch (root.stage) {
        case 0: {
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
                if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("the first settle never asked"); }
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
                if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("a scroll asked no newly visible tile"); }
                return
            }
            var cols2 = Math.max(1, grid.columns)
            var tileRows2 = Math.max(1, grid.visibleTileRows)
            var first2 = Math.floor(grid.contentY / grid.cellHeightPx) * cols2
            root.scrolledLast = Math.min(root.rowCount - 1, first2 + tileRows2 * cols2 - 1)
            if (!root.inBounds(now, 0, root.scrolledLast)) { root.fail("an ask named a tile never scrolled into view"); return }
            if (root.stubBackend.windowCalls !== 0) { root.fail("the held window covered the scroll, yet " + root.stubBackend.windowCalls + " refetch ran"); return }
            root.stage = 3
            root.stageSince = Date.now()
            return
        }
        case 3: {
            if (listProbe.count !== 0 || listProbe.model !== 0) {
                root.fail("hidden list built count=" + listProbe.count + " model=" + listProbe.model + ", want 0")
                return
            }
            listProbe.visible = true
            root.stage = 30
            root.stageSince = Date.now()
            return
        }
        case 30: {
            if (listProbe.count !== root.stubPicker.shownTotal) {
                if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("shown list holds count=" + listProbe.count + " model=" + listProbe.model + ", want " + root.stubPicker.shownTotal); }
                return
            }
            root.hiddenShown = listProbe.count
            listProbe.visible = false
            var winComp = Qt.createComponent("flea/PickerWindow.qml")
            if (winComp.status !== Component.Ready) {
                root.fail("PickerWindow does not compile: " + winComp.errorString())
                return
            }
            root.winShell = winComp.createObject(root)
            if (!root.winShell) {
                root.fail("PickerWindow did not instantiate: " + winComp.errorString())
                return
            }
            root.win = root.winShell.pickerWin
            if (!root.win) {
                root.fail("real window has no storage holder")
                return
            }
            root.stage = 41
            root.stageSince = Date.now()
            return
        }
        case 41: {
            if (!root.win || !root.win.storageKnown) {
                if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("window onListed never asked fsinfo"); }
                return
            }
            if (root.win.storageClass !== "network") {
                root.fail("window storage holds " + JSON.stringify(root.win.storageClass) + ", want network")
                return
            }
            root.win.setView("grid")
            root.stage = 42
            root.stageSince = Date.now()
            return
        }
        case 42: {
            if (!root.winThumbPending()) {
                if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("no thumb ask followed the fsinfo answer"); }
                return
            }
            root.folderClass = root.win.storageClass
            root.win.open("flea:recent")
            root.stage = 43
            root.stageSince = Date.now()
            return
        }
        case 43: {
            if (!root.win) {
                root.fail("real window vanished before Recent")
                return
            }
            if (root.win.path !== "flea:recent") {
                if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("Recent never opened, at " + root.win.path); }
                return
            }
            // A stray Recent fsinfo flips storageKnown at once, so no hold may hide it.
            if (root.win.storageKnown) { root.fail("Recent asked fsinfo, storage is known"); return }
            if (root.win.pendingListings !== 0 || root.win.total === 0) {
                if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("Recent listing never landed"); }
                return
            }
            // The barrier rides the same worker: a scroll past the held window asks for rows.
            var view = root.win.viewItem()
            if (view) view.contentY = view.contentHeight
            root.stage = 44
            root.stageSince = Date.now()
            return
        }
        case 44: {
            if (root.win.storageKnown) { root.fail("Recent asked fsinfo, storage is known"); return }
            if (root.win.path !== "flea:recent") { root.fail("left Recent before its window answered"); return }
            if (root.win.rows.length > 0) { root.report(); return }
            var again = root.win.viewItem()
            if (again) again.contentY = again.contentHeight
            if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("Recent window ask never answered"); }
            return
        }
        }
    }

    function report() {
        if (root.failures.length === 0) {
            console.log("PICKERGRID PASS screen=0.." + root.screenLast + " scrolled<=" + root.scrolledLast + " hidden=" + root.hiddenShown + " fsinfo=\"" + root.folderClass + "\"")
        } else {
            for (var i = 0; i < root.failures.length; i++)
                console.log("PICKERGRID FAIL " + root.failures[i])
        }
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
