import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "flea/js/Tabs.js" as Tabs

// Drive real WindowBody keys and pointers; record new-window launches while forwarding backend/state calls.
ShellRoot {
    id: root
    readonly property string mode: Quickshell.env("PROBE_MODE")
    readonly property string here: Quickshell.env("PROBE_BASE") || Quickshell.env("FLEA_PATH")
    readonly property string other: Quickshell.env("PROBE_OTHER_PATH")
    readonly property var body: loader.item
    readonly property var pane: body ? body.currentPane : null
    property int phase: 0
    property double phaseAt: Date.now()
    property int checks: 0
    property int failures: 0
    property bool finished: false
    property var dragItem: null
    property var railOwner: null
    readonly property var otherPane: watchLoader.item ? watchLoader.item.currentPane : null
    property int initialTotal: 0
    property int firstLists: 0
    property int secondLists: 0
    property var selectedNames: []
    property bool previewGrabbed: false
    readonly property int dragInset: 10
    readonly property int pointerMoveMs: 20
    readonly property int pointerEventMs: 1
    readonly property int harnessTickMs: 50

    function check(label, actual, expected) {
        root.checks++
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) root.failures++
        console.log("TAB_HUNT " + (ok ? "ok " : "FAIL ") + label
                    + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function next() { root.phase++; root.phaseAt = Date.now() }
    function launches() { return String(launchFile.text()).split("\n").filter(function (line) { return line.length > 0 }).length }
    function focusList() { pane.focusView = "list"; pane.listArea.forceActiveFocus() }
    function focusRail() { pane.focusView = "rail"; pane.sidebar.forceActiveFocus() }
    function tabStrip() { return body.children.filter(function (item) { return typeof item.itemAt === "function" && item.tabCount !== undefined })[0] }
    function checkDrag(label) {
        check(label, Tabs.currentIndex(pane), 0)
        check(label + " labels", [dragItem.itemAt(0).title, dragItem.itemAt(1).title], [Tabs.label(other, pane.home), Tabs.label(here, pane.home)])
        check(label + " dragged identity at destination", pane.tabs.items[0].path, root.other)
    }
    function press(key, modifiers) { keys.keyClick(key, modifiers || Qt.NoModifier, -1) }
    function text(value) { keys.keyClickChar(value, Qt.NoModifier, -1) }
    function finish() {
        root.finished = true
        console.log("TAB_HUNT DONE " + root.mode + " " + root.checks + " checks, " + root.failures + " failed")
        if (watchLoader.item) watchLoader.item.quitBackends()
        body.quitBackends()
    }
    FloatingWindow {
        id: win
        implicitWidth: 900
        implicitHeight: 600
        function centreOf(item) { return "" }
        function rectOf(item) { return "" }
        function boxOf(item) { return "" }
        Loader {
            id: loader
            anchors.fill: parent
            focus: true
            Component.onCompleted: setSource("file://" + Quickshell.env("PROBE_BODY"), { host: win })
        }
        TestEvent { id: keys }
    }
    FloatingWindow {
        id: watchWin
        visible: root.mode === "watch"
        implicitWidth: 900
        implicitHeight: 600
        function centreOf(item) { return "" }
        function rectOf(item) { return "" }
        function boxOf(item) { return "" }
        Loader {
            id: watchLoader
            active: root.mode === "watch"
            anchors.fill: parent
            onActiveChanged: if (active) setSource("file://" + Quickshell.env("PROBE_BODY"), { host: watchWin })
            Component.onCompleted: if (active) setSource("file://" + Quickshell.env("PROBE_BODY"), { host: watchWin })
        }
    }
    Process { id: outsideCreate; command: ["touch", root.here + "/000-watch-new.txt"] }
    FileView {
        id: launchFile
        path: Quickshell.env("PROBE_LAUNCHES")
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
    }
    function advance() {
        if (!pane || pane.listInFlight || ["ready", "empty"].indexOf(pane.listingState) < 0 || Date.now() - root.phaseAt < 150) return
        if (Flea.ViewState.writeBook.inflight.length > 0 || Flea.ViewState.settler.running || Flea.ViewState.settleMode.length > 0) return
        if (root.mode === "watch") {
            if (!otherPane || otherPane.listInFlight || otherPane.listingState !== "ready") return
            if (phase === 0) {
                root.initialTotal = pane.total
                root.firstLists = pane.backend.listRequests
                root.secondLists = otherPane.backend.listRequests
                root.selectedNames = [pane.rowFor(pane.cursorIndex).n, pane.rowFor(1).n]
                pane.clearSelection()
                pane.toggleSelectAt(1)
                check("the watch fixture starts with both selected files", pane.selectionCount(), 2)
                outsideCreate.running = true; next()
            } else if (phase === 1) {
                if ((otherPane.total === initialTotal || pane.total === initialTotal) && Date.now() - phaseAt < 2000) return
                check("the other window refreshes the watched folder", otherPane.total, initialTotal + 1)
                check("a selected window refreshes its watched folder", pane.total, initialTotal + 1)
                check("a selected window sends its own watched reread", pane.backend.listRequests > root.firstLists, true)
                check("the watched reread keeps both selected files", pane.selectedIndices().map(function (i) { return pane.rowFor(i).n }), root.selectedNames)
                root.firstLists = pane.backend.listRequests
                pane.clearSelection()
                next()
            } else if (phase === 2) {
                if (Date.now() - phaseAt <= pane.wire.watchMs + root.harnessTickMs)
                    return
                check("clearing selection keeps the refreshed listing", pane.total, initialTotal + 1)
                check("clearing selection sends no extra watched reread", pane.backend.listRequests, root.firstLists)
                check("clearing selection removes the kept mark", pane.selectionCount(), 0)
                check("the other window requested its own watched reread", otherPane.backend.listRequests > root.secondLists, true)
                finish()
            }
        } else if (root.mode === "restore") {
            if (phase === 0) {
                check("Last folder restores every tab", Tabs.count(pane), 3)
                check("Last folder restores the active index", Tabs.currentIndex(pane), 1)
                check("Last folder lists the active tab's folder", pane.path, root.other)
                focusList(); text("]"); next()
            } else if (phase === 1) {
                check("the restored third tab lists its folder", pane.path, root.here + "/sub")
                focusList(); text("]"); next()
            } else if (phase === 2) {
                check("the restored first tab lists its folder after wrap", pane.path, root.here)
                finish()
            }
        } else if (root.mode === "openers") {
            var view = Math.floor(phase / 6)
            var part = phase % 6
            var modes = ["list", "grid", "columns"]
            var codes = [Qt.Key_1, Qt.Key_3, Qt.Key_2]
            if (view >= modes.length) { finish(); return }
            if (part === 0) { focusList(); press(codes[view], Qt.ControlModifier); next() }
            else if (part === 1) {
                check("the opener uses " + modes[view] + " view", pane.viewMode, modes[view])
                focusList(); pane.setCursor(0); press(Qt.Key_Return, Qt.ControlModifier); next()
            } else if (part === 2) {
                check("Ctrl+Return opens the folder in " + modes[view], pane.path, root.here + "/sub")
                check("Ctrl+Return adds one tab in " + modes[view], Tabs.count(pane), 2)
                Tabs.closeAt(pane, Tabs.currentIndex(pane)); next()
            } else if (part === 3) {
                var row = pane.visibleItemFor(0)
                if (!row) return
                keys.mouseClick(row, 45, row.height / 2, Qt.MiddleButton, Qt.NoModifier, 1); next()
            } else if (part === 4) {
                check("middle click opens the folder in " + modes[view], pane.path, root.here + "/sub")
                check("middle click adds one tab in " + modes[view], Tabs.count(pane), 2)
                Tabs.closeAt(pane, Tabs.currentIndex(pane)); next()
            } else if (part === 5) next()
        } else if (root.mode === "dragpreview") {
            if (phase === 0) {
                root.dragItem = tabStrip()
                var tab = dragItem.itemAt(1)
                keys.mousePress(tab, tab.width / 2, tab.height / 2, Qt.LeftButton, Qt.NoModifier, pointerEventMs)
                keys.mouseMove(tab.parent, 3 * dragItem.tabWidth - dragInset, tab.height / 2, pointerMoveMs, Qt.LeftButton, Qt.NoModifier)
                next()
            } else if (phase === 1) {
                var held = dragItem.itemAt(1), after = dragItem.itemAt(2)
                check("the preview drag is held at the far insertion point", [dragItem.dragFrom, dragItem.dropAt], [1, 3])
                check("the held tab occupies its destination slot", held.x, 2 * dragItem.tabWidth)
                check("the following tab closes the source slot", after.x, dragItem.tabWidth)
                var bar = dragItem.children.filter(function (item) { return item.color === Flea.Theme.color.accent && item.width === 2 * Flea.Theme.spacing.hairline })[0]
                check("the insertion bar borders the ghost's leading edge", bar ? bar.x : -1, held.mapToItem(dragItem, 0, 0).x - Flea.Theme.spacing.hairline)
                check("the held tab draws at disabled opacity", held.opacity, Flea.Theme.disabledOpacity)
                check("a preview keeps the committed order", Tabs.labels(pane), [Tabs.label(here, pane.home), Tabs.label(other, pane.home), "sub"])
                dragItem.grabToImage(function (result) { check("the held preview capture saves", result.saveToFile(Quickshell.env("PROBE_SHOT")), true); root.previewGrabbed = true })
                next()
            } else if (phase === 2) {
                if (!root.previewGrabbed) return
                var tab = dragItem.itemAt(1)
                keys.mouseRelease(tab.parent, 3 * dragItem.tabWidth - dragInset, tab.height / 2, Qt.LeftButton, Qt.NoModifier, pointerEventMs)
                next()
            } else if (phase === 3) {
                check("the preview order becomes the committed order", Tabs.labels(pane), [Tabs.label(here, pane.home), "sub", Tabs.label(other, pane.home)])
                check("dragging another tab preserves the current tab", [Tabs.currentIndex(pane), pane.path], [0, root.here])
                finish()
            }
        } else if (root.mode === "quickdrag") {
            if (phase === 0) { focusList(); text("t"); pane.open(root.other); next() }
            else if (phase === 1) {
                root.dragItem = tabStrip()
                var tab = root.dragItem.itemAt(1)
                keys.mousePress(tab, 30, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
                keys.mouseMove(tab, -root.dragItem.tabWidth + 10, tab.height / 2, 20, Qt.LeftButton, Qt.NoModifier)
                next()
            } else if (phase === 2) {
                check("a single movement event grabs the tab drag", root.dragItem.dragFrom, 1)
                var tab = root.dragItem.itemAt(1)
                keys.mouseRelease(tab, -root.dragItem.tabWidth + 10, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
                next()
            } else if (phase === 3) {
                checkDrag("a tab drag with one move event lands where released")
                // Reset the current tab's place so the slower control is independent of this result.
                Tabs.moveCurrent(pane, 1)
                var tab = root.dragItem.itemAt(1)
                keys.mousePress(tab, 30, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
                keys.mouseMove(tab, -20, tab.height / 2, 20, Qt.LeftButton, Qt.NoModifier)
                keys.mouseMove(tab, -root.dragItem.tabWidth + 10, tab.height / 2, 20, Qt.LeftButton, Qt.NoModifier)
                next()
            } else if (phase === 4) {
                var tab = root.dragItem.itemAt(1)
                keys.mouseRelease(tab, -root.dragItem.tabWidth + 10, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
                next()
            } else if (phase === 5) {
                checkDrag("the same drag with two move events reorders")
                Tabs.moveCurrent(pane, 1)
                var tab = root.dragItem.itemAt(1)
                keys.mousePress(tab, 30, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
                keys.mouseMove(tab, -20, tab.height / 2, 20, Qt.LeftButton, Qt.NoModifier)
                next()
            } else if (phase === 6) {
                check("the release-only destination starts from a grabbed drag", root.dragItem.dragFrom, 1)
                var tab = root.dragItem.itemAt(1)
                keys.mouseRelease(tab, -root.dragItem.tabWidth + 10, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
                next()
            } else if (phase === 7) {
                checkDrag("release updates the insertion slot without another move")
                finish()
            }
        } else if (root.mode === "window") {
            if (phase === 0) { focusList(); press(Qt.Key_N, Qt.ControlModifier); next() }
            else if (phase === 1) {
                if (launches() === 0 && Date.now() - phaseAt < 1000) return
                check("Ctrl+N in the list launches a window", launches(), 1)
                pane.focusView = "rail"; pane.sidebar.forceActiveFocus()
                press(Qt.Key_N, Qt.ControlModifier); next()
            } else if (phase === 2) {
                if (Date.now() - phaseAt < 1000) return
                check("Ctrl+N in the rail launches a window", launches(), 2)
                focusRail(); text("t"); next()
            } else if (phase === 3) {
                check("t in the rail opens a tab", Tabs.count(pane), 2)
                pane.open(root.other); next()
            } else if (phase === 4) {
                check("the rail-created tab lists its own folder", pane.path, root.other)
                focusRail(); text("["); next()
            } else if (phase === 5) {
                check("[ in the rail selects the previous tab", [Tabs.currentIndex(pane), pane.path], [0, root.here])
                focusRail(); text("]"); next()
            } else if (phase === 6) {
                check("] in the rail selects the next tab", [Tabs.currentIndex(pane), pane.path], [1, root.other])
                focusRail(); press(Qt.Key_PageUp, Qt.ControlModifier); next()
            } else if (phase === 7) {
                check("Ctrl+PageUp in the rail selects the previous tab", pane.path, root.here)
                focusRail(); press(Qt.Key_PageDown, Qt.ControlModifier); next()
            } else if (phase === 8) {
                check("Ctrl+PageDown in the rail selects the next tab", pane.path, root.other)
                focusRail(); press(Qt.Key_PageUp, Qt.ControlModifier | Qt.ShiftModifier); next()
            } else if (phase === 9) {
                check("Ctrl+Shift+PageUp in the rail moves the current tab left", [Tabs.currentIndex(pane), pane.path], [0, root.other])
                focusRail(); press(Qt.Key_PageDown, Qt.ControlModifier | Qt.ShiftModifier); next()
            } else if (phase === 10) {
                check("Ctrl+Shift+PageDown in the rail moves the current tab right", Tabs.currentIndex(pane), 1)
                focusRail(); text("{"); next()
            } else if (phase === 11) {
                check("{ in the rail moves the current tab left", Tabs.currentIndex(pane), 0)
                focusRail(); text("}"); next()
            } else if (phase === 12) {
                check("} in the rail moves the current tab right", Tabs.currentIndex(pane), 1)
                focusRail(); text("w"); next()
            } else if (phase === 13) {
                check("w in the rail closes the current tab", [Tabs.count(pane), pane.path], [1, root.here])
                firstLists = pane.backend.listRequests
                focusRail(); press(Qt.Key_F5); next()
            } else if (phase === 14) {
                check("F5 in the rail reloads the current folder once", [pane.backend.listRequests, pane.path], [firstLists + 1, root.here])
                firstLists = pane.backend.listRequests
                focusRail(); press(Qt.Key_R, Qt.ControlModifier); next()
            } else if (phase === 15) {
                check("Ctrl+R in the rail reloads the current folder once", [pane.backend.listRequests, pane.path], [firstLists + 1, root.here])
                root.railOwner = pane
                pane.chooseView("dual"); next()
            } else if (phase === 16) {
                if (!body.dualMode) return
                body.focusPane(1); next()
            } else if (phase === 17) {
                check("the second pane owns the shared rail", pane !== root.railOwner, true)
                focusRail(); press(Qt.Key_N, Qt.ControlModifier); next()
            } else if (phase === 18) {
                if (Date.now() - phaseAt < 1000) return
                check("Ctrl+N from the shared rail launches a window", launches(), 3)
                focusRail(); text("t"); next()
            } else if (phase === 19) {
                check("the shared rail opens a tab in the active pane", [Tabs.count(pane), Tabs.count(root.railOwner)], [2, 1])
                focusRail(); press(Qt.Key_W, Qt.ControlModifier); next()
            } else if (phase === 20) {
                check("Ctrl+W from the shared rail closes the active pane's tab", [Tabs.count(pane), Tabs.count(root.railOwner)], [1, 1])
                finish()
            }
        } else if (root.mode === "trash") {
            if (phase === 0) { focusList(); text("t"); pane.open(root.other); next() }
            else if (phase === 1) {
                check("the second tab lists its own folder", pane.path, root.other)
                pane.trash.open(); next()
            } else if (phase === 2) {
                check("Trash is open before the switch", pane.trash.opened, true)
                pane.trash.item.forceActiveFocus(); text("["); next()
            } else if (phase === 3) {
                check("[ from Trash selects the previous tab", Tabs.currentIndex(pane), 0)
                check("the previous tab's directory has landed", pane.path, root.here)
                check("the destination listing replaces Trash", pane.trash.opened, false)
                // Keep the next assertion independent even when the preceding switch left Trash up.
                pane.trash.close(); pane.trash.open(); next()
            } else if (phase === 4) {
                pane.trash.item.forceActiveFocus(); text("t"); next()
            } else if (phase === 5) {
                check("t from Trash creates a new tab", Tabs.count(pane), 3)
                check("the new tab's listing replaces Trash", pane.trash.opened, false)
                focusList(); text("["); next()
            } else if (phase === 6) {
                check("returning to a tab left in Trash restores its folder", [pane.path, pane.trash.opened], [root.other, false])
                pane.trash.open(); next()
            } else if (phase === 7) {
                pane.trash.item.forceActiveFocus(); text("w"); next()
            } else if (phase === 8) {
                check("closing the current tab drops Trash over the same-folder tab", [Tabs.count(pane), pane.path, pane.trash.opened], [2, root.here, false])
                pane.trash.open(); next()
            } else if (phase === 9) {
                pane.openWithoutHistory(root.other); next()
            } else if (phase === 10) {
                check("opening a folder without history drops Trash", [pane.path, pane.trash.opened], [root.other, false])
                pane.trash.open(); next()
            } else if (phase === 11) {
                if (pane.listInFlight) return
                check("Trash is open before the covered folder is re-listed in place", pane.trash.opened, true)
                pane.refresh(""); next()
            } else if (phase === 12) {
                check("a refresh of the covered folder leaves Trash open", pane.trash.opened, true)
                if (pane.listInFlight) return
                pane.wire.stale = true; pane.wire.reread(); next()
            } else if (phase === 13) {
                check("a watcher re-read of the covered folder leaves Trash open", pane.trash.opened, true)
                finish()
            }
        } else if (root.mode === "tabview") {
            if (phase === 0) { focusList(); press(Qt.Key_3, Qt.ControlModifier); next() }
            else if (phase === 1) {
                check("Ctrl+3 selects Grid before opening another tab", pane.viewMode, "grid")
                focusList(); text("t"); press(Qt.Key_1, Qt.ControlModifier); next()
            } else if (phase === 2) {
                check("Ctrl+1 selects List in the new tab", pane.viewMode, "list")
                pane.open(root.other); next()
            } else if (phase === 3) { focusList(); text("["); next() }
            else if (phase === 4) {
                check("the switched tab is current", Tabs.currentIndex(pane), 0)
                check("the switched tab's folder landed", pane.path, root.here)
                check("the switched tab keeps its own Grid view after the reply", pane.viewMode, "grid")
                finish()
            }
        } else if (root.mode === "tabs") {
            if (phase === 0) { focusList(); text("t"); pane.open(root.other); next() }
            else if (phase === 1) { focusList(); text("["); next() }
            else if (phase === 2) {
                check("[ selects the previous folder", pane.path, root.here)
                focusList(); text("]"); next()
            } else if (phase === 3) {
                check("] selects the next folder", pane.path, root.other)
                focusList(); text("{"); next()
            } else if (phase === 4) {
                check("{ moves the current tab left", Tabs.currentIndex(pane), 0)
                focusList(); text("}"); next()
            } else if (phase === 5) {
                check("} moves the current tab right", Tabs.currentIndex(pane), 1)
                press(Qt.Key_PageUp, Qt.ControlModifier | Qt.ShiftModifier); next()
            } else if (phase === 6) {
                check("Ctrl+Shift+PageUp moves the tab left", Tabs.currentIndex(pane), 0)
                press(Qt.Key_PageDown, Qt.ControlModifier | Qt.ShiftModifier); next()
            } else if (phase === 7) {
                check("Ctrl+Shift+PageDown moves the tab right", Tabs.currentIndex(pane), 1)
                next()
                root.dragItem = tabStrip()
                check("the real tab strip is reachable", !!root.dragItem, true)
                var tab = root.dragItem.itemAt(1)
                keys.mousePress(tab, 30, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
                keys.mouseMove(tab, -20, tab.height / 2, 20, Qt.LeftButton, Qt.NoModifier)
                keys.mouseMove(tab, -root.dragItem.tabWidth + 10, tab.height / 2, 20, Qt.LeftButton, Qt.NoModifier)
            } else if (phase === 8) {
                check("the tab's pointer drag was grabbed", root.dragItem.dragFrom, 1)
                var tab = root.dragItem.itemAt(1)
                keys.mouseRelease(tab, -root.dragItem.tabWidth + 10, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
                next()
            } else if (phase === 9) {
                check("a pointer drag reorders the real strip", Tabs.currentIndex(pane), 0)
                focusList(); pane.setCursor(0); press(Qt.Key_Return, Qt.ControlModifier); next()
            } else if (phase === 10) {
                check("Ctrl+Return opens the cursor folder", pane.path, root.other + "/sub")
                check("Ctrl+Return adds a tab", Tabs.count(pane), 3)
                focusList(); text("["); next()
            } else if (phase === 11) {
                var row = pane.visibleItemFor(0)
                if (!row) return
                keys.mouseClick(row, 45, row.height / 2, Qt.MiddleButton, Qt.NoModifier, 1); next()
            } else if (phase === 12) {
                check("a middle click opens the real folder row", pane.path, root.here + "/sub")
                check("a middle click adds a tab", Tabs.count(pane), 4)
                finish()
            }
        }
    }
    Timer {
        interval: root.harnessTickMs
        repeat: true
        running: !root.finished
        onTriggered: root.advance()
    }
    Timer {
        interval: 20000
        running: !root.finished
        onTriggered: { check("the probe finishes before its deadline at phase " + root.phase, false, true); finish() }
    }
}
