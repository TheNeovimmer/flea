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
