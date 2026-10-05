import QtQuick
import "js/Scroll.js" as Scroll

// A wheel or swipe that goes sideways over a table wider than its block scrolls that table; a vertical one is left for the document's handler beneath.
MouseArea {
    id: root
    objectName: "tableWheel"

    // The sideways scrolls alive in the document, which each adds itself to and drops itself from.
    property var scrollers: []
    // The table a touchpad stroke went to until it ends, and whether the stroke went to the document instead.
    property var held: null
    property bool documentStroke: false

    anchors.fill: parent
    // A press is never taken: the table's links and the document's own handler need them.
    acceptedButtons: Qt.NoButton
    // Over the document's FastScrollHandler (z 1000), so a sideways stroke reaches the table first.
    z: 1001

    function add(scroller) {
        root.scrollers = root.scrollers.concat([scroller])
    }

    function remove(scroller) {
        root.scrollers = root.scrollers.filter(function (s) { return s !== scroller })
        if (root.held === scroller)
            root.held = null
    }

    // The overflowing table under a point of this item, else null.
    function scrollerAt(x, y) {
        for (var i = 0; i < root.scrollers.length; i++) {
            var s = root.scrollers[i]
            if (!s || !s.visible || !s.table || !s.table.overflows)
                continue
            var at = s.mapFromItem(root, x, y)
            if (at.x >= 0 && at.y >= 0 && at.x < s.width && at.y < s.height)
                return s
        }
        return null
    }

    // The sideways distance of an event: Shift turns a vertical wheel notch sideways, as it does in a browser.
    function across(event, axis) {
        var pixel = Number(event.pixelDelta.x) || 0
        var angle = Number(event.angleDelta.x) || 0
        if ((event.modifiers & Qt.ShiftModifier) && pixel === 0 && angle === 0)
            return axis === "pixel" ? Number(event.pixelDelta.y) || 0 : Number(event.angleDelta.y) || 0
        return axis === "pixel" ? pixel : angle
    }

    // Sideways when its sideways travel beats its vertical in the unit the event carries, or Shift holds a notch; Shift on a vertical notch is sideways.
    function sideways(event) {
        var pixel = (Number(event.pixelDelta.x) || 0) !== 0 || (Number(event.pixelDelta.y) || 0) !== 0
        var x = Math.abs(root.across(event, pixel ? "pixel" : "angle"))
        var y = Math.abs(Number(pixel ? event.pixelDelta.y : event.angleDelta.y) || 0)
        return (event.modifiers & Qt.ShiftModifier) ? x !== 0 : x > y
    }

    // A table's wheel takes sideways deltas only; the vertical ones stay with the document.
    function sidewaysEvent(event) {
        return { pixelDelta: { x: root.across(event, "pixel"), y: 0 }, angleDelta: { x: root.across(event, "angle"), y: 0 },
            modifiers: event.modifiers & ~Qt.ShiftModifier, phase: event.phase !== undefined ? event.phase : Qt.NoScrollPhase, accepted: false }
    }

    // True when the table took the event; a false answer leaves it to the document's handler under this one.
    function route(event) {
        if (event.modifiers & Qt.ControlModifier)
            return false
        var phase = event.phase !== undefined ? event.phase : Qt.NoScrollPhase
        var at = root.scrollerAt(event.x, event.y)
        if (!Scroll.isTouchpad(phase)) {
            if (at === null || !root.sideways(event))
                return false
            at.wheel(root.sidewaysEvent(event))
            return true
        }
        if (phase === Qt.ScrollBegin) {
            root.held = null
            root.documentStroke = false
            // The table stops its own coasting on a new touch, and the document hears the Begin as well.
            if (at !== null)
                at.wheel(root.sidewaysEvent(event))
            return false
        }
        if (root.held === null && !root.documentStroke && phase !== Qt.ScrollEnd) {
            if (at !== null && root.sideways(event))
                root.held = at
            else if ((Number(event.pixelDelta.x) || 0) !== 0 || (Number(event.pixelDelta.y) || 0) !== 0)
                root.documentStroke = true
        }
        var taker = root.held
        if (phase === Qt.ScrollEnd) {
            root.held = null
            root.documentStroke = false
        }
        if (taker === null)
            return false
        taker.wheel(root.sidewaysEvent(event))
        return true
    }

    onWheel: function (wheel) { wheel.accepted = root.route(wheel) }
}
