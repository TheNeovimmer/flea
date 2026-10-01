.pragma library

// The cursor keeps three rows of context above and below while scrolling, and still
// reaches the first and last rows. Pure index maths; the list and the columns view
// turn the answer into pixels, and the grid keeps its own contain.

// How many rows stand between the cursor and the viewport edge before the window moves.
var CONTEXT = 3

// The first visible row that keeps the cursor's context: first is the window's own,
// visible how many rows it holds, cursor a view position, total the listing's rows.
function firstFor(first, visible, cursor, total, context) {
    var margin = context === undefined ? CONTEXT : context
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
