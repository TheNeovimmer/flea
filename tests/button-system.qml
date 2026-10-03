//@ pragma ShellId flea-button-system-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Recent.js" as Recent
import "flea/js/TextSize.js" as TextSize

// tests/button-system.sh's harness: the real TrashView strip's Empty Trash and a destructive Flea.DialogButton draw one ladder in five states.
ShellRoot {
    id: shell

    // GM's ruling, ButtonSystem040 A (2026-09-24): the numbers the drawn items are held to.
    readonly property real rulingHover: 0.08
    readonly property real rulingPress: 0.14
    readonly property real rulingPressScale: 0.96
    readonly property real rulingDisabled: 0.55
    readonly property int rulingRing: 2
    readonly property real alphaEpsilon: 0.002
    // The pointer parks here, clear of both controls, and presses are released far outside so no tap fires.
    readonly property int parkX: 700
    readonly property int parkY: 50
    readonly property int releaseOutside: -40
    readonly property int noDelay: 0
    // Quiet ticks (the press scale unchanged) before a state is read; a count of frames, never time.
    readonly property int settleTicks: 4
    readonly property int tickMs: 16
    readonly property int outerTimeoutS: Number(Quickshell.env("BUTTONSYS_TIMEOUT_S")) || 60
    readonly property int capShare: 2
    readonly property int msPerSecond: 1000
    readonly property double startedAt: Date.now()
    // Elapsed time, not ticks: half the .sh's outer timeout, so "did not finish" fires first whenever qs starts inside that half.
    readonly property int capMs: shell.outerTimeoutS * shell.msPerSecond / shell.capShare
    readonly property int chainCap: 200
    readonly property int trashRows: 3
    // GM's text size, where the strip is 27 and its control 20 (ButtonSystem040).
    readonly property int pinnedSize: 14
    // The drawn values two controls must share in every state, in the order they are reported.
    readonly property var ladder: ["frameColor", "frameWidth", "ink", "wash", "ringShown", "ringWidth", "ringColor", "ringOutset", "scale", "opacity"]
    readonly property var states: ["rest", "hover", "focus", "pressed", "disabled"]

    property int checks: 0
    property var failures: []
    property var readings: ({ strip: ({}), dialog: ({}) })
    property int activations: 0
    property int step: 0
    property int quiet: 0
    property real lastScaleA: -1
    property real lastScaleB: -1
    property bool acted: false
    property var script: []
    // The root every path this run touches must lie under, and the ops the strip sent to the backend this run never has.
    readonly property string sandboxRoot: Quickshell.env("BUTTONSYS_ROOT") || ""
    property var requestedOps: []
    readonly property var destructiveOps: ["delete", "restore"]

    function log(line) { console.log("BUTTONSYS " + line) }
    function check(name, actual, expected) {
        shell.checks += 1
        if (JSON.stringify(actual) === JSON.stringify(expected)) {
            shell.log("ok " + name)
            return
        }
        shell.failures.push(name)
        shell.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function finish() {
        shell.log("DONE checks=" + shell.checks + " failed=" + shell.failures.length)
        shell.step = shell.script.length + 1
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    function rgba(c) {
        return [c.r, c.g, c.b, c.a].map(function (v) { return Math.round(v * 1000) / 1000 }).join(",")
    }
    // A wash with no alpha draws nothing, whatever ink it carries.
    function washRgba(c) { return c.a === 0 ? "0,0,0,0" : shell.rgba(c) }
    function alphaOf(c) { return Math.round(c.a * 1000) / 1000 }
    function find(item, name) {
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o.objectName === name) return o
            var kids = o.children !== undefined ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return null
    }

    // What the control draws now, read off its own items; an item the recipe lacks reads as absent.
    function read(button) {
        var frame = shell.find(button, "buttonFrame")
        var washItem = shell.find(button, "buttonWash") || frame
        var label = shell.find(button, "buttonLabel")
        var ring = shell.find(button, "buttonRing")
        var corner = ring ? ring.mapToItem(frame, 0, 0) : null
        return {
            frameColor: shell.rgba(frame.border.color), frameWidth: frame.border.width,
            ink: shell.rgba(label.color), wash: shell.washRgba(washItem.color), washAlpha: shell.alphaOf(washItem.color),
            ringShown: ring !== null && ring.visible, ringWidth: ring ? ring.border.width : 0,
            ringColor: ring ? shell.rgba(ring.border.color) : "none", ringOutset: corner ? Math.round(-corner.x * 1000) / 1000 : 0,
            scale: button.scale, opacity: button.opacity,
            frameHeight: frame.height, labelSize: label.font.pixelSize
        }
    }

    FloatingWindow {
        id: window
        implicitWidth: 800
        implicitHeight: 480
        color: "#303030"

        Item {
            id: stripHost
            width: 800
            height: 300
            Flea.TrashView {
                id: view
                opened: true
                total: shell.trashRows
            }
        }

        Item {
            id: dialogHost
            y: 320
            width: 800
            height: 100
            Flea.DialogButton {
                id: dialog
                x: 40
                y: 20
                label: "Empty Trash"
                destructive: true
                onActivated: shell.activations += 1
            }
        }

        // Somewhere for the keyboard to rest where it draws nothing.
        Item { id: parking; y: 440; width: 10; height: 10; focus: true }

        TestEvent { id: driver }
    }

    // No backend answers in this harness, so a request the view sends is dropped and the view reads as idle.
    Connections {
        target: view
        function onRequested(message) { shell.requestedOps.push(message.op); view.pendingOp = "" }
    }
    Connections {
        target: view.emptyItem
        function onActivated() { shell.activations += 1 }
    }

    readonly property var strip: view.emptyItem
    readonly property var dlg: dialog

    function settled() {
        var a = shell.strip.scale
        var b = shell.dlg.scale
        var same = a === shell.lastScaleA && b === shell.lastScaleB
        shell.lastScaleA = a
        shell.lastScaleB = b
        shell.quiet = same ? shell.quiet + 1 : 0
        return shell.quiet >= shell.settleTicks
    }
    function centre(item) { return { x: item.width / 2, y: item.height / 2 } }
    function park() { driver.mouseMove(dialogHost, shell.parkX, shell.parkY, shell.noDelay, Qt.NoButton, Qt.NoModifier) }
    function hoverOn(item) { var c = shell.centre(item); driver.mouseMove(item, c.x, c.y, shell.noDelay, Qt.NoButton, Qt.NoModifier) }
    function pressOn(item) { var c = shell.centre(item); driver.mousePress(item, c.x, c.y, Qt.LeftButton, Qt.NoModifier, shell.noDelay) }
    function releaseOff(item) { driver.mouseRelease(item, shell.releaseOutside, shell.releaseOutside, Qt.LeftButton, Qt.NoModifier, shell.noDelay) }
    function setAvailable(which, on) {
        if (which === "strip") {
            view.total = on ? shell.trashRows : 0
            view.pendingOp = ""
        } else {
            dialog.available = on
        }
    }

    // One control through the five states; each act leaves the pointer and keyboard as the state needs them.
    function seriesFor(which) {
        var item = which === "strip" ? shell.strip : shell.dlg
        function record(state) { return function () { shell.readings[which][state] = shell.read(item) } }
        return [
            { name: which + ":rest", act: function () { parking.forceActiveFocus(); shell.park() }, record: record("rest") },
            { name: which + ":hover", act: function () { shell.hoverOn(item) }, record: record("hover") },
            { name: which + ":focus", act: function () { shell.park(); item.forceActiveFocus() }, record: function () {
                shell.readings[which].focus = shell.read(item)
                shell.readings[which].focusRing = shell.ringBox(item, which)
            } },
            { name: which + ":pressed", act: function () { parking.forceActiveFocus(); shell.hoverOn(item); shell.pressOn(item) }, record: record("pressed") },
            { name: which + ":released", act: function () { shell.releaseOff(item); shell.park() }, record: function () {
                shell.check(which + ": a press released outside does not activate", shell.activations, 0)
            } },
            { name: which + ":disabled", act: function () { shell.setAvailable(which, false) }, record: record("disabled") },
            { name: which + ":disabled-input", act: function () {
                item.forceActiveFocus(); shell.hoverOn(item); shell.pressOn(item); shell.releaseOff(item)
                driver.keyClick(Qt.Key_Return, Qt.NoModifier, shell.noDelay)
            }, record: function () {
                shell.check(which + ": a disabled control activates on neither pointer nor Return", shell.activations, 0)
                shell.setAvailable(which, true)
            } }
        ]
    }

    // The focus ring in the strip's own coordinates, or the dialog button's.
    function ringBox(item, which) {
        var ring = shell.find(item, "buttonRing")
        if (!ring) return null
        var host = which === "strip" ? view.stripItem : dialogHost
        var box = ring.mapToItem(host, 0, 0)
        return { x: box.x, y: box.y, w: ring.width, h: ring.height, hostW: host.width, hostH: host.height }
    }

    function compare(state) {
        var a = shell.readings.strip[state]
        var b = shell.readings.dialog[state]
        for (var i = 0; i < shell.ladder.length; i++) {
            var key = shell.ladder[i]
            shell.check(state + ": the strip and the dialog draw the same " + key + " (strip " + a[key] + ", dialog " + b[key] + ")", a[key], b[key])
        }
    }

    // The ruling itself, so two controls drifting together still fail.
    function ruling() {
        var muted = shell.rgba(Flea.Theme.color.muted)
        var error = shell.rgba(Flea.Theme.color.error)
        var foreground = shell.rgba(Flea.Theme.color.foreground)
        var s = shell.readings.strip
        for (var i = 0; i < shell.states.length; i++) {
            var state = shell.states[i]
            shell.check(state + ": the frame is the muted frame and never changes", s[state].frameColor, muted)
            shell.check(state + ": the frame is one hairline", s[state].frameWidth, Flea.Theme.spacing.hairline)
            shell.check(state + ": a destructive label inks error (muted when disabled)", s[state].ink, state === "disabled" ? muted : error)
        }
        shell.check("rest: no wash", s.rest.washAlpha, 0)
        shell.check("hover: the wash is 8% of the ink", Math.abs(s.hover.washAlpha - shell.rulingHover) < shell.alphaEpsilon, true)
        shell.check("hover: the wash is the label's ink", s.hover.wash, error.split(",").slice(0, 3).concat([s.hover.washAlpha]).join(","))
        shell.check("focus: no wash and a 2 px foreground ring outside the frame",
                    [s.focus.washAlpha, s.focus.ringShown, s.focus.ringWidth, s.focus.ringColor, s.focus.ringOutset],
                    [0, true, shell.rulingRing, foreground, shell.rulingRing])
        shell.check("rest and hover: no ring", [s.rest.ringShown, s.hover.ringShown], [false, false])
        shell.check("pressed: the wash is 14% of the ink and the control takes the 0.96 press", [Math.abs(s.pressed.washAlpha - shell.rulingPress) < shell.alphaEpsilon, s.pressed.scale], [true, shell.rulingPressScale])
        shell.check("rest: no press scale", s.rest.scale, 1)
        shell.check("disabled: 0.55 opacity and no wash", [s.disabled.opacity, s.disabled.washAlpha], [shell.rulingDisabled, 0])
        shell.check("rest: full opacity", s.rest.opacity, 1)
    }

    // The two controls differ in height and label size, and in nothing else.
    function geometry() {
        var s = shell.readings.strip.rest
        var d = shell.readings.dialog.rest
        shell.check("dialog: a 30 px frame at body size", [d.frameHeight, d.labelSize], [Flea.Theme.rowHeight - Flea.Theme.spacing.rowPaddingY, Flea.Theme.font.body])
        shell.check("strip: the control height at caption size", [s.frameHeight, s.labelSize], [Flea.Theme.chromeControlHeight, Flea.Theme.font.caption])
        var frame = shell.find(shell.strip, "buttonFrame")
        var top = frame.mapToItem(shell.strip, 0, 0).y
        shell.check("strip: the press area fills the strip and clears the 24 px floor", [shell.strip.height, shell.strip.height >= Flea.Theme.hitMin], [Flea.Theme.chromeHeight, true])
        shell.check("strip: the frame is centred in the strip less its rule", top, Math.round((shell.strip.height - Flea.Theme.spacing.hairline - frame.height) / 2))
        var ring = shell.readings.strip.focusRing
        shell.check("strip: the focus ring lies inside the strip, above its rule",
                    ring !== null && ring.x >= 0 && ring.y >= 0 && ring.x + ring.w <= ring.hostW && ring.y + ring.h <= ring.hostH - Flea.Theme.spacing.hairline, true)
        shell.check("both: one accessible name and the button role",
                    [shell.strip.Accessible.name, shell.strip.Accessible.role === Accessible.Button, shell.dlg.Accessible.name, shell.dlg.Accessible.role === Accessible.Button],
                    ["Empty Trash", true, "Empty Trash", true])
    }

    // Press, keys and Tab on the live controls.
    function inputs() {
        var frame = shell.find(shell.strip, "buttonFrame")
        var gap = frame.mapToItem(shell.strip, 0, 0).y
        shell.check("strip: the pointer reaches the press area above the drawn frame", gap > 1, true)
        shell.activations = 0
        driver.mouseClick(shell.strip, shell.strip.width / 2, 1, Qt.LeftButton, Qt.NoModifier, shell.noDelay)
        shell.check("strip: a click in the press area above the frame activates", shell.activations, 1)
        var keys = [["Return", Qt.Key_Return], ["Enter", Qt.Key_Enter], ["Space", Qt.Key_Space]]
        for (var k = 0; k < keys.length; k++) {
            shell.activations = 0
            shell.strip.forceActiveFocus()
            driver.keyClick(keys[k][1], Qt.NoModifier, shell.noDelay)
            shell.check("strip: " + keys[k][0] + " activates it", shell.activations, 1)
            shell.activations = 0
            shell.dlg.forceActiveFocus()
            driver.keyClick(keys[k][1], Qt.NoModifier, shell.noDelay)
            shell.check("dialog: " + keys[k][0] + " activates it", shell.activations, 1)
        }
        var seen = false
        var at = view
        for (var n = 0; n < shell.chainCap && !seen; n++) {
            at = at.nextItemInFocusChain(true)
            if (at === shell.strip) seen = true
            if (at === view || at === null) break
        }
        shell.check("strip: Tab reaches it in the focus chain", [shell.strip.activeFocusOnTab, seen], [true, true])
    }

    // open() leaves the keyboard on the view, trashFocusEmpty gives it to the strip button, and restore() is trashFocusListing's body in ui/Ipc.qml (the .sh pins the two together).
    function restore() { view.emptyItem.focus = false; view.forceActiveFocus() }
    function handback() {
        view.forceActiveFocus()
        shell.check("open() leaves the keyboard on the Trash view, not on the button", [view.activeFocus, view.emptyItem.activeFocus], [true, false])
        view.emptyItem.forceActiveFocus(Qt.TabFocusReason)
        shell.check("trashFocusEmpty gives the keyboard to the strip button", view.emptyItem.activeFocus, true)
        shell.restore()
        shell.check("trashFocusListing takes the keyboard back from the strip button", [view.activeFocus, view.emptyItem.activeFocus], [true, false])
    }

    Timer {
        interval: shell.tickMs
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    // Under the marked root, with no parent hop; a path outside it, or a harness started with no root, fails closed before any control is activated.
    function underRoot(path) {
        return shell.sandboxRoot.length > 0 && path.indexOf(shell.sandboxRoot + "/") === 0 && path.split("/").indexOf("..") < 0
    }
    // Sample input: "/root/data/recently-used.xbel" gives "/root/data", the data home the product resolved.
    function productDataHome() {
        var file = Recent.historyPath(Quickshell.env("XDG_DATA_HOME"), Quickshell.env("HOME"))
        return file.slice(0, file.length - Recent.HISTORY_LEAF.length - 1)
    }
    // The first five rows are the environment this run was given, the rest paths the product resolved from it; gio's Trash is the product's data home plus /Trash.
    function pinned() {
        var home = Quickshell.env("HOME") || ""
        var paths = [
            ["HOME", home],
            ["XDG_DATA_HOME", Quickshell.env("XDG_DATA_HOME") || home + "/.local/share"],
            ["XDG_CONFIG_HOME", Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"],
            ["XDG_STATE_HOME", Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"],
            ["XDG_CACHE_HOME", Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"],
            ["the Trash directory under the product's data home", shell.productDataHome() + "/Trash"],
            ["the view's home", view.home],
            ["the scripts directory", Flea.Scripts.directory],
            ["the state file ViewState reads", Flea.ViewState.store.path]
        ]
        var ok = true
        for (var i = 0; i < paths.length; i++) {
            var inside = shell.underRoot(paths[i][1])
            shell.check("sandbox: " + paths[i][0] + " lies under the harness root", inside, true)
            if (!inside) ok = false
        }
        return ok
    }

    function buildScript() {
        // First, while the strip button has never held the keyboard, as it has not when open() runs on a fresh view.
        var steps = [{ name: "handback", act: function () {}, record: shell.handback }]
        steps = steps.concat(shell.seriesFor("strip"), shell.seriesFor("dialog"))
        steps.push({ name: "compare", act: function () {}, record: function () {
            shell.check("strip: the harness drove an available control", view.emptyItem.available, true)
            shell.check("the harness draws at GM's text size", Flea.Theme.baseSize, shell.pinnedSize)
            shell.check("the harness runs with motion on, so the press scale is drawn", Flea.Theme.reducedMotion, false)
            for (var i = 0; i < shell.states.length; i++) shell.compare(shell.states[i])
            shell.ruling()
            shell.geometry()
            shell.inputs()
            shell.check("no delete or restore request was sent", shell.requestedOps.filter(function (op) { return shell.destructiveOps.indexOf(op) >= 0 }), [])
            shell.check("the confirmation card never opened, so no key could confirm it", view.confirmationOpen, false)
        } })
        shell.script = steps
    }

    function advance() {
        if (Date.now() - shell.startedAt > shell.capMs) {
            shell.failures.push("the harness did not finish")
            shell.log("FAIL the harness did not finish at step " + shell.step)
            shell.finish()
            return
        }
        if (shell.step > shell.script.length) return
        if (shell.script.length === 0) {
            if (!shell.pinned()) { shell.finish(); return }
            // Assigned only once every path is proved under the root, because the store may write on assignment.
            Flea.ViewState.state = { display: { textSize: { mode: TextSize.nearest(shell.pinnedSize) } } }
            shell.buildScript()
            return
        }
        if (shell.step === shell.script.length) { shell.finish(); return }
        var current = shell.script[shell.step]
        if (!shell.acted) {
            current.act()
            shell.acted = true
            shell.quiet = 0
            return
        }
        if (!shell.settled()) return
        current.record()
        shell.acted = false
        shell.step += 1
    }
}
