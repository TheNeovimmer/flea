//@ pragma ShellId flea-scroll-bounds-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Scroll.js" as Scroll

// tp2-r2: grid margin lanes and axis lanes on bare views, offscreen. A grid rests at -gap on
// both axes and never reads overscrolled there; an axis with no scroll range takes no delta,
// so a diagonal on a vertical list coasts exactly like the pure vertical stroke.
// tests/scroll-bounds.sh drives it.
ShellRoot {
    id: root

    property var failures: []
    property double fakeT: 1000
    property real gap: Flea.Theme.spacing.gap

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 500
        color: Flea.Theme.color.background

        GridView {
            id: grid
            objectName: "laneGrid"
            width: 440
            height: 400
            model: 3000
            clip: true
            leftMargin: root.gap
            topMargin: root.gap
            cellWidth: 118
            cellHeight: 140
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle { required property int index; width: 110; height: 132 }
            Flea.FastScrollHandler { parent: grid; flickable: grid }
        }

        ListView {
            id: list
            objectName: "laneList"
            width: 400
            height: 300
            anchors.right: parent.right
            model: 3000
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle { required property int index; width: list.width; height: 28 }
            Flea.FastScrollHandler { parent: list; flickable: list }
        }
    }

    Timer { interval: 800; running: true; repeat: false; onTriggered: root.checkGrid() }

    function fail(text) { root.failures.push(text) }

    function bodyOf(view) {
        var kids = view.children
        for (var i = 0; i < kids.length; i++)
            if (kids[i] && kids[i].objectName === "fleaScroll")
                return kids[i]
        return null
    }

    function wheelXY(px, py, phase) {
        return { pixelDelta: { x: px, y: py }, angleDelta: { x: 0, y: 0 },
            phase: phase, modifiers: 0, accepted: false }
    }

    function freeze(body) { body.tailRunning = false; body.returnRunning = false }

    function retActive(view) {
        var found = Scroll.tailState(view, false)
        return found !== null && found.retActive
    }

    function tailActive(view) {
        var found = Scroll.tailState(view, false)
        return found !== null && found.active
    }

    // Finding 2: the grid rests at -gap,-gap; one press and one Begin move nothing, an End at
    // rest starts nothing, and a stroke at the top returns to -gap rather than to the origin.
    function checkGrid() {
        var body = root.bodyOf(grid)
        if (!body) { fail("found no grid handler"); root.checkDiag(); return }
        Scroll.tailState(grid, true).samples = []
        grid.contentX = -root.gap
        grid.contentY = -root.gap
        body.stopTail()
        body.stopReturn(false)
        if (body.overscrolled())
            fail("grid reads overscrolled at its own rest " + grid.contentY.toFixed(1))
        var press = { accepted: true }
        body.handlePress(press)
        if (press.accepted !== false)
            fail("grid press was consumed instead of reaching the tile")
        body.handleWheel(wheelXY(0, 0, 1))
        if (grid.contentX !== -root.gap || grid.contentY !== -root.gap)
            fail("a press and a Begin moved the grid " + grid.contentX.toFixed(1)
                + "," + grid.contentY.toFixed(1) + ", want rest -gap")
        var end = wheelXY(0, 0, 3)
        body.handleWheel(end)
        if (root.retActive(grid) || root.tailActive(grid))
            fail("an End at rest started an animation")
        if (end.accepted !== false)
            fail("an End at rest was consumed with nothing to animate")
        // A stroke pulling the top down, lifted: the return rests at -gap.
        body.handleWheel(wheelXY(0, 0, 1))
        for (var i = 0; i < 8; i++) {
            root.fakeT += 8
            Scroll.testNowMs = root.fakeT
            body.handleWheel(wheelXY(0, 24, 2))
        }
        root.fakeT += 8
        Scroll.testNowMs = root.fakeT
        end = wheelXY(0, 0, 3)
        body.handleWheel(end)
        if (end.accepted !== true)
            fail("overscrolled End left unaccepted on the grid")
        root.freeze(body)
        if (!root.retActive(grid))
            fail("grid edge started no return")
        var frames = 0
        while (root.retActive(grid) && frames < 10000) { body.advanceReturn(16.7); frames += 1 }
        if (Math.abs(grid.contentY + root.gap) > 1 || Math.abs(grid.contentX + root.gap) > 1)
            fail("grid rested " + grid.contentX.toFixed(1) + "," + grid.contentY.toFixed(1) + ", want -gap")
        console.log("LANES grid rest=" + (-root.gap) + " frames=" + frames)
        root.checkDiag()
    }

    function strokeUpdates(body, view, deltas) {
        body.handleWheel(wheelXY(0, 0, 1))
        for (var i = 0; i < deltas.length; i++) {
            root.fakeT += 8
            Scroll.testNowMs = root.fakeT
            body.handleWheel(wheelXY(deltas[i][0], deltas[i][1], 2))
        }
        root.fakeT += 8
        Scroll.testNowMs = root.fakeT
        var end = wheelXY(0, 0, 3)
        body.handleWheel(end)
        return end
    }

    function coastToRest(body, view) {
        var lift = view.contentY
        root.freeze(body)
        var frames = 0
        while (root.tailActive(view) && frames < 10000) { body.advanceTail(16.7); frames += 1 }
        while (root.retActive(view) && frames < 20000) { body.advanceReturn(16.7); frames += 1 }
        return view.contentY - lift
    }

    function verticalDeltas(n) {
        var out = []
        for (var i = 0; i < n; i++) out.push([0, -12])
        return out
    }

    // Finding 3: horizontal deltas never touch a vertical view, and the lift then coasts
    // exactly like the same stroke without them: no rubber band, no stolen tail.
    function checkDiag() {
        var body = root.bodyOf(list)
        if (!body) { fail("found no list handler"); root.report(); return }
        var rest = 1200
        list.contentY = rest
        body.stopTail()
        body.stopReturn(true)
        root.fakeT += 1000
        Scroll.testNowMs = root.fakeT
        root.strokeUpdates(body, list, root.verticalDeltas(12))
        var control = root.coastToRest(body, list)
        list.contentY = rest
        body.stopTail()
        body.stopReturn(true)
        root.fakeT += 1000
        Scroll.testNowMs = root.fakeT
        body.handleWheel(wheelXY(0, 0, 1))
        var deltas = [[2, -12], [2, -12], [2, -12], [2, -12],
            [0, -12], [0, -12], [0, -12], [0, -12], [0, -12], [0, -12], [0, -12], [0, -12]]
        for (var i = 0; i < deltas.length; i++) {
            root.fakeT += 8
            Scroll.testNowMs = root.fakeT
            body.handleWheel(wheelXY(deltas[i][0], deltas[i][1], 2))
            if (Math.abs(list.contentX) > 0.01)
                fail("diagonal update " + i + " moved contentX to " + list.contentX.toFixed(2))
        }
        var liftY = list.contentY
        root.fakeT += 8
        Scroll.testNowMs = root.fakeT
        var end = wheelXY(0, 0, 3)
        body.handleWheel(end)
        if (!root.tailActive(list) || root.retActive(list))
            fail("diagonal lift started a return instead of a tail")
        var coast = root.coastToRest(body, list)
        if (Math.abs(coast - control) > 1)
            fail("diagonal coasted " + coast.toFixed(1) + ", want the pure stroke " + control.toFixed(1))
        console.log("LANES diag control=" + control.toFixed(1) + " coast=" + coast.toFixed(1)
            + " contentX=" + list.contentX)
        root.report()
    }

    function report() {
        if (root.failures.length === 0)
            console.log("SCROLL_BOUNDS PASS grid diag")
        for (var f = 0; f < root.failures.length; f++)
            console.log("SCROLL_BOUNDS FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
