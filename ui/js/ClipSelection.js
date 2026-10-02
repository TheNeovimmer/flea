.pragma library

// Only one untagged paths reply may be outstanding; the latest overlapping selection waits with its own verb.
function take(pane, moving, paths, indices, copied) {
    if (paths) {
        pane.clipboard = { paths: paths, moving: moving }
        pane.clipQueued = pane.clipPending !== null ? { paths: paths, moving: moving } : null
        pane.message(copied(paths.length, moving), false)
        return
    }
    if (pane.clipPending !== null) {
        pane.clipQueued = { rows: indices.slice(), moving: moving, path: pane.path, listing: pane.backend.heldListing }
        return
    }
    pane.clipPending = moving
    pane.backend.askPaths(indices)
}

// A resolved menu choice already replaced the clipboard; an older reply cannot replace it again.
function resolved(pane, list, copied) {
    if (pane.clipPending === null) return
    var moving = pane.clipPending
    var queued = pane.clipQueued
    pane.clipPending = null
    pane.clipQueued = null
    if (queued && queued.paths) return
    pane.clipboard = { paths: list, moving: moving }
    pane.message(copied(list.length, moving), false)
    if (!queued) return
    if (queued.path !== pane.path || queued.listing !== pane.backend.heldListing || pane.listInFlight) {
        pane.message("Selected items changed; copy or cut again.", false)
        return
    }
    pane.clipPending = queued.moving
    pane.backend.askPaths(queued.rows)
}
