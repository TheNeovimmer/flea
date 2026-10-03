//@ pragma ShellId flea-picker-grid-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Picker.js" as Picker

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
    property int stage1Batches: 0
    property int stage1Asks: 0
    property var winShell: null
    property var win: null
    property bool settledWritten: false
    property bool wideSetup: false
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
            property bool marksAllowed: true
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
            function endRange() {}
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
    // Delegates inside the viewport, independent of the grid's own tile arithmetic.
    function visibleTiles() {
        var lo = grid.contentY, hi = grid.contentY + grid.height
        var out = []
        for (var i = 0; i < root.rowCount; i++) {
            var item = grid.itemAtIndex(i)
            if (!item) continue
            if (item.y + item.height > lo && item.y < hi) out.push(i)
        }
        return out
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
            var exp = root.visibleTiles()
            if (exp.length === 0) { root.fail("no delegate met the viewport on the first screen"); return }
            root.screenLast = exp[exp.length - 1]
            root.stage1Batches = stubBackend.thumbAsks.length
            root.stage1Asks = root.flatAsks().length
            var first = root.flatAsks()
            if (first.length !== exp.length) {
                root.fail("the first screen asked " + first.length + " tiles, want " + exp.length)
                return
            }
            if (!root.inBounds(first, exp[0], exp[exp.length - 1])) { root.fail("the first screen asked outside itself"); return }
            grid.contentY = 2 * grid.cellHeightPx
            root.stageSince = Date.now()
            root.stage = 2
            return
        }
        case 2: {
            var now = root.flatAsks()
            if (now.length <= root.stage1Asks) {
                if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("a scroll asked no newly visible tile"); }
                return
            }
            var exp2 = root.visibleTiles()
            if (exp2.length === 0) { root.fail("no delegate met the viewport after the scroll"); return }
            root.scrolledLast = exp2[exp2.length - 1]
            var fresh = []
            for (var b = root.stage1Batches; b < stubBackend.thumbAsks.length; b++)
                for (var j = 0; j < stubBackend.thumbAsks[b].length; j++)
                    fresh.push(stubBackend.thumbAsks[b][j])
            if (fresh.length === 0) { root.fail("a scroll asked no newly visible tile"); return }
            if (!root.inBounds(fresh, exp2[0], exp2[exp2.length - 1])) { root.fail("an ask named a tile never scrolled into view"); return }
            if (root.stubBackend.windowCalls !== 0) { root.fail("the held window covered the scroll, yet " + root.stubBackend.windowCalls + " refetch ran"); return }
            grid.contentY = 0
            grid.width = 1600
            grid.height = 700
            root.rowCount = 500
            root.stubPicker.rows = root.buildRows()
            root.stubPicker.total = 500
            root.stubPicker.shownTotal = 500
            root.stageSince = Date.now()
            root.stage = 4
            return
        }
        case 4: {
            if (grid.width !== 1600 || grid.columns < 1) {
                if (Date.now() - root.stageSince > root.askWaitMs) {
                    if (grid.width !== 1600) root.fail("wide width never reached 1600")
                    else root.fail("wide columns never reached 1")
                }
                return
            }
            var vis = root.visibleTiles()
            if (vis.length === 0) {
                if (Date.now() - root.stageSince > root.askWaitMs) root.fail("no delegate met the wide viewport")
                return
            }
            var listRows = Math.max(1, listProbe.visibleRows)
            var wide = Picker.windowSize(listRows, grid.visibleTileRows, grid.columns)
            var old = listRows + 60
            if (!(old < vis.length)) { root.fail("the wide stage is not sensitive, old covers " + vis.length); return }
            if (!(wide * (1 - root.stubPicker.windowLead) >= vis.length)) { root.fail("the shared window leaves blank tiles at wide width"); return }
            for (var w = 0; w < vis.length; w++)
                if (vis[w] >= wide) { root.fail("tile " + vis[w] + " has no row in a " + wide + " window"); return }
            // One-shot setup: re-running it would re-arm the settle the quiesce below waits out.
            if (!root.wideSetup) {
                root.wideSetup = true
                root.stubPicker.held = 10
                root.stubPicker.rows = root.stubPicker.rows.slice(0, 60)
                root.stubPicker.total = 500
                root.stubPicker.shownTotal = 500
                var calls = root.stubBackend.windowCalls
                listProbe.requestIfDrifted()
                if (root.stubBackend.windowCalls !== calls) { root.fail("a hidden list refetched its window"); return }
                listProbe.visible = true
                root.stubPicker.cursorIndex = 300
                listProbe.reshow(300)
                if (root.stubBackend.windowCalls === calls) { root.fail("a reshown list never refetched its window"); return }
                var rowTop = 300 * Flea.Theme.rowHeight
                if (!(listProbe.contentY <= rowTop && rowTop + Flea.Theme.rowHeight <= listProbe.contentY + listProbe.height)) { root.fail("a reshown list never showed row 300"); return }
                listProbe.visible = false
                return
            }
            // Quiesce the settle, so only the reshow below may restart it.
            if (grid.settleRunning) return
            var gCalls = root.stubBackend.windowCalls
            var target = vis[vis.length - 1] + 1
            root.stubPicker.cursorIndex = target
            grid.reshow(target)
            if (root.stubBackend.windowCalls === gCalls) { root.fail("a reshown grid never refetched its window"); return }
            if (!grid.settleRunning) { root.fail("a reshown grid never restarted its settle"); return }
            if (root.visibleTiles().indexOf(target) < 0) { root.fail("a reshown grid never showed tile " + target); return }
            root.wideSetup = false
            root.stubPicker.held = 0
            root.rowCount = 60
            root.stubPicker.rows = root.buildRows()
            root.stubPicker.total = 60
            root.stubPicker.shownTotal = 60
            root.stubPicker.cursorIndex = 0
            grid.width = 700
            grid.height = 300
            grid.contentY = 0
            root.stage = 20
            return
        }
        case 20: {
            var pageCols = Math.max(1, grid.columns)
            var pageRows = Math.max(1, grid.visibleTileRows)
            var page = pageRows * pageCols
            if (page < 2) { root.fail("page holds " + page + ", want at least 2"); return }
            var lastTile = root.rowCount - 1
            var start = Math.max(1, lastTile - Math.floor(page / 2))
            if (lastTile - start >= page) { root.fail("start " + start + " is a full page from the end"); return }
            root.stubPicker.cursorIndex = start
            var downHandled = grid.handleAction("pageDown", 0, 0)
            if (!downHandled) { root.fail("pageDown went unhandled"); return }
            if (root.stubPicker.cursorIndex !== lastTile) { root.fail("pageDown from " + start + " landed on " + root.stubPicker.cursorIndex + ", want " + lastTile); return }
            root.stage = 21
            return
        }
        case 21: {
            root.stubPicker.cursorIndex = 1
            var upHandled = grid.handleAction("pageUp", 0, 0)
            if (!upHandled) { root.fail("pageUp went unhandled"); return }
            if (root.stubPicker.cursorIndex !== 0) { root.fail("pageUp from 1 landed on " + root.stubPicker.cursorIndex + ", want 0"); return }
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
            // Release fsinfo once the first settle ran unknown with no thumb ask.
            if (root.win && !root.win.storageKnown && !root.settledWritten) {
                var firstGrid = root.win.viewItem()
                if (firstGrid && firstGrid.settleRuns > 0) {
                    if (root.winThumbPending()) { root.fail("the first settle asked while storage was unknown"); return }
                    Quickshell.execDetached(["touch", Quickshell.env("FLEA_PICKER_SETTLED")])
                    root.settledWritten = true
                }
            }
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
            root.win.held = 0
            root.win.rows = root.win.rows.slice(0, 5)
            root.win.cursorIndex = root.win.total - 1
            root.win.setView("list")
            root.stage = 45
            root.stageSince = Date.now()
            return
        }
        case 45: {
            if (root.win.viewMode !== "list") { root.fail("setView list never switched view"); return }
            var lview = root.win.viewItem()
            var ltop = root.win.cursorIndex * Flea.Theme.rowHeight
            if (!(lview.contentY <= ltop && ltop + Flea.Theme.rowHeight <= lview.contentY + lview.height)) {
                if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("setView list never showed the cursor row"); }
                return
            }
            if (!(root.win.held <= root.win.cursorIndex && root.win.cursorIndex < root.win.held + root.win.rows.length)) {
                if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("setView list never refetched its window"); }
                return
            }
            root.win.held = 0
            root.win.rows = root.win.rows.slice(0, 5)
            root.win.setView("grid")
            root.stage = 46
            root.stageSince = Date.now()
            return
        }
        case 46: {
            if (root.win.viewMode !== "grid") { root.fail("setView grid never switched view"); return }
            var gview = root.win.viewItem()
            var gitem = gview.itemAtIndex(root.win.cursorIndex)
            if (!gitem || !(gitem.y + gitem.height > gview.contentY && gitem.y < gview.contentY + gview.height)) {
                if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("setView grid never showed the cursor tile"); }
                return
            }
            if (!(root.win.held <= root.win.cursorIndex && root.win.cursorIndex < root.win.held + root.win.rows.length)) {
                if (Date.now() - root.stageSince > root.askWaitMs) { root.fail("setView grid never refetched its window"); }
                return
            }
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
