.pragma library

// Slow-click rename shared by the list, grid and columns views: tap arms the pane timer, double click cancels, fire renames a still-held sole row.
var CLEARED = -2 // SlowClick.cancel's cleared value, read by Pane.qml's slowClickIndex.

// Pre-tap sole-selection fact the views capture before Tap.tapped selects for this tap.
function wasSoleSelection(pane, index) {
    if (!pane || index < 0) return false
    if (pane.selectionCount() !== 1 || !pane.isSelected(index)) return false
    return pane.cursorIndex === index
}
// Whether this tap starts the timer; records every tap so a tap on another row re-arms.
function arm(pane, index, modifiers, now, interval, dragging, wasSole) {
    var plain = (modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === 0
    var drag = dragging === undefined ? pane.dragActive : dragging
    var priorAt = pane.slowClickAt || 0
    var priorIndex = pane.slowClickIndex === undefined ? CLEARED : pane.slowClickIndex
    pane.slowClickAt = now
    pane.slowClickIndex = index
    if (!(index >= 0 && plain && pane.singleClick !== true && pane.clickRename !== false
            && pane.searchMode === "" && pane.renamingIndex < 0 && !pane.renamePending
            && pane.selectionBand === null && drag !== true))
        return false
    if (wasSole !== undefined) {
        if (!wasSole) return false
    } else if (!wasSoleSelection(pane, index)) {
        return false
    }
    return priorIndex === index && now - priorAt > interval
}

// The timer firing renames only when the cursor and sole selection still hold the armed row.
function fire(pane, dragging) {
    var index = pane.slowClickIndex
    pane.slowClickIndex = CLEARED
    if (index === undefined || index < 0) return false
    if (pane.menuVisible === true) return false
    var liveDrag = dragging === undefined ? pane.dragActive : dragging
    if (liveDrag === true) return false
    if (pane.renamingIndex >= 0 || pane.renamePending) return false
    if (pane.singleClick === true || pane.clickRename === false) return false
    if (pane.searchMode !== "" || pane.selectionBand !== null) return false
    var picked = pane.selectedIndices()
    if (picked.length !== 1 || picked[0] !== index || pane.cursorIndex !== index) return false
    pane.act("rename")
    return true
}

// A second tap in time, or a tap failing the arm, disarms without renaming.
function cancel(pane) {
    pane.slowClickIndex = CLEARED
}
