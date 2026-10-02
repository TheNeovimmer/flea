.pragma library

// A menu's wheel answer: the highlight steps, the content follows through reveal(). Kept pure
// so tests/js/menuscroll.js drives it without a Flickable. Gained travel is Scroll.js's own
// number (touchDistance's gained pixels, distance's notch pixels), signed the way writeY reads
// it: negative moves later rows into view, so the highlight moves down, exactly as Down does.

function notchStep(gained) {
    var d = Number(gained) || 0
    if (d === 0)
        return 0
    return d < 0 ? 1 : -1
}

// One discrete notch in raw angleDelta units, Qt's own convention for a wheel click.
var NOTCH_UNITS = 120

// Folds raw angleDelta into whole notches, keeping the remainder for the next event. Positive
// steps move the highlight down, so a negative (downward) angle steps down, the notchStep sign.
// A hi-res wheel sends a fraction of a notch per event and must accumulate to one, never step one
// row per event. The remainder is dropped when the direction flips, and the caller resets it when
// the menu opens, the GridArea.zoomWheel pattern.
function notchSteps(accum, angleDelta) {
    var a = Number(accum) || 0
    var d = Number(angleDelta) || 0
    if (d === 0)
        return { steps: 0, rest: a }
    if (a !== 0 && ((a < 0) !== (d < 0)))
        a = 0
    var total = a + d
    var notches = total > 0 ? Math.floor(total / NOTCH_UNITS) : Math.ceil(total / NOTCH_UNITS)
    return { steps: -notches, rest: total - notches * NOTCH_UNITS }
}

// Folds a phaseless wheel's raw pixelDelta into whole rows at rowHeight px each, keeping the
// leftover for the next event. Raw pixels at gain 1, not the touchpad's gained travel, so small
// pixel nudges accumulate to one row instead of stepping one row per event.
function pixelSteps(accum, pixels, rowHeight) {
    return touchSteps(accum, Number(pixels) || 0, rowHeight)
}

// Folds gained travel into whole rows at rowHeight px each, keeping the leftover for the next
// event. Positive steps move the highlight down. Stateless across strokes by construction: the
// caller resets accum to 0 on ScrollBegin, so no momentum tail ever builds in a menu.
function touchSteps(accum, gained, rowHeight) {
    var row = Math.max(1, Number(rowHeight) || 0)
    var total = (Number(accum) || 0) + (Number(gained) || 0)
    var steps = 0
    while (total <= -row) {
        steps += 1
        total += row
    }
    while (total >= row) {
        steps -= 1
        total -= row
    }
    return { steps: steps, rest: total }
}
