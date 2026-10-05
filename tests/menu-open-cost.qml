//@ pragma ShellId flea-menu-open-cost-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/MenuFit.js" as MenuFit

// tests/menu-settle.sh's open-cost leg: the real pane opens its row menu by the m key and by a click point, and every open reads its rows' widths a few times, never once per row.
ShellRoot {
    id: root
    readonly property var pane: body.currentPane
    readonly property var menu: pane ? pane.contextMenu() : null
    readonly property string fixture: Quickshell.env("FLEA_PATH")
    readonly property string firstPath: Quickshell.env("FLEA_COST_FIRST") === "click" ? "click" : "key"
    readonly property int fixtureRows: 8
    // Four opens per process alternate the two paths, the first of them the process's cold one.
    readonly property int opens: 4
    readonly property int pollMs: 20
    readonly property int stageLimitMs: 8000
    // Ticks an open rests so its provider answers land and no frame is pending when the next one starts.
    readonly property int restTicks: 10
    readonly property int keyRow: 0
    readonly property int clickRow: 1
    readonly property real clickInset: 40
    // One read per build, when its rows stand; a read per row built would be about twenty a build.
    readonly property int readsPerBuild: 1
    readonly property string longLabel: "A label long enough that its row wants more than the card's base width, " + "so the fit has to widen the card to hold it whole"

    property string stage: "ready"
    property int sample: 0
    property int rest: 0
    property bool finished: false
    property bool executing: false
    property double started: Date.now()
    property string path: "key"
    property bool measuring: false
    property int readsBefore: 0
    property int builds: 0
    property double tPlace: 0
    property double tFrame: 0
    property int checks: 0
    property int failures: 0

    function log(line) { console.log("MENUOPEN " + line) }
    function check(name, ok) {
        checks += 1
        if (ok) return
        failures += 1
        log("FAIL " + name)
    }
    function next(stageName) { stage = stageName; started = Date.now() }
    function finish() {
        finished = true
        log((failures === 0 ? "PASS " : "FAIL ") + checks + " checks")
        log("DONE failures=" + failures)
        body.quitBackends()
    }
    function advance() {
        if (executing || finished) return
        executing = true
        try { runStage() }
        catch (error) { check("harness error " + String(error), false); finish() }
        executing = false
    }
    function runStage() {
        var timedOut = Date.now() - started > stageLimitMs
        if (stage === "ready") {
            if (timedOut) { check("fixture listed", false); finish(); return }
            if (pane.listInFlight || pane.path !== fixture || pane.total < fixtureRows || !pane.visibleItemFor(clickRow + 1)) return
            next("rest")
        } else if (stage === "rest") {
            if (rest++ < restTicks) return
            rest = 0
            path = (sample % 2 === 0) === (firstPath === "key") ? "key" : "click"
            pane.setCursor(keyRow)
            pane.listArea.forceActiveFocus()
            readsBefore = MenuFit.reads
            builds = 0
            tFrame = 0
            measuring = true
            tPlace = Date.now()
            if (path === "key") {
                driver.keyClickChar("m", Qt.NoModifier, -1)
            } else {
                // The pane's own right-click handler, the one a mouse reaches.
                var row = pane.visibleItemFor(clickRow)
                driver.mouseClick(row, clickInset, row.height / 2, Qt.RightButton, Qt.NoModifier, -1)
            }
            next("shown")
        } else if (stage === "shown") {
            if (timedOut) { check(path + " open reached a frame", false); finish(); return }
            if (tFrame === 0 || rest++ < restTicks) return
            rest = 0
            measuring = false
            var reads = MenuFit.reads - readsBefore
            check(path + " open " + sample + " opened", menu.opened)
            // Equal is the target: fewer would mean the fit was not read, or this is not the library the menu imports.
            check(path + " open " + sample + " read " + reads + " times for " + builds + " builds", builds >= 1 && reads === readsPerBuild * builds)
            // A long label widens the card past its base width once the rows stand, so a fit held at the base fails here.
            menu.setEntries([{ label: longLabel, action: "open" }, { label: "Short", action: "copy" }])
            check(path + " open " + sample + " card widens for a long label", menu.frameItem.width > Flea.Theme.menuWidth)
            log("open " + sample + " " + path + " reads=" + reads + " builds=" + builds + " frame_ms=" + (tFrame - tPlace))
            menu.close()
            sample += 1
            if (sample >= opens) finish()
            else next("rest")
        }
    }

    Connections {
        target: root.menu
        function onEntriesChanged() { if (root.measuring) root.builds += 1 }
    }
    Connections {
        target: root.menu ? root.menu.Window.window : null
        function onFrameSwapped() { if (root.measuring && root.menu.opened && root.tFrame === 0) root.tFrame = Date.now() }
    }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 800
        Flea.WindowBody { id: body; host: window }
        Item { anchors.fill: parent; TestEvent { id: driver } }
    }
    Timer { interval: root.pollMs; repeat: true; running: !root.finished; onTriggered: root.advance() }
}
