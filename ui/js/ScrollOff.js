.pragma library

// The cursor keeps three rows of context above and below while scrolling, and still
// reaches the first and last rows. Pure index maths; the list and the columns view
// turn the answer into pixels, and the grid keeps its own contain.

// How many rows stand between the cursor and the viewport edge before the window moves.
var CONTEXT = 3

// How many rows are fully inside the viewport: a partly drawn bottom row is
// not one, so the view ends past the last row's bottom. Callers size
// prefetch and windows from pane.visibleRows and never from this.
function fullyVisible(height, rowHeight) {
    return Math.max(1, Math.floor(height / rowHeight))
}

// The first visible row that keeps the cursor's context: first is the window's own,
// visible how many rows it holds, cursor a view position, total the listing's rows.
function firstFor(first, visible, cursor, total, context) {
    var asked = context === undefined ? CONTEXT : context
    // Vim's scrolloff rule: the margin never exceeds half the viewport, so the
    // cursor always fits inside [want, want + visible - 1] on a short list.
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

// True when the cursor row itself stands outside the viewport's pixels, even
// though its index sits at the window edge: a pixel wheel scroll can leave the
// first row cut at the top edge while firstFor answers no move. contentY is in
// the same space as want * rowH (the columns view passes contentY - originY),
// height the view's own. Both views scroll when this answers true.
function needsAlign(cursor, want, visible, contentY, height, rowH) {
    if (cursor !== want && cursor !== want + visible - 1)
        return false
    var top = cursor * rowH
    return top < contentY || top + rowH > contentY + height
}

// The pointer case, in pixels and never in rows: a click never scrolls the list
// under the pointer, except that a row cut by the viewport edge is scrolled just
// enough to show it whole. top is the row's own top in the same space as
// contentY, rowH one row, height the view's own. A fully inside row keeps
// contentY; a row starting above answers its top; a row ending below answers
// top + rowH - height. The caller clamps, the way the row-grid path does.
function containY(top, rowH, contentY, height) {
    if (top < contentY)
        return top
    if (top + rowH > contentY + height)
        return top + rowH - height
    return contentY
}
