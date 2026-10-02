.pragma library

// Reorder is pure with no pane; Tabs.js snapshots around it.
// Sample input: items ["a","b","c"], from 0.

// A drag names the insertion point, not the tab it takes.
function insertionAt(x, tabWidth, count) {
    if (!(tabWidth > 0) || !(count > 0))
        return 0
    return Math.max(0, Math.min(count, Math.floor(x / tabWidth + 0.5)))
}

// The { and } keys move one place, clamping at either end rather than wrapping.
function step(from, delta, count) {
    return Math.max(0, Math.min(count - 1, from + delta))
}

// A move keeps the current tab current across the shift.
function reorder(items, from, to, index) {
    if (from < 0 || from >= items.length || to < 0 || to >= items.length || from === to)
        return index
    var moving = items.splice(from, 1)[0]
    items.splice(to, 0, moving)
    if (index === from)
        return to
    if (from < index && to >= index)
        return index - 1
    if (from > index && to <= index)
        return index + 1
    return index
}
