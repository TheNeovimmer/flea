//@ pragma ShellId flea-button-hueless-test

import QtQuick
import Quickshell
import "flea" as Flea
import "button-probe.js" as Probe

// tests/button-system.sh's third harness: where a theme's accent carries no colour (stock kanagawa and white) a focused set member keeps A's ring and its picked or muted frame, because an accent frame there would read as picked.
ShellRoot {
    id: shell

    // Quiet ticks, a count of frames and never time, before the window is up and the chips can take focus.
    readonly property int settleTicks: 4
    readonly property int tickMs: 16
    readonly property int outerTimeoutS: Number(Quickshell.env("BUTTONSYS_TIMEOUT_S")) || 60
    readonly property int capShare: 2
    readonly property int msPerSecond: 1000
    readonly property double startedAt: Date.now()
    readonly property int capMs: shell.outerTimeoutS * shell.msPerSecond / shell.capShare
    readonly property string rootDir: Quickshell.env("BUTTONSYS_ROOT") || ""

    property int checks: 0
    property int ticks: 0
    property var failures: []

    function log(line) { console.log("HUELESS " + line) }
    function check(name, actual, expected) {
        shell.checks += 1
        if (JSON.stringify(actual) === JSON.stringify(expected)) { shell.log("ok " + name); return }
        shell.failures.push(name)
        shell.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function finish() {
        shell.log("DONE checks=" + shell.checks + " failed=" + shell.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    FloatingWindow {
        id: window
        implicitWidth: 400
        implicitHeight: 120
        color: "#303030"

        Item {
            anchors.fill: parent
            Flea.ProtocolChip { id: picked; x: 20; y: 10; label: "Picked"; picked: true }
            Flea.ProtocolChip { id: unpicked; x: 140; y: 10; label: "Unpicked" }
            Item { id: parking; y: 100; width: 10; height: 10; focus: true }
        }
    }

    // One theme: its accent has no colour, so each focused chip draws its resting frame and the ring.
    function hueless(name, body) {
        var c = Flea.Theme.color, rgba = Probe.rgba
        Flea.Theme.applyColors(body)
        parking.forceActiveFocus()
        var cold = Probe.focusRead(unpicked)
        var warm = Probe.focusRead(picked)
        shell.check(name + ": the accent carries no colour", c.accentHasHue, false)
        shell.check(name + ": a focused unpicked member keeps its muted frame and label and shows the ring", [cold.frameColor, cold.ink, cold.ringShown], [rgba(c.muted), rgba(c.muted), true])
        shell.check(name + ": a focused picked member keeps its foreground frame and label and shows the ring", [warm.frameColor, warm.ink, warm.ringShown], [rgba(c.foreground), rgba(c.foreground), true])
        shell.check(name + ": an unpicked member keeps its muted frame and never reads as picked", cold.frameColor !== rgba(c.foreground), true)
    }

    function run() {
        var c = Flea.Theme.color, rgba = Probe.rgba
        var inside = shell.rootDir.length > 0 && (Quickshell.env("HOME") || "").indexOf(shell.rootDir + "/") === 0
        shell.check("sandbox: HOME lies under the harness root", inside, true)
        if (!inside) { shell.finish(); return }
        Flea.Theme.applyColors(Probe.COLOURED_THEME)
        shell.check("tokyo-night's accent has a hue, apart from its foreground", [c.accentHasHue, rgba(c.accent) !== rgba(c.foreground)], [true, true])
        shell.hueless("kanagawa", Probe.KANAGAWA_THEME)
        shell.hueless("white", Probe.WHITE_THEME)
        Flea.Theme.applyColors(Probe.COLOURED_THEME)
        parking.forceActiveFocus()
        var back = Probe.focusRead(unpicked)
        shell.check("the coloured accent is back with its focus frame and no ring", [c.accentHasHue, back.frameColor, back.ringShown], [true, rgba(c.accent), false])
        shell.finish()
    }

    Timer {
        interval: shell.tickMs
        repeat: true
        running: true
        onTriggered: {
            if (Date.now() - shell.startedAt > shell.capMs) {
                shell.failures.push("the harness did not finish")
                shell.log("FAIL the harness did not finish")
                shell.finish()
                running = false
                return
            }
            shell.ticks += 1
            if (shell.ticks === shell.settleTicks) { running = false; shell.run() }
        }
    }
}
