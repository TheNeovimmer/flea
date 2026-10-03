//@ pragma ShellId flea-scroll-bounds-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Scroll.js" as Scroll

// tp2-r2: grid margin lanes and axis lanes on bare views, offscreen. A grid rests at -gap on
// both axes and never reads overscrolled there; an axis with no scroll range takes no delta,
// so a diagonal on a vertical list coasts exactly like the pure vertical stroke. The scroll bar
// measures a list's content plus its margins, so a list with margins reads true at both ends.
// tests/scroll-bounds.sh drives it.
ShellRoot {
    id: root

    property var failures: []
    property double fakeT: 1000
    property real gap: Flea.Theme.spacing.gap
    // Bar fixtures: a list whose content is shorter than the view by less than its two margins, a long one, and a bare one.
    readonly property real barTop: 40
    readonly property real barBottom: 30
    readonly property real barRow: 28
    readonly property int shortRows: 10
    readonly property int longRows: 40
    readonly property real barViewHeight: 300
    readonly property real barViewWidth: 200
    readonly property real barViewGap: 250
    readonly property real barViewY: 500
    // The proportional checks and the drag land within half a pixel, the bar's own overflow tolerance.
    readonly property real barTolerance: 0.5
    // The drag ends this many track lengths past the end of the lane, so it can only stop at the bound.
    readonly property real overDrag: 2
    readonly property int noDelay: 0

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: root.barViewY + root.barViewHeight
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

        TestEvent { id: driver }

        ListView {
            id: shortList
            x: 0
            y: root.barViewY
            width: root.barViewWidth
            height: root.barViewHeight
            model: root.shortRows
            topMargin: root.barTop
            bottomMargin: root.barBottom
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle { required property int index; width: shortList.width; height: root.barRow }
            Flea.ViewportScrollBar { id: shortBar; parent: shortList; anchors { top: parent.top; right: parent.right } flickable: shortList }
        }

        ListView {
            id: longList
            x: root.barViewGap
            y: root.barViewY
            width: root.barViewWidth
            height: root.barViewHeight
            model: root.longRows
            topMargin: root.barTop
            bottomMargin: root.barBottom
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle { required property int index; width: longList.width; height: root.barRow }
            Flea.ViewportScrollBar { id: longBar; parent: longList; anchors { top: parent.top; right: parent.right } flickable: longList }
        }

        ListView {
            id: bareList
            x: 2 * root.barViewGap
            y: root.barViewY
            width: root.barViewWidth
            height: root.barViewHeight
            model: root.longRows
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle { required property int index; width: bareList.width; height: root.barRow }
            Flea.ViewportScrollBar { id: bareBar; parent: bareList; anchors { top: parent.top; right: parent.right } flickable: bareList }
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
        root.checkBars()
    }

    // The scrollable range the flickable itself reports: content plus both margins, less the view.
    function trueTop(view) { return view.originY - view.topMargin }
    function trueEnd(view) { return view.originY + view.contentHeight - view.height + view.bottomMargin }

    // Knob geometry from the flickable's measured numbers alone, never from the bar's own readers.
    function checkKnob(label, view, bar) {
        var track = bar.height
        var content = view.contentHeight + view.topMargin + view.bottomMargin
        var span = content - view.height
        if (!bar.overflow) { fail(label + " bar reads no overflow though the view scrolls " + span.toFixed(1)); return }
        var length = Math.min(track, Math.max(Flea.Theme.hitMin, track * view.height / content))
        var travel = track - length
        if (Math.abs(bar.handleLength - length) > root.barTolerance)
            fail(label + " knob length " + bar.handleLength.toFixed(1) + ", want " + length.toFixed(1))
        var top = root.trueTop(view)
        var marks = [[0, "top"], [1 / 3, "third"], [1, "end"]]
        for (var i = 0; i < marks.length; i++) {
            view.contentY = top + span * marks[i][0]
            var want = travel * marks[i][0]
            if (Math.abs(bar.handleOffset - want) > root.barTolerance)
                fail(label + " knob offset at the " + marks[i][1] + " " + bar.handleOffset.toFixed(2) + ", want " + want.toFixed(2))
        }
        view.contentY = top
        var x = bar.width / 2
        driver.mousePress(bar, x, bar.handleOffset + bar.handleLength / 2, Qt.LeftButton, Qt.NoModifier, root.noDelay)
        driver.mouseMove(bar, x, track * root.overDrag, root.noDelay, Qt.LeftButton, Qt.NoModifier)
        driver.mouseRelease(bar, x, track * root.overDrag, Qt.LeftButton, Qt.NoModifier, root.noDelay)
        var end = root.trueEnd(view)
        if (Math.abs(view.contentY - end) > root.barTolerance)
            fail(label + " knob drag landed at " + view.contentY.toFixed(1) + ", want the true end " + end.toFixed(1))
        console.log("LANES bar " + label + " span=" + span.toFixed(1) + " knob=" + length.toFixed(1) + " dragged=" + view.contentY.toFixed(1))
    }

    function checkBars() {
        if (shortList.contentHeight >= shortList.height)
            fail("the short fixture is not shorter than its view: " + shortList.contentHeight)
        if (shortList.contentHeight + shortList.topMargin + shortList.bottomMargin <= shortList.height)
            fail("the short fixture does not scroll by its margins")
        root.checkKnob("short", shortList, shortBar)
        root.checkKnob("long", longList, longBar)
        root.checkKnob("bare", bareList, bareBar)
        if (bareBar.contentLength !== bareList.contentHeight || bareBar.origin !== bareList.originY)
            fail("a list without margins reads " + bareBar.origin + "+" + bareBar.contentLength + ", want its bare content")
        root.report()
    }

    function report() {
        if (root.failures.length === 0)
            console.log("SCROLL_BOUNDS PASS grid diag bars")
        for (var f = 0; f < root.failures.length; f++)
            console.log("SCROLL_BOUNDS FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
