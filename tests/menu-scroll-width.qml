//@ pragma ShellId flea-menu-scroll-width-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Scroll.js" as Scroll

// tests/menu-scroll-width.sh's harness: an overflowing context menu draws no bar in any state and
// steps the highlight on wheel and touchpad, while an ordinary CardScroll keeps pixel scrolling.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0
    property string shortNote: ""

    function log(line) { console.log("MENUSCROLL " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        if (!cond) shell.failures.push(name + " got " + detail)
    }
    function isType(o, name) {
        var s = String(o)
        return s.indexOf(name) === 0 || s.indexOf("QQuick" + name) === 0
    }
    function findFirst(item, name) {
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o !== item && shell.isType(o, name)) return o
            var kids = (o && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return null
    }
    // A wheel event as FastScrollHandler reads it: phase 0 is a notch, 1/2/3 a touchpad stroke.
    function notch(down) {
        return { phase: 0, pixelDelta: { x: 0, y: 0 }, angleDelta: { x: 0, y: down ? -120 : 120 },
                 modifiers: 0, accepted: false }
    }
    function stroke(phase, pixels) {
        return { phase: phase, pixelDelta: { x: 0, y: pixels }, angleDelta: { x: 0, y: 0 },
                 modifiers: 0, accepted: false }
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        Flea.CardScroll {
            id: plain
            width: 320
            height: 200
            Column { width: parent.width; Repeater { model: 40; Text { text: "line " + index } } }
        }

        Flea.ContextMenu {
            id: menu
            anchors.fill: parent
            opened: true
        }
    }

    // Sample input: entries(2, false) is two file rows; withSub puts a flyout on the first.
    function entries(n, withSub) {
        var out = []
        for (var i = 0; i < n; i++) {
            var e = { label: "Row " + i, action: "noop" + i, glyph: "file" }
            if (withSub && i === 0)
                e.submenu = [{ id: "a", label: "App A" }, { id: "b", label: "App B" }]
            out.push(e)
        }
        return out
    }

    function ready(main) {
        return main && main.contentHeight > 0 && main.holderWidth > 0
    }

    function barUnder(item) { return shell.findFirst(item, "ViewportScrollBar") }
    function handlerUnder(item) { return shell.findFirst(item, "FastScrollHandler") }

    function measure(tag) {
        var main = shell.findFirst(menu.frameItem, "CardScroll")
        var sub = shell.findFirst(menu.submenuFrameItem, "CardScroll")
        if (!main || !sub) {
            shell.failures.push(tag + " menu bodies not found")
            return ""
        }
        // No bar item anywhere in either menu body, short or overflowing, at rest or mid-wheel.
        shell.check(tag + ":main-nobar", shell.barUnder(menu.frameItem) === null, "a bar stands")
        shell.check(tag + ":flyout-nobar", shell.barUnder(menu.submenuFrameItem) === null, "a bar stands")
        // Rows span the frame: the holder keeps no lane and the row fills it.
        shell.check(tag + ":main-holder", main.holderWidth === main.width,
                    String(main.holderWidth) + "/" + String(main.width))
        shell.check(tag + ":main-row", menu.itemFor(0).width === main.holderWidth,
                    String(menu.itemFor(0).width))
        shell.check(tag + ":flyout-holder", sub.holderWidth === sub.width,
                    String(sub.holderWidth) + "/" + String(sub.width))
        // Both bodies step the highlight, with the row height a touchpad stroke spends.
        var mh = shell.handlerUnder(main)
        var sh = shell.handlerUnder(sub)
        shell.check(tag + ":main-step", mh && mh.stepMode === true, "pixel scroll")
        shell.check(tag + ":flyout-step", sh && sh.stepMode === true, "pixel scroll")
        shell.check(tag + ":step-row", mh && mh.stepRowHeight === Flea.Theme.rowHeight,
                    String(mh ? mh.stepRowHeight : "none"))
        // The dialog body keeps pixel scrolling and itself carries no bar either.
        shell.check(tag + ":plain-nobar", shell.barUnder(plain) === null, "a bar stands")
        shell.check(tag + ":plain-holder", plain.holderWidth === plain.width,
                    String(plain.holderWidth) + "/" + String(plain.width))
        var ph = shell.handlerUnder(plain)
        shell.check(tag + ":plain-pixel", ph && ph.stepMode === false, "stepping")
        return tag + " frame=" + Math.round(main.width) + " holder=" + Math.round(main.holderWidth)
    }

    function wheelDown(handler, n) {
        for (var i = 0; i < n; i++)
            handler.handleWheel(shell.notch(true))
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function advance() {
        shell.ticks += 1
        var main = menu.frameItem ? shell.findFirst(menu.frameItem, "CardScroll") : null
        if (shell.phase === 0 && shell.ticks >= 2) {
            menu.entries = shell.entries(3, true)
            menu.openSubmenu(0)
            shell.phase = 1
            shell.ticks = 0
        } else if (shell.phase === 1 && (shell.ready(main) || shell.ticks > 50)) {
            shell.shortNote = shell.measure("short")
            menu.entries = shell.entries(60, true)
            menu.openSubmenu(0)
            menu.cursor = menu.stepCursor(-1, 1)
            shell.phase = 2
            shell.ticks = 0
        } else if (shell.phase === 2 && (shell.ready(main) || shell.ticks > 50)) {
            var longNote = shell.measure("long")
            var mh = shell.handlerUnder(main)
            var sub = shell.findFirst(menu.submenuFrameItem, "CardScroll")
            var sh = shell.handlerUnder(sub)
            var rowH = Flea.Theme.rowHeight
            // A notch steps the highlight one row, like Down, and the body follows it.
            var at = menu.cursor
            shell.wheelDown(mh, 3)
            shell.check("long:wheel-3", menu.cursor === at + 3, String(menu.cursor))
            shell.wheelDown(mh, 56)
            shell.check("long:wheel-end", menu.cursor === 59, String(menu.cursor))
            shell.check("long:revealed", main.contentY > 0, String(main.contentY))
            mh.handleWheel(shell.notch(false))
            shell.check("long:wheel-up", menu.cursor === 58, String(menu.cursor))
            // A touchpad stroke steps one row per row height of tp1-gained travel, and no
            // more: raw pixels ride through Scroll's touch gain, so a row costs rowH / gain.
            var before = menu.cursor
            var rawRow = rowH / Scroll.TOUCH_GAIN
            for (var s = 0; s < 4; s++) {
                mh.handleWheel(shell.stroke(1, rawRow))
                mh.handleWheel(shell.stroke(2, 0))
            }
            shell.check("long:touch-4", menu.cursor === before - 4, String(menu.cursor))
            mh.handleWheel(shell.stroke(1, rawRow - 1))
            mh.handleWheel(shell.stroke(2, 0))
            mh.handleWheel(shell.stroke(3, 0))
            shell.check("long:touch-partial", menu.cursor === before - 4, String(menu.cursor))
            shell.check("long:no-tail", mh.tailRunning === false, "a tail runs")
            // The flyout steps through its own cursor on the same wheel.
            var sat = menu.submenuCursor
            sh.handleWheel(shell.notch(true))
            shell.check("long:flyout-wheel", menu.submenuCursor === sat + 1,
                        String(menu.submenuCursor))
            // Still no bar after wheeling, and a shut menu keeps nothing standing.
            shell.check("long:bar-after-wheel", shell.barUnder(menu.frameItem) === null, "a bar stands")
            menu.close()
            shell.check("long:shut", menu.opened === false, "still open")
            if (shell.failures.length === 0)
                shell.log("PASS " + shell.shortNote + " " + longNote
                          + " text=" + Flea.Theme.font.body + "/" + Flea.Theme.font.caption
                          + " pad=" + Flea.Theme.spacing.rowPaddingX)
            else
                for (var i = 0; i < shell.failures.length; i++)
                    shell.log("FAIL " + shell.failures[i])
            shell.log("DONE failures=" + shell.failures.length)
            shell.phase = 3
            shell.quit()
        }
    }
}
