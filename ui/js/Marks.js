.pragma library

.import "Filter.js" as Filter

// Marking rows: ctrl+A, the shift range in both its keyboard and its pointer form, and ctrl+click.
// Split out of ui/js/Filter.js, which narrows the listing; these move the cursor and the marks over
// whatever that narrowing left drawn, which is why every one of them reads through it.

// Ctrl+A takes what is drawn, never what is listed: under a filter that is the matches alone.
function selectAll(pane) {
    if (pane.shown === null) {
        pane.selection.all(pane.total)
        return
    }
    pane.selection.clear()
    for (var i = 0; i < pane.shown.length; i++) {
        pane.selection.toggle(pane.shown[i])
    }
}

// A gesture continues while nothing else moved the cursor since the last extend left it;
// any other cursor move, and any mark made outside the gesture, ends it through shiftState.
function continuing(pane) {
    var state = pane.selection.shiftState()
    return state !== null && pane.cursorIndex === state.last
}

// Invert selection flips the marks over the rows the listing draws. The filter
// applies, so under a filter only the exact matches flip; a close match a later
// filter draws beside them is never in shown and so is never selected here.
function inverted(total, shown, selected) {
    var drawn = shown === null ? range(total) : shown.slice()
    var has = {}
    for (var s = 0; s < selected.length; s++)
        has[selected[s]] = true
    var out = []
    for (var i = 0; i < drawn.length; i++) {
        if (has[drawn[i]] !== true)
            out.push(drawn[i])
    }
    return out
}

function range(total) {
    var out = []
    for (var r = 0; r < total; r++)
        out.push(r)
    return out
}

// The pane's own invert, through the same drawn set selectAll reads.
function invert(pane) {
    var next = inverted(pane.total, pane.shown, pane.selectedIndices())
    pane.selection.clear()
    for (var i = 0; i < next.length; i++)
        pane.selection.toggle(next[i])
    pane.selectionVersion += 1
}

// Shift+J and Shift+K, the whole gesture: the cursor moves through what is drawn and the selection
// is the base the gesture started from plus the drawn rows between the anchor and the cursor, so
// several blocks can be marked and the gesture's own range still grows and shrinks.
function extend(pane, delta) {
    if (!continuing(pane)) {
        pane.selection.shiftBegin(pane.selectedIndices(), pane.cursorIndex)
        pane.selectionAnchor = pane.cursorIndex
    }
    Filter.moveCursor(pane, delta)
    extendTo(pane, pane.selectionAnchor)
    pane.selection.shiftMoved(pane.cursorIndex)
    pane.selectionVersion += 1
}

// Shift+click, the absolute twin of extend() above: the anchor latches to the cursor row before the
// click, which a plain click or ctrl+click already sets, and consecutive shift+clicks share one base.
// A click carries context 0 so the list never moves under the pointer.
function extendToRow(pane, index) {
    if (!continuing(pane)) {
        pane.selection.shiftBegin(pane.selectedIndices(), pane.cursorIndex)
        pane.selectionAnchor = pane.cursorIndex
    }
    Filter.setCursor(pane, index, 0)
    extendTo(pane, pane.selectionAnchor)
    pane.selection.shiftMoved(pane.cursorIndex)
    pane.selectionVersion += 1
}

// Ctrl+click, v's mouse twin. An empty set means the cursor row is selected, so it joins first.
// A click carries context 0 so the list never moves under the pointer.
function toggleRow(pane, index) {
    if (pane.selection.count() === 0 && pane.cursorIndex !== index) {
        pane.selection.toggle(pane.cursorIndex)
    }
    Filter.setCursor(pane, index, 0)
    pane.selection.toggle(index)
    pane.selectionAnchor = index
    pane.selectionVersion += 1
}

// A lone selection follows a plain move so delete takes the cursor row; deliberate marks drop lone.
function follow(pane) {
    if (!pane.selection.follows() || pane.cursorIndex === pane.selectedIndices()[0])
        return
    var keep = pane.selection.isLanded ? pane.selection.isLanded() : false
    pane.selection.only(pane.cursorIndex, keep)
    pane.selectionAnchor = pane.cursorIndex
    pane.selectionVersion += 1
}

// v on a lone following row keeps it as a deliberate mark instead of toggling it off.
function toggleSelect(pane) {
    if (!pane.selection.promote(pane.cursorIndex)) pane.selection.toggle(pane.cursorIndex)
    pane.selectionAnchor = pane.cursorIndex
    pane.selectionVersion += 1
}

// The rows drawn between the cursor and the anchor, for both gestures above. Inside a gesture the
// base joins them, so shrinking the range never removes a base mark; with no gesture this stays the
// plain single range it always was.
function extendTo(pane, anchor) {
    var state = pane.selection.shiftState()
    if (state === null) {
        if (pane.shown === null) {
            pane.selection.extendTo(pane.cursorIndex, anchor)
            return
        }
        pane.selection.clear()
        var single = Filter.between(pane.shown, pane.cursorIndex, anchor)
        for (var i = 0; i < single.length; i++) {
            pane.selection.toggle(single[i])
        }
        return
    }
    var range
    if (pane.shown === null) {
        range = []
        var lo = Math.min(pane.cursorIndex, anchor)
        var hi = Math.max(pane.cursorIndex, anchor)
        for (var r = lo; r <= hi; r++) {
            range.push(r)
        }
    } else {
        range = Filter.between(pane.shown, pane.cursorIndex, anchor)
    }
    pane.selection.shiftApply(range)
}
