import QtQuick
import "js/Scroll.js" as Scroll
import "js/Motion.js" as Motion

// A MouseArea because Flickable eats wheel before a child WheelHandler; presses pass through, arithmetic in Scroll.js.
MouseArea {
    id: root
    objectName: "fleaScroll"

    required property var flickable
    property var ctrlWheelAction: null
    property bool tailRunning: false
    property bool returnRunning: false

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

    function returnActive() {
        var found = Scroll.tailState(root.flickable, false)
        return found !== null && found.retActive
    }

    // An axis the view cannot scroll takes no delta at all.
    function scrollsX() {
        var f = root.flickable
        if (!f || f.flickableDirection === Flickable.VerticalFlick)
            return false
        return Scroll.rangesX(f)
    }
    function scrollsY() {
        var f = root.flickable
        if (!f || f.flickableDirection === Flickable.HorizontalFlick)
            return false
        return Scroll.rangesY(f)
    }

    // Any foreign write ends the return; a press holds it instead of snapping to the bound.
    function stopReturn(snap) {
        var f = root.flickable
        if (!f) {
            root.returnRunning = false
            return
        }
        var found = Scroll.tailState(f, false)
        if (found !== null) {
            found.retActive = false
            found.retElapsed = 0
            found.overY = 0
            found.overX = 0
        }
        root.returnRunning = false
        if (snap) {
            var ly = Scroll.limitsY(f)
            var lx = Scroll.limitsX(f)
            var ty = Math.max(ly.min, Math.min(ly.max, f.contentY))
            var tx = Math.max(lx.min, Math.min(lx.max, f.contentX))
            if (ty !== f.contentY || tx !== f.contentX) {
                var live = Scroll.tailState(f, true)
                live.lastY = ty
                live.lastX = tx
                f.contentY = ty
                f.contentX = tx
                f.cancelFlick()
            }
        }
    }

    function overscrolled() {
        var found = Scroll.tailState(root.flickable, false)
        if (found !== null && (found.overY !== 0 || found.overX !== 0))
            return true
        var f = root.flickable
        var ly = Scroll.limitsY(f)
        var lx = Scroll.limitsX(f)
        return f.contentY < ly.min - 0.01 || f.contentY > ly.max + 0.01
            || f.contentX < lx.min - 0.01 || f.contentX > lx.max + 0.01
    }

    function writeY(value) {
        var at = Scroll.bounded(value, root.flickable.originY, root.flickable.contentHeight,
                                root.flickable.height, root.flickable.topMargin, root.flickable.bottomMargin)
        Scroll.tailState(root.flickable, true).lastY = at
        root.flickable.contentY = at
    }

    function writeX(value) {
        var at = Scroll.bounded(value, root.flickable.originX, root.flickable.contentWidth,
                                root.flickable.width, root.flickable.leftMargin, root.flickable.rightMargin)
        Scroll.tailState(root.flickable, true).lastX = at
        root.flickable.contentX = at
    }

    function writeRawY(at) {
        Scroll.tailState(root.flickable, true).lastY = at
        root.flickable.contentY = at
    }

    function writeRawX(at) {
        Scroll.tailState(root.flickable, true).lastX = at
        root.flickable.contentX = at
    }

    // Past the bound travel resists; banked travel from a swapped listing is dropped.
    function touchY(down) {
        var f = root.flickable
        var lim = Scroll.limitsY(f)
        var st = Scroll.tailState(f, true)
        if (st.overY !== 0 && f.contentY >= lim.min - 0.01 && f.contentY <= lim.max + 0.01)
            st.overY = 0
        var d = Math.max(1, f.height)
        if (st.overY === 0) {
            var want = f.contentY - down
            if (want >= lim.min && want <= lim.max) {
                writeY(want)
                return
            }
            var raw = want < lim.min ? lim.min - want : want - lim.max
            var shown = Scroll.overResist(raw, d)
            st.overY = want < lim.min ? -raw : raw
            writeRawY(want < lim.min ? lim.min - shown : lim.max + shown)
            return
        }
        var m = Math.abs(st.overY)
        var nm = st.overY < 0 ? m + down : m - down
        if (nm <= 0) {
            var inside = st.overY < 0 ? lim.min + (-nm) : lim.max + nm
            st.overY = 0
            writeY(inside)
            return
        }
        var s = Scroll.overResist(nm, d)
        st.overY = st.overY < 0 ? -nm : nm
        writeRawY(st.overY < 0 ? lim.min - s : lim.max + s)
    }

    function touchX(across) {
        var f = root.flickable
        var lim = Scroll.limitsX(f)
        var st = Scroll.tailState(f, true)
        if (st.overX !== 0 && f.contentX >= lim.min - 0.01 && f.contentX <= lim.max + 0.01)
            st.overX = 0
        var d = Math.max(1, f.width)
        if (st.overX === 0) {
            var want = f.contentX - across
            if (want >= lim.min && want <= lim.max) {
                writeX(want)
                return
            }
            var raw = want < lim.min ? lim.min - want : want - lim.max
            var shown = Scroll.overResist(raw, d)
            st.overX = want < lim.min ? -raw : raw
            writeRawX(want < lim.min ? lim.min - shown : lim.max + shown)
            return
        }
        var m = Math.abs(st.overX)
        var nm = st.overX < 0 ? m + across : m - across
        if (nm <= 0) {
            var inside = st.overX < 0 ? lim.min + (-nm) : lim.max + nm
            st.overX = 0
            writeX(inside)
            return
        }
        var s = Scroll.overResist(nm, d)
        st.overX = st.overX < 0 ? -nm : nm
        writeRawX(st.overX < 0 ? lim.min - s : lim.max + s)
    }

    // A past-bound lift returns on Omarchy's duration, at once under reduced motion.
    function startReturn() {
        var f = root.flickable
        if (!f)
            return
        var st = Scroll.tailState(f, true)
        var ly = Scroll.limitsY(f)
        var lx = Scroll.limitsX(f)
        var needY = f.contentY < ly.min - 0.01 || f.contentY > ly.max + 0.01
        var needX = f.contentX < lx.min - 0.01 || f.contentX > lx.max + 0.01
        if (!needY && !needX) {
            st.overY = 0
            st.overX = 0
            root.returnRunning = false
            return
        }
        var toY = f.contentY < ly.min ? ly.min : (f.contentY > ly.max ? ly.max : f.contentY)
        var toX = f.contentX < lx.min ? lx.min : (f.contentX > lx.max ? lx.max : f.contentX)
        if (Theme.reducedMotion) {
            st.overY = 0
            st.overX = 0
            st.retActive = false
            root.returnRunning = false
            st.lastY = toY
            st.lastX = toX
            f.contentY = toY
            f.contentX = toX
            f.cancelFlick()
            return
        }
        st.retFromY = f.contentY
        st.retToY = toY
        st.retFromX = f.contentX
        st.retToX = toX
        st.retElapsed = 0
        st.retDur = Motion.durMs.open
        st.retActive = true
        st.overY = 0
        st.overX = 0
        root.returnRunning = true
    }

    // One frame of the return; the FrameAnimation below and the headless probe both enter here.
    function advanceReturn(dtMs) {
        var found = Scroll.tailState(root.flickable, false)
        if (found === null || !found.retActive) {
            root.returnRunning = false
            return 0
        }
        var dt = Math.max(0, Number(dtMs) || 0)
        if (dt <= 0)
            return 0
        found.retElapsed += dt
        var ny = Scroll.returnAt(found.retFromY, found.retToY, found.retElapsed, found.retDur)
        var nx = Scroll.returnAt(found.retFromX, found.retToX, found.retElapsed, found.retDur)
        var moved = Math.abs(ny - root.flickable.contentY) + Math.abs(nx - root.flickable.contentX)
        found.lastY = ny
        found.lastX = nx
        root.flickable.contentY = ny
        root.flickable.contentX = nx
        if (found.retElapsed >= found.retDur) {
            found.retActive = false
            found.overY = 0
            found.overX = 0
            root.returnRunning = false
        }
        return moved
    }

    // Past the bound the tail integrates through stroke resistance and brakes to a peak.
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
            var wantY = beforeY - stepY.dx
            var ly = Scroll.limitsY(root.flickable)
            if (wantY >= ly.min && wantY <= ly.max) {
                writeY(wantY)
                if (root.flickable.contentY === beforeY)
                    found.vy = 0
                else
                    moved += Math.abs(root.flickable.contentY - beforeY)
            } else {
                // The frame's raw travel joins the banked total shown through resistance.
                var boundY = wantY < ly.min ? ly.min : ly.max
                var stY = Scroll.tailState(root.flickable, true)
                var dimY = Math.max(1, root.flickable.height)
                var pastY = (wantY < ly.min ? ly.min - wantY : wantY - ly.max) - Scroll.overResist(Math.abs(stY.overY), dimY)
                var accY = Math.abs(stY.overY) + Math.max(0, pastY)
                stY.overY = wantY < ly.min ? -accY : accY
                found.vy = Scroll.overDecel(found.vy, dt)
                var shownY = Scroll.overResist(accY, dimY)
                writeRawY(wantY < ly.min ? boundY - shownY : boundY + shownY)
                moved += Math.abs(root.flickable.contentY - beforeY)
            }
        }
        if (stepX.dx !== 0) {
            var beforeX = root.flickable.contentX
            var wantX = beforeX - stepX.dx
            var lx = Scroll.limitsX(root.flickable)
            if (wantX >= lx.min && wantX <= lx.max) {
                writeX(wantX)
                if (root.flickable.contentX === beforeX)
                    found.vx = 0
                else
                    moved += Math.abs(root.flickable.contentX - beforeX)
            } else {
                var boundX = wantX < lx.min ? lx.min : lx.max
                var stX = Scroll.tailState(root.flickable, true)
                var dimX = Math.max(1, root.flickable.width)
                var pastX = (wantX < lx.min ? lx.min - wantX : wantX - lx.max) - Scroll.overResist(Math.abs(stX.overX), dimX)
                var accX = Math.abs(stX.overX) + Math.max(0, pastX)
                stX.overX = wantX < lx.min ? -accX : accX
                found.vx = Scroll.overDecel(found.vx, dt)
                var shownX = Scroll.overResist(accX, dimX)
                writeRawX(wantX < lx.min ? boundX - shownX : boundX + shownX)
                moved += Math.abs(root.flickable.contentX - beforeX)
            }
        }
        if (!Scroll.tailLive(found.vx, found.vy)) {
            found.active = false
            found.vx = 0
            found.vy = 0
            root.tailRunning = false
            if (root.overscrolled())
                root.startReturn()
        }
        return moved
    }

    function startTail() {
        var found = Scroll.tailState(root.flickable, true)
        if (found.overY !== 0 || found.overX !== 0)
            return
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
                root.stopReturn(true)
                return true
            }
        }
        var phase = wheel.phase !== undefined ? wheel.phase : Qt.NoScrollPhase
        if (Scroll.isTouchpad(phase)) {
            // A new stroke ends the old tail and snaps the return to its bound.
            if (phase === Qt.ScrollBegin) {
                root.stopTail()
                root.stopReturn(true)
            } else if (root.tailActive()) {
                root.stopTail()
            } else if (root.returnActive()) {
                root.stopReturn(true)
            }
            var down = Scroll.touchDistance(wheel.pixelDelta.y)
            var across = Scroll.touchDistance(wheel.pixelDelta.x)
            // A dead axis takes no delta, so samples and overscroll never name it.
            if (!root.scrollsY())
                down = 0
            if (!root.scrollsX())
                across = 0
            if ((down === 0 && across === 0) || !root.flickable.interactive) {
                if (phase === Qt.ScrollEnd && root.flickable.interactive) {
                    // The overscrolled lift End is accepted to start the return: left unaccepted,
                    // the view snaps to the bound in the same delivery and kills it.
                    if (root.overscrolled()) {
                        root.startReturn()
                        wheel.accepted = true
                        return true
                    }
                    root.startTail()
                }
                wheel.accepted = false
                return false
            }
            Scroll.pushSample(root.flickable, Scroll.now(), across, down)
            var previousY = root.flickable.contentY
            var previousX = root.flickable.contentX
            root.flickable.cancelFlick()
            if (down !== 0)
                touchY(down)
            // A tilt or a diagonal touchpad stroke pans a content wider than the view, a zoomed PDF page.
            if (across !== 0)
                touchX(across)
            wheel.accepted = Scroll.moved(previousY, root.flickable.contentY) || Scroll.moved(previousX, root.flickable.contentX)
            if (phase === Qt.ScrollEnd) {
                if (root.overscrolled())
                    root.startReturn()
                else
                    root.startTail()
            }
            return wheel.accepted
        }
        if (root.tailActive())
            root.stopTail()
        if (root.returnActive())
            root.stopReturn(true)
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
    // A press stops the tail and the return where they are for the row Qt picked; left
    // unaccepted it takes no grab, so the view's own release fixup returns the held overscroll.
    function handlePress(mouse) { root.stopTail(); root.stopReturn(false); mouse.accepted = false }
    onPressed: function (mouse) { root.handlePress(mouse) }

    Connections {
        target: root.flickable
        // Any content write the tail or the return did not make ends it: showCursor, restore,
        // cursor keys, the band. Each records every value it writes, so any other value is another.
        function onContentYChanged() {
            var found = Scroll.tailState(root.flickable, false)
            if (found === null)
                return
            if (found.active && root.flickable.contentY !== found.lastY)
                root.stopTail()
            else if (found.retActive && root.flickable.contentY !== found.lastY)
                root.stopReturn(false)
        }
        function onContentXChanged() {
            var found = Scroll.tailState(root.flickable, false)
            if (found === null)
                return
            if (found.active && root.flickable.contentX !== found.lastX)
                root.stopTail()
            else if (found.retActive && root.flickable.contentX !== found.lastX)
                root.stopReturn(false)
        }
        function onMovementStarted() { root.stopTail(); root.stopReturn(true) }
    }

    FrameAnimation {
        running: root.tailRunning || root.returnRunning
        // frameTime is seconds; both animations integrate milliseconds.
        onTriggered: {
            if (root.tailRunning)
                root.advanceTail(frameTime * 1000)
            else if (root.returnRunning)
                root.advanceReturn(frameTime * 1000)
        }
    }

    Component.onDestruction: Scroll.forgetTail(root.flickable)
}
