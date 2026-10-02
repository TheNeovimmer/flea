import QtQuick
import "js/Scroll.js" as Scroll

// Writes the bounded position directly, on both axes; a MouseArea because a Flickable consumes wheel events first.
// Presses stop the tail unaccepted to reach the row; touchpad strokes move gained pixels, a notch keeps the Theme rate.
MouseArea {
    id: root
    objectName: "fleaScroll"

    required property var flickable
    property var ctrlWheelAction: null
    property bool tailRunning: false

    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    propagateComposedEvents: true
    z: 1000

    function scrollDistance(pixelDelta, angleDelta) {
        return Scroll.distance(pixelDelta, angleDelta, Application.styleHints.wheelScrollLines,
                               Theme.scroll.notchPx, Theme.scroll.multiplier)
    }

    function tailActive() {
        var found = Scroll.tailState(root.flickable, false)
        return found !== null && found.active
    }

    function stopTail() {
        Scroll.stopTail(root.flickable)
        root.tailRunning = false
        if (root.flickable)
            root.flickable.cancelFlick()
    }

    function writeY(value) {
        var at = Scroll.bounded(value, root.flickable.originY,
                                root.flickable.contentHeight, root.flickable.height)
        Scroll.tailState(root.flickable, true).lastY = at
        root.flickable.contentY = at
    }

    function writeX(value) {
        var at = Scroll.bounded(value, root.flickable.originX,
                                root.flickable.contentWidth, root.flickable.width)
        Scroll.tailState(root.flickable, true).lastX = at
        root.flickable.contentX = at
    }

    // One frame of the tail; the FrameAnimation below and the headless probe both enter here.
    function advanceTail(dtMs) {
        var found = Scroll.tailState(root.flickable, false)
        if (found === null || !found.active) {
            root.tailRunning = false
            return 0
        }
        var dt = Math.max(0, Number(dtMs) || 0)
        if (dt <= 0)
            return 0
        var stepY = Scroll.tailStep(found.vy, dt)
        var stepX = Scroll.tailStep(found.vx, dt)
        found.vy = stepY.v
        found.vx = stepX.v
        var moved = 0
        if (stepY.dx !== 0) {
            var beforeY = root.flickable.contentY
            writeY(beforeY - stepY.dx)
            if (root.flickable.contentY === beforeY)
                found.vy = 0
            else
                moved += Math.abs(root.flickable.contentY - beforeY)
        }
        if (stepX.dx !== 0) {
            var beforeX = root.flickable.contentX
            writeX(beforeX - stepX.dx)
            if (root.flickable.contentX === beforeX)
                found.vx = 0
            else
                moved += Math.abs(root.flickable.contentX - beforeX)
        }
        if (!Scroll.tailLive(found.vx, found.vy)) {
            found.active = false
            found.vx = 0
            found.vy = 0
            root.tailRunning = false
        }
        return moved
    }

    function startTail() {
        var found = Scroll.tailState(root.flickable, true)
        var v = Scroll.liftVelocity(found.samples, Scroll.now())
        found.samples = []
        if (v.vx === 0 && v.vy === 0) {
            found.active = false
            root.tailRunning = false
            return
        }
        found.vx = v.vx
        found.vy = v.vy
        found.active = true
        root.tailRunning = true
    }

    function handleWheel(wheel) {
        if ((wheel.modifiers & Qt.ControlModifier) && root.ctrlWheelAction !== null) {
            wheel.accepted = root.ctrlWheelAction(wheel)
            if (wheel.accepted) {
                root.stopTail()
                return true
            }
        }
        var phase = wheel.phase !== undefined ? wheel.phase : Qt.NoScrollPhase
        if (Scroll.isTouchpad(phase)) {
            // A new stroke ends the old tail; updates of the stroke in flight find none running.
            if (phase === Qt.ScrollBegin || root.tailActive())
                root.stopTail()
            // The Begin carries no pixels and anchors the lift's span.
            if (phase === Qt.ScrollBegin)
                Scroll.pushSample(root.flickable, Scroll.now(), 0, 0)
            var down = Scroll.touchDistance(wheel.pixelDelta.y)
            var across = Scroll.touchDistance(wheel.pixelDelta.x)
            if ((down === 0 && across === 0) || !root.flickable.interactive) {
                if (phase === Qt.ScrollEnd && root.flickable.interactive)
                    root.startTail()
                wheel.accepted = false
                return false
            }
            Scroll.pushSample(root.flickable, Scroll.now(), across, down)
            var previousY = root.flickable.contentY
            var previousX = root.flickable.contentX
            root.flickable.cancelFlick()
            if (down !== 0)
                writeY(previousY - down)
            // A tilt or a diagonal touchpad stroke pans a content wider than the view, a zoomed PDF page.
            if (across !== 0)
                writeX(previousX - across)
            wheel.accepted = Scroll.moved(previousY, root.flickable.contentY) || Scroll.moved(previousX, root.flickable.contentX)
            if (phase === Qt.ScrollEnd)
                root.startTail()
            return wheel.accepted
        }
        if (root.tailActive())
            root.stopTail()
        var notchDown = root.scrollDistance(wheel.pixelDelta.y, wheel.angleDelta.y)
        var notchAcross = root.scrollDistance(wheel.pixelDelta.x, wheel.angleDelta.x)
        if ((notchDown === 0 && notchAcross === 0) || !root.flickable.interactive) {
            wheel.accepted = false
            return false
        }
        var notchY = root.flickable.contentY
        var notchX = root.flickable.contentX
        root.flickable.cancelFlick()
        if (notchDown !== 0)
            writeY(notchY - notchDown)
        if (notchAcross !== 0)
            writeX(notchX - notchAcross)
        wheel.accepted = Scroll.moved(notchY, root.flickable.contentY) || Scroll.moved(notchX, root.flickable.contentX)
        return wheel.accepted
    }

    onWheel: function (wheel) { root.handleWheel(wheel) }
    // Passive: the tail stops before the click is read, and the press reaches the row.
    function handlePress(mouse) { root.stopTail(); mouse.accepted = false }
    onPressed: function (mouse) { root.handlePress(mouse) }

    Connections {
        target: root.flickable
        // Any content write the tail did not make ends it: showCursor, restore, cursor keys, the
        // band. The tail records every value it writes, so any other value is someone else's.
        function onContentYChanged() {
            var found = Scroll.tailState(root.flickable, false)
            if (found !== null && found.active && root.flickable.contentY !== found.lastY)
                root.stopTail()
        }
        function onContentXChanged() {
            var found = Scroll.tailState(root.flickable, false)
            if (found !== null && found.active && root.flickable.contentX !== found.lastX)
                root.stopTail()
        }
        function onMovementStarted() { root.stopTail() }
    }

    FrameAnimation {
        running: root.tailRunning
        // frameTime is seconds; the tail integrates milliseconds.
        onTriggered: root.advanceTail(frameTime * 1000)
    }

    Component.onDestruction: Scroll.forgetTail(root.flickable)
}
