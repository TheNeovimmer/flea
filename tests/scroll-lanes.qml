//@ pragma ShellId flea-scroll-lanes-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/scroll-lanes.sh's harness: non-file surfaces draw no bar anywhere and keep pixel
// scrolling with rows at full width; the .sh sweeps the sources for the same rule.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0

    function log(line) { console.log("SCROLLLANES " + line) }
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
    function notch(down) {
        return { phase: 0, pixelDelta: { x: 0, y: 0 }, angleDelta: { x: 0, y: down ? -120 : 120 },
                 modifiers: 0, accepted: false }
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        Flea.SettingsRail {
            id: rail
            width: 200
            height: 40
            section: "display"
        }

        Flea.CardScroll {
            id: body
            width: 320
            height: 200
            Column { width: parent.width; Repeater { model: 40; Text { text: "line " + index } } }
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function advance() {
        shell.ticks += 1
        if (shell.phase === 0 && shell.ticks >= 3) {
            shell.phase = 1
            shell.ticks = 0
            // The settings rail: no bar item, rows at full width, still pixel scrolling.
            shell.check("rail-nobar", shell.findFirst(rail, "ViewportScrollBar") === null, "a bar stands")
            var row = rail.itemFor("display")
            shell.check("rail-row", row && row.width === rail.width,
                        String(row ? row.width : "none") + "/" + String(rail.width))
            var rh = shell.findFirst(rail, "FastScrollHandler")
            shell.check("rail-handler", rh && rh.stepMode === false, "stepping")
            if (rh && rail.contentHeight > rail.height) {
                var y0 = rail.contentY
                for (var i = 0; i < 5; i++)
                    rh.handleWheel(shell.notch(true))
                shell.check("rail-scrolls", rail.contentY > y0, String(rail.contentY))
            } else {
                shell.failures.push("rail-scrolls no overflow to scroll")
            }
            // A dialog body: no bar, full width, wheel still moves pixels.
            shell.check("body-nobar", shell.findFirst(body, "ViewportScrollBar") === null, "a bar stands")
            shell.check("body-holder", body.holderWidth === body.width,
                        String(body.holderWidth) + "/" + String(body.width))
            var bh = shell.findFirst(body, "FastScrollHandler")
            if (bh && body.contentHeight > body.height) {
                var b0 = body.contentY
                for (var j = 0; j < 3; j++)
                    bh.handleWheel(shell.notch(true))
                shell.check("body-scrolls", body.contentY > b0, String(body.contentY))
            } else {
                shell.failures.push("body-scrolls no overflow to scroll")
            }
            if (shell.failures.length === 0)
                shell.log("PASS rail=" + Math.round(rail.width) + " body=" + Math.round(body.width)
                          + "/" + Math.round(body.holderWidth))
            else
                for (var k = 0; k < shell.failures.length; k++)
                    shell.log("FAIL " + shell.failures[k])
            shell.log("DONE failures=" + shell.failures.length)
            shell.phase = 2
            shell.quit()
        }
    }
}
