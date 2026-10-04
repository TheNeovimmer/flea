//@ pragma ShellId flea-chromering-test

import QtQuick
import Quickshell
import qs.Commons
import "flea" as Flea

// tests/chromering.sh's harness: the real ui/ChromeButton.qml, whose ring ButtonSystem040 A draws only for the keyboard.
ShellRoot {
    id: root

    // Qt Quick needs the window mapped and a frame laid out before a size is read.
    readonly property int layoutMs: 300
    readonly property int ringBoard: 24
    readonly property int ringStroke: 2
    readonly property int boardStop: 14
    // Theme's own ratios: the strip is this share of a row, and a row is its line box (1.8 x bodySmall) plus the padding above and below.
    readonly property real chromeRowRatio: 0.72
    readonly property real lineBoxRatio: 1.8
    // Every stop the Display section offers, from the smallest strip to the largest.
    readonly property var stops: [9, 10, 11, 12, 14, 16, 20]
    property int checks: 0
    property var failures: []

    function check(label, actual, expected) {
        root.checks += 1
        if (actual === expected) {
            console.log("CHROMERING ok " + label)
            return
        }
        root.failures.push(label)
        console.log("CHROMERING FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function report() {
        if (root.failures.length === 0)
            console.log("CHROMERING PASS " + root.checks + " checks")
        root.quit()
    }

    FloatingWindow {
        implicitWidth: 320
        implicitHeight: 120
        color: Flea.Theme.color.background

        Row {
            spacing: 12
            Flea.ChromeButton { id: rest; glyph: "x" }
            Flea.ChromeButton { id: hot; glyph: "x"; keyboardFocused: true }
            Flea.ChromeButton { id: off; glyph: "x"; keyboardFocused: true; enabled: false }
            Flea.ChromeButton { id: muted; glyph: "x"; keyboardFocused: true; restingColor: Flea.Theme.color.muted }
            Flea.ChromeButton { id: lit; glyph: "x"; active: true; keyboardFocused: true }
        }
    }

    Timer {
        interval: root.layoutMs
        running: true
        repeat: false
        onTriggered: root.run()
    }

    // A button with no ring item answers "no ring" for every ring read, so the build before the ring fails on the board's words and not on a TypeError.
    function ringRead(button, read) { return button.ringItem ? read(button.ringItem) : "no ring" }
    function markRead(button, read) { return button.markItem ? read(button.markItem) : "no mark" }
    // What a stop must draw, from the Omarchy tokens the product scales: the icon token over the base size, and the strip off the row's line box.
    function wantMark(stop) { return Math.round(Style.font.icon * stop / Style.font.baseSize) }
    function wantStrip(stop) {
        var row = Math.round(Flea.Theme.font.bodySmall * root.lineBoxRatio) + 2 * Flea.Theme.spacing.rowPaddingY
        return Math.round(row * root.chromeRowRatio)
    }
    function stopState(stop) { Flea.ViewState.load(JSON.stringify({ display: { textSize: { mode: stop } } })) }

    // Every read is synchronous on the settled layout; hover and press have no reader here because the ring never depends on them.
    function run() {
        var shown = function (ring) { return ring.visible }
        root.stopState(root.boardStop)
        check("the hit box is at least the 24 board square", hot.implicitWidth >= root.ringBoard, true)
        check("a resting mark draws no ring", ringRead(rest, shown), false)
        check("a keyboard-focused mark draws its ring", ringRead(hot, shown), true)
        check("the ring is the board's 24 x 24 at the board's size", ringRead(hot, function (ring) { return ring.width + "x" + ring.height }), root.ringBoard + "x" + root.ringBoard)
        check("the ring is a 2 px frame", ringRead(hot, function (ring) { return ring.border.width }), root.ringStroke)
        check("the ring is the foreground", ringRead(hot, function (ring) { return String(ring.border.color) }), String(Flea.Theme.color.foreground))
        check("the ring has no fill", ringRead(hot, function (ring) { return ring.color.a }), 0)
        check("a disabled mark draws no ring", ringRead(off, shown), false)
        check("a disabled mark mutes its glyph", markRead(off, function (mark) { return String(mark.color) }), String(Flea.Theme.color.muted))
        check("a muted resting mark inks in the foreground under the ring", markRead(muted, function (mark) { return String(mark.color) }), String(Flea.Theme.color.foreground))
        check("an active mark still takes the ring", ringRead(lit, shown), true)
        check("a resting mark inks in the foreground", markRead(rest, function (mark) { return String(mark.color) }), String(Flea.Theme.color.foreground))
        var marks = {}
        var strips = {}
        for (var i = 0; i < root.stops.length; i++) {
            root.stopState(root.stops[i])
            var tag = "stop " + root.stops[i] + " "
            var inside = function (ring) {
                return ring.x >= 0 && ring.y >= 0 && ring.x + ring.width <= hot.width && ring.y + ring.height <= hot.height }
            var centre = function (ring) {
                return (ring.x * 2 + ring.width) + "," + (ring.y * 2 + ring.height) }
            var markCentre = markRead(hot, function (mark) { return (mark.x * 2 + mark.width) + "," + (mark.y * 2 + mark.height) })
            check(tag + "the ring stays inside the hit box", ringRead(hot, inside), true)
            check(tag + "the ring leaves a hairline above and below", ringRead(hot, function (ring) { return ring.y >= Flea.Theme.spacing.hairline && hot.height - ring.y - ring.height >= Flea.Theme.spacing.hairline }), true)
            check(tag + "the ring shares the glyph's centre, so both sit on whole pixels together", ringRead(hot, centre), markCentre)
            check(tag + "the glyph keeps the chrome mark size under the ring", markRead(hot, function (mark) { return mark.width }), Flea.Theme.chromeMarkSize)
            check(tag + "the mark is the icon token scaled to the stop", markRead(hot, function (mark) { return mark.width }), root.wantMark(root.stops[i]))
            check(tag + "the hit box is as wide as the larger of the 24 floor and the mark", hot.width, Math.max(root.ringBoard, root.wantMark(root.stops[i])))
            check(tag + "the hit box is the strip's height off the row", hot.height, root.wantStrip(root.stops[i]))
            marks[root.wantMark(root.stops[i])] = true
            strips[root.wantStrip(root.stops[i])] = true
        }
        check("the stops draw more than one mark size", Object.keys(marks).length > 1, true)
        check("the stops draw more than one hit box height", Object.keys(strips).length > 1, true)
        report()
    }
}
