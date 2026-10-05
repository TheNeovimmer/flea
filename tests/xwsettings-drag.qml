import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Tabs.js" as Tabs

// Drive the real tab strip's pointer drags through WindowBody; each mode is one drag shape.
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
    property bool stepping: false
    property var dragItem: null
    property bool previewGrabbed: false
    readonly property int dragInset: 10
    readonly property int pointerMoveMs: 20
    readonly property int pointerEventMs: 1
    readonly property int harnessTickMs: 50
    // The tick the phase timer runs at; a run may shorten it to make a tick land inside a phase's own pointer waits.
    readonly property int tickMs: Number(Quickshell.env("PROBE_TICK_MS")) || root.harnessTickMs

    function check(label, actual, expected) {
        root.checks++
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) root.failures++
        console.log("TAB_HUNT " + (ok ? "ok " : "FAIL ") + label
                    + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function next() { root.phase++; root.phaseAt = Date.now() }
    function focusList() { pane.focusView = "list"; pane.listArea.forceActiveFocus() }
    function tabStrip() { return body.children.filter(function (item) { return typeof item.itemAt === "function" && item.tabCount !== undefined })[0] }
    function checkDrag(label) {
        check(label, Tabs.currentIndex(pane), 0)
        check(label + " labels", [dragItem.itemAt(0).title, dragItem.itemAt(1).title], [Tabs.label(other, pane.home), Tabs.label(here, pane.home)])
        check(label + " dragged identity at destination", pane.tabs.items[0].path, root.other)
    }
    function text(value) { keys.keyClickChar(value, Qt.NoModifier, -1) }
    function finish() {
        root.finished = true
        console.log("TAB_HUNT DONE " + root.mode + " " + root.checks + " checks, " + root.failures + " failed")
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
    // TestEvent pointer delays admit a reentrant tick, so the guard drops it or the outer call skips the next phase including release.
    function advance() {
        if (root.stepping) return
        root.stepping = true
        try { root.step() } finally { root.stepping = false }
    }
    function step() {
        if (!pane || pane.listInFlight || ["ready", "empty"].indexOf(pane.listingState) < 0 || Date.now() - root.phaseAt < 150) return
        if (Flea.ViewState.writeBook.inflight.length > 0 || Flea.ViewState.settler.running || Flea.ViewState.settleMode.length > 0) return
        if (root.mode === "dragpreview") {
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
        } else if (root.mode === "middrag") {
            // The listing is asked for while the drag is held; the phase after it starts only once it has landed.
            if (phase === 0) {
                focusList(); text("t")
                root.dragItem = tabStrip()
                var tab = root.dragItem.itemAt(1)
                keys.mousePress(tab, 30, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
                keys.mouseMove(tab, -root.dragItem.tabWidth + 10, tab.height / 2, 20, Qt.LeftButton, Qt.NoModifier)
                next()
            } else if (phase === 1) {
                check("the drag is held before its tab's folder loads", root.dragItem.dragFrom, 1)
                pane.open(root.other)
                next()
            } else if (phase === 2) {
                check("a listing that landed mid-drag leaves the grab held", [root.dragItem.dragFrom, pane.path], [1, root.other])
                var tab = root.dragItem.itemAt(1)
                keys.mouseRelease(tab, -root.dragItem.tabWidth + 10, tab.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
                next()
            } else if (phase === 3) {
                checkDrag("a drag held across a listing landing reorders")
                finish()
            }
        }
    }
    Timer {
        interval: root.tickMs
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
