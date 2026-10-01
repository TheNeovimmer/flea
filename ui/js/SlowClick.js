.pragma library

// Slow-click rename, one shared mechanism for the list, grid and columns
// views: a tap arms the pane's timer of the double-click interval, a second
// tap in time cancels it and opens as a double click does, and the timer fires
// a rename only when the cursor and the sole selection are still that row and
// nothing else started. now and interval are handed in so the window is
// assertable without a clock; interval is Qt.styleHints.mouseDoubleClickInterval
// on the live path. The drag state rides along because the views read it off
// their own drag session, which the pane never sees. It never arms on a double
// click, a drag, a search result, or in single-click mode, where one tap
// already opened. Firing on the timer rather than on the tap itself is what
// keeps the first tap of a double click on an already-selected row from
// starting a rename the second tap then lands in.

// Whether this tap starts the timer. Records every tap the way the arming tap
// used to, so a tap on another row re-arms rather than firing: only a second
// tap on the same row past the interval arms.
function arm(pane, index, modifiers, now, interval, dragging) {
    var plain = (modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === 0
    var drag = dragging === undefined ? pane.dragActive : dragging
    var priorAt = pane.slowClickAt || 0
    var priorIndex = pane.slowClickIndex === undefined ? -2 : pane.slowClickIndex
    pane.slowClickAt = now
    pane.slowClickIndex = index
    if (!(index >= 0 && plain && pane.singleClick !== true && pane.clickRename !== false
            && pane.searchMode === "" && pane.renamingIndex < 0 && !pane.renamePending
            && pane.selectionBand === null && drag !== true))
        return false
    var picked = pane.selectedIndices()
    if (picked.length !== 1 || picked[0] !== index || pane.cursorIndex !== index)
        return false
    var gap = interval > 0 ? interval : 400
    return priorIndex === index && now - priorAt > gap
}

// The timer firing: renames only when the cursor and the sole selection are
// still the armed row and nothing else started. Consumes the arm either way,
// so a later tap re-arms rather than firing twice.
function fire(pane, now, interval) {
    var index = pane.slowClickIndex
    var at = pane.slowClickAt || 0
    pane.slowClickIndex = -2
    if (index === undefined || index < 0) return false
    var gap = interval > 0 ? interval : 400
    if (!(now - at > gap)) return false
    if (pane.renamingIndex >= 0 || pane.renamePending) return false
    if (pane.singleClick === true || pane.clickRename === false) return false
    if (pane.searchMode !== "" || pane.selectionBand !== null) return false
    var picked = pane.selectedIndices()
    if (picked.length !== 1 || picked[0] !== index || pane.cursorIndex !== index) return false
    pane.act("rename")
    return true
}

// A second tap in time, or a tap that fails the arm, disarms without renaming.
function cancel(pane) {
    pane.slowClickIndex = -2
}
