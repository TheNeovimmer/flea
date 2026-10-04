.pragma library

// The cursor keeps three rows of context while scrolling and still reaches both ends.
var CONTEXT = 3

// A partly drawn bottom row is not visible, so the count floors.
function fullyVisible(height, rowHeight) {
    return Math.max(1, Math.floor(height / rowHeight))
}

// The first visible row keeping the cursor's context; the margin never exceeds half the viewport.
function firstFor(first, visible, cursor, total, context) {
    var asked = context === undefined ? CONTEXT : context
    // The margin never exceeds half the viewport, so the cursor fits on a short list.
    var margin = Math.min(asked, Math.max(0, Math.floor((visible - 1) / 2)))
    var maxFirst = Math.max(0, total - visible)
    var want = first
    if (cursor - margin < first)
        want = cursor - margin
    else if (cursor + margin > first + visible - 1)
        want = cursor + margin - (visible - 1)
    if (want < 0)
        want = 0
    if (want > maxFirst)
        want = maxFirst
    return want
}

// True when a pixel-cut edge row needs aligning though its index sits at the window edge.
function needsAlign(cursor, want, visible, contentY, height, rowH) {
    if (cursor !== want && cursor !== want + visible - 1)
        return false
    var top = cursor * rowH
    return top < contentY || top + rowH > contentY + height
}

// The pointer case in pixels: a cut row moves just enough to show it whole.
function containY(top, rowH, contentY, height) {
    if (top < contentY)
        return top
    if (top + rowH > contentY + height)
        return top + rowH - height
    return contentY
}

// The keyboard move in pixels: row aligned, but a window that wants the last first row parks the last row flush on the bottom edge.
function keyY(visible, cursor, total, context, rowH, rel, height, contentHeight) {
    var first = Math.floor(rel / rowH)
    var want = firstFor(first, visible, cursor, total, context)
    var span = Math.max(0, contentHeight - height)
    // The row-aligned stop leaves up to a row of bare ground under the last row; a wheel parked in the footer stays.
    if (total > visible && want === total - visible)
        return Math.max(rel, Math.min(span, Math.max(0, total * rowH - height)))
    if (want === first && !needsAlign(cursor, want, visible, rel, height, rowH))
        return rel
    return Math.min(span, want * rowH)
}
