.pragma library

function publish(pane, request, copied) {
    if (request.sequence !== pane.clipSequence) return
    pane.clipboard = { paths: request.paths, moving: request.moving }
    pane.message(copied(request.paths.length, request.moving), false)
}

// Untagged paths replies resolve one queued request at a time; only the newest choice publishes.
function drain(pane) {
    if (pane.clipPending !== null) return
    var queue = (pane.clipQueue || []).slice()
    while (queue.length) {
        var request = queue[0]
        if (request.paths !== null || request.sequence !== pane.clipSequence) {
            queue.shift()
            continue
        }
        if (request.path !== pane.path || request.listing !== pane.backend.heldListing || pane.listInFlight) {
            queue.shift()
            pane.message("Selected items changed; copy or cut again.", false)
            continue
        }
        pane.clipQueue = queue
        pane.clipPending = request
        pane.backend.askPaths(request.rows)
        return
    }
    pane.clipQueue = queue
}

function take(pane, moving, paths, indices, copied) {
    pane.clipSequence = (pane.clipSequence || 0) + 1
    var request = { sequence: pane.clipSequence, moving: moving, paths: paths ? paths.slice() : null,
        rows: paths ? null : indices.slice(), path: pane.path, listing: pane.backend.heldListing }
    pane.clipQueue = (pane.clipQueue || []).concat([request])
    if (request.paths !== null) publish(pane, request, copied)
    drain(pane)
}

function resolved(pane, list, copied) {
    if (pane.clipPending === null) return
    var sequence = pane.clipPending.sequence
    var queue = (pane.clipQueue || []).slice()
    for (var i = 0; i < queue.length; i++) {
        if (queue[i].sequence !== sequence) continue
        var request = Object.assign({}, queue[i], { paths: list.slice() })
        queue[i] = request
        publish(pane, request, copied)
        break
    }
    pane.clipQueue = queue
    pane.clipPending = null
    drain(pane)
}

function failed(pane) {
    if (pane.clipPending === null) return
    var sequence = pane.clipPending.sequence
    pane.clipQueue = (pane.clipQueue || []).filter(function (request) {
        return request.sequence !== sequence
    })
    pane.clipPending = null
    drain(pane)
}
