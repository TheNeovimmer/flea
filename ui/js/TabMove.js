.pragma library

// Tabs040 callout 1: tabs reorder by drag and by keys. The pure reorder alone,
// with no pane in it; ui/js/Tabs.js snapshots the current tab around it and
// writes the packed strip back. Sample input: items ["a","b","c"], from 0.

// A drag answers an insertion point, 0 before the first tab and count past the
// last, so the pointer names where the tab lands rather than which tab it takes.
function insertionAt(x, tabWidth, count) {
    if (!(tabWidth > 0) || !(count > 0))
        return 0
    return Math.max(0, Math.min(count, Math.floor(x / tabWidth + 0.5)))
}

// The { and } keys move one place, clamping at either end rather than wrapping.
function step(from, delta, count) {
    return Math.max(0, Math.min(count - 1, from + delta))
}

// A favourite drag answers where the row lands and where the line draws, 0 before the first row and count past the last.
// Sample input: railReorder(40, 1, 30, 5) drops at 2 with the line at 3.
function railReorder(dy, from, rowHeight, count) {
    var n = Math.max(1, count)
    if (!(rowHeight > 0)) {
        return { to: Math.max(0, Math.min(n - 1, from)), line: Math.max(0, Math.min(n, from + (dy >= 0 ? 1 : 0))) }
    }
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
