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
    property string longNote: ""

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
    // A hi-res notch fragment in raw angleDelta units, and a phaseless pixel nudge.
    function frag(down, units) {
        return { phase: 0, pixelDelta: { x: 0, y: 0 }, angleDelta: { x: 0, y: down ? -units : units },
                 modifiers: 0, accepted: false }
    }
    function nudge(pixels) {
        return { phase: 0, pixelDelta: { x: 0, y: pixels }, angleDelta: { x: 0, y: 0 },
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

        Flea.OpenWithDialog {
            id: openWith
            anchors.fill: parent
        }
    }

    // Sample input: entries(2, false) is two file rows; withSub puts a flyout on the
    // first, or on subAt when given.
    function entries(n, withSub, subAt) {
        var at = subAt === undefined ? 0 : subAt
        var out = []
        for (var i = 0; i < n; i++) {
            var e = { label: "Row " + i, action: "noop" + i, glyph: "file" }
            if (withSub && i === at)
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
    // The stepping handler under an item: the Open with dialog holds a pixel body handler
    // beside its list's stepping one, so the first match is not always the stepping one.
    function stepHandlerUnder(item) {
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o !== item && shell.isType(o, "FastScrollHandler") && o.stepMode === true)
                return o
            var kids = (o && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return null
    }

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
    // Drops a menu body's wheel remainders where the production open does; guarded so the
    // suite reports rather than throws on a tree without the reset.
    function resetStepsOf(card) {
        if (card.resetSteps !== undefined)
            card.resetSteps()
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
            shell.longNote = shell.measure("long")
            var mh = shell.handlerUnder(main)
            var sub = shell.findFirst(menu.submenuFrameItem, "CardScroll")
            var sh = shell.handlerUnder(sub)
            var rowH = Flea.Theme.rowHeight
            // The flyout steps through its own cursor on the same wheel; first, while the
            // phase-1 openSubmenu(0) is still standing, because a main-frame wheel below closes it.
            var sat = menu.submenuCursor
            sh.handleWheel(shell.notch(true))
            shell.check("long:flyout-wheel", menu.submenuCursor === sat + 1,
                        String(menu.submenuCursor))
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
            // Hi-res fragments accumulate to one row per notch, never one row per event.
            // The cursor parks mid-list, so no clamp hides a runaway the way the end would.
            menu.cursor = 30
            shell.resetStepsOf(main)
            var hiAt = menu.cursor
            for (var f = 0; f < 8; f++)
                mh.handleWheel(shell.frag(true, 15))
            shell.check("long:hires-8", menu.cursor === hiAt + 1, String(menu.cursor))
            shell.resetStepsOf(main)
            hiAt = menu.cursor
            for (var g = 0; g < 4; g++)
                mh.handleWheel(shell.frag(true, 15))
            shell.check("long:hires-4-none", menu.cursor === hiAt, String(menu.cursor))
            for (var h = 0; h < 4; h++)
                mh.handleWheel(shell.frag(true, 15))
            shell.check("long:hires-4-more", menu.cursor === hiAt + 1, String(menu.cursor))
            // A direction flip drops the remainder instead of spending it back.
            shell.resetStepsOf(main)
            hiAt = menu.cursor
            for (var u = 0; u < 4; u++)
                mh.handleWheel(shell.frag(false, 15))
            mh.handleWheel(shell.frag(true, 15))
            shell.check("long:hires-flip", menu.cursor === hiAt, String(menu.cursor))
            shell.check("long:hires-flip-drops", mh.notchAccum === -15, String(mh.notchAccum))
            // Phaseless pixels fold by row height: twenty -2 nudges are one row, not twenty.
            menu.cursor = 30
            shell.resetStepsOf(main)
            var pxAt = menu.cursor
            for (var n = 0; n < 20; n++)
                mh.handleWheel(shell.nudge(-2))
            var pxWant = pxAt + Math.floor(40 / rowH)
            shell.check("long:pixel-fold", menu.cursor === pxWant,
                        String(menu.cursor) + "/" + String(pxWant))
            shell.check("long:pixel-not-per-event", menu.cursor !== pxAt + 20,
                        String(menu.cursor))
            // Still no bar after wheeling, then on to the flyout behaviour below.
            shell.check("long:bar-after-wheel", shell.barUnder(menu.frameItem) === null, "a bar stands")
            shell.phase = 3
            shell.ticks = 0
        } else if (shell.phase === 3 && shell.ticks >= 2) {
            // Five entries with the flyout on row 1: a wheel over the main frame closes the
            // flyout first and then steps, so the highlight never moves where it is not drawn.
            menu.entries = shell.entries(5, true, 1)
            menu.cursor = 1
            menu.openSubmenu(1)
            var main3 = shell.findFirst(menu.frameItem, "CardScroll")
            var mh3 = shell.handlerUnder(main3)
            shell.resetStepsOf(main3)
            mh3.handleWheel(shell.notch(true))
            shell.check("flyout:main-closes", menu.submenuOpen === false, "still open")
            shell.check("flyout:main-steps", menu.cursor === 2, String(menu.cursor))
            shell.check("flyout:main-drawn", menu.itemFor(2).current === true, "not current")
            // Down, the cursorDown action's own stepRow call, moves to row 3 from there.
            menu.cursor = menu.stepCursor(menu.cursor, 1)
            shell.check("flyout:down-after", menu.cursor === 3, String(menu.cursor))
            // A wheel over the flyout steps the flyout's own cursor and leaves the main one alone.
            menu.openSubmenu(1)
            var sub3 = shell.findFirst(menu.submenuFrameItem, "CardScroll")
            var sh3 = shell.handlerUnder(sub3)
            var heldCursor = menu.cursor
            var heldSub = menu.submenuCursor
            sh3.handleWheel(shell.notch(true))
            shell.check("flyout:flyout-steps", menu.submenuCursor === heldSub + 1,
                        String(menu.submenuCursor))
            shell.check("flyout:main-held", menu.cursor === heldCursor, String(menu.cursor))
            shell.phase = 4
            shell.ticks = 0
        } else if (shell.phase === 4 && shell.ticks >= 2) {
            // Open with: a wheel step moves the cursor only, never the focus, and a busy
            // list answers nothing. The pointer's own rule, now the wheel's too.
            openWith.handlers = [{ id: "a", label: "App A" }, { id: "b", label: "App B" },
                                 { id: "c", label: "App C" }]
            openWith.installed = []
            openWith.kind = "text"
            openWith.busy = false
            openWith.cursor = 0
            openWith.opened = true
            var oh = shell.stepHandlerUnder(openWith)
            shell.check("openwith:stepper", oh !== null, "no stepping handler")
            openWith.focusPart = 3
            openWith.closeItem.forceActiveFocus()
            oh.handleWheel(shell.notch(true))
            shell.check("openwith:wheel-keeps-part", openWith.focusPart === 3,
                        String(openWith.focusPart))
            shell.check("openwith:wheel-steps", openWith.cursor === 1, String(openWith.cursor))
            // The search field keeps focus across a wheel step, so Space stays a character.
            openWith.focusPart = 0
            openWith.fieldItem.forceActiveFocus()
            var alwaysAt = openWith.always
            oh.handleWheel(shell.notch(true))
            shell.check("openwith:field-keeps-part", openWith.focusPart === 0,
                        String(openWith.focusPart))
            shell.check("openwith:field-keeps-focus", openWith.fieldItem.activeFocus === true,
                        "field lost focus")
            shell.check("openwith:field-no-toggle", openWith.always === alwaysAt, "toggled")
            // Cursor 0 of three, where an unguarded notch would land on 1, so only the busy guard holds it.
            openWith.busy = true
            openWith.cursor = 0
            var busyAt = openWith.cursor
            oh.handleWheel(shell.notch(true))
            shell.check("openwith:busy-holds", openWith.cursor === busyAt, String(openWith.cursor))
            openWith.busy = false
            openWith.opened = false
            shell.phase = 5
            shell.ticks = 0
        } else if (shell.phase === 5 && shell.ticks >= 2) {
            // Opening the menu drops every wheel remainder, so one menu never spends another's.
            menu.entries = shell.entries(3, true)
            menu.cursor = 0
            var main5 = shell.findFirst(menu.frameItem, "CardScroll")
            var mh5 = shell.handlerUnder(main5)
            shell.resetStepsOf(main5)
            for (var w = 0; w < 4; w++)
                mh5.handleWheel(shell.frag(true, 15))
            shell.check("reopen:held", mh5.notchAccum === -60, String(mh5.notchAccum))
            // ScrollUpdate inputs reach the other two accums, so a reset that kept them would show here.
            mh5.handleWheel(shell.nudge(-2))
            mh5.handleWheel(shell.stroke(2, 1))
            shell.check("reopen:pixel-live", mh5.pixelAccum !== 0, String(mh5.pixelAccum))
            shell.check("reopen:touch-live", mh5.stepAccum !== 0, String(mh5.stepAccum))
            menu.place(Qt.point(20, 20))
            shell.check("reopen:notch-dropped", mh5.notchAccum === 0, String(mh5.notchAccum))
            shell.check("reopen:pixel-dropped", mh5.pixelAccum === 0, String(mh5.pixelAccum))
            shell.check("reopen:touch-dropped", mh5.stepAccum === 0, String(mh5.stepAccum))
            // At shipped defaults c opens a lone flyout because Copy as is hidden. The main
            // frame must close that flyout before its wheel step, just as for a visible parent.
            menu.openAt(Qt.point(20, 20))
            var loneOpened = menu.openSubmenuFor("copyAs")
            shell.check("hunt:lone-copy-opens", loneOpened && menu.loneFlyoutAction === "copyAs",
                        "opened=" + loneOpened + " lone=" + menu.loneFlyoutAction)
            shell.resetStepsOf(main5)
            mh5.handleWheel(shell.notch(true))
            shell.check("hunt:lone-main-wheel-closes", menu.submenuOpen === false,
                        "lone=" + menu.loneFlyoutAction + " submenuOpen=" + menu.submenuOpen)
            shell.check("hunt:lone-main-wheel-draws-highlight", menu.itemFor(menu.cursor).current === true,
                        "cursor=" + menu.cursor + " current=" + menu.itemFor(menu.cursor).current)
            // Hidden parents still obey the filesystem and writability inventory gates.
            menu.clipboardAvailable = true
            menu.canLink = false
            menu.openAt(Qt.point(20, 20))
            shell.check("hunt:hidden-paste-refuses-no-links", !menu.openSubmenuFor("pasteAs") && !menu.submenuOpen,
                        "submenuOpen=" + menu.submenuOpen)
            menu.canLink = true
            menu.dirWritable = false
            menu.openAt(Qt.point(20, 20))
            shell.check("hunt:hidden-paste-refuses-read-only", !menu.openSubmenuFor("pasteAs") && !menu.submenuOpen,
                        "submenuOpen=" + menu.submenuOpen)
            menu.dirWritable = true
            // A shut menu keeps nothing standing.
            menu.close()
            shell.check("shut", menu.opened === false, "still open")
            if (shell.failures.length === 0)
                shell.log("PASS " + shell.shortNote + " " + shell.longNote
                          + " text=" + Flea.Theme.font.body + "/" + Flea.Theme.font.caption
                          + " pad=" + Flea.Theme.spacing.rowPaddingX)
            else
                for (var i = 0; i < shell.failures.length; i++)
                    shell.log("FAIL " + shell.failures[i])
            shell.log("DONE failures=" + shell.failures.length)
            shell.phase = 6
            shell.quit()
        }
    }
}
