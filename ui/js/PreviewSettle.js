.pragma library

// Cursor preview loads stamp distinct moves: due(200, 0, 120) and due(100, 200, 120) load now; due(50, 0, 120) trails.
function due(now, last, interval) {
    var elapsed = now - last
    return elapsed >= interval || elapsed < 0
}

// plan(50, 0, 120, "b", "b", true) keeps the pending timer; callers suppress shown duplicates by identity before scheduling.
function plan(now, last, interval, key, lastKey, armedForKey) {
    if (key === lastKey && armedForKey === true)
        return "same"
    return due(now, last, interval) ? "now" : "later"
}

// A selection identity that matters only for multi-selections: a lone selection must not
// key on the version, since Marks.follow bumps it on every plain move with one row selected.
function selectionKey(count, version) {
    if (count <= 1)
        return ""
    return count + ":" + version
}
