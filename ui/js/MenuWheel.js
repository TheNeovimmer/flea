.pragma library

// A menu's wheel answer in raw angleDelta units: highlight steps, content follows through reveal().

// One discrete notch in raw angleDelta units, Qt's own convention for a wheel click.
var NOTCH_UNITS = 120

// Folds raw angleDelta into whole notches (remainder kept, dropped on flip, reset on open).
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

// Folds phaseless raw pixelDelta into whole rows at rowHeight px (gain 1, leftover kept).
function pixelSteps(accum, pixels, rowHeight) {
    return touchSteps(accum, Number(pixels) || 0, rowHeight)
}

// Folds gained travel into whole rows at rowHeight px (leftover kept, reset on ScrollBegin, no tail).
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
