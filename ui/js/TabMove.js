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
// A favourite drag answers where the row lands and the line draws: (40, 1, 30, 5) drops at 2, line at 3.
function railReorder(dy, from, rowHeight, count) {
    var n = Math.max(1, count)
    var step = Math.round(dy / rowHeight)
    return { to: Math.max(0, Math.min(n - 1, from + step)),
        line: Math.max(0, Math.min(n, from + step + (dy >= 0 ? 1 : 0))) }
}

// Move the entry at from so it ends at index to, keeping the current tab
// current: the entry dragged along follows, and one crossed over shifts back.
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
