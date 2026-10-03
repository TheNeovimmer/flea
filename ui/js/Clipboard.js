.pragma library

.import "ClipMarks.js" as ClipMarks

function empty() { return { paths: [], moving: false, token: "" } }
function state() { return { sets: [], ownTokens: Object.create(null), generation: 0, failed: [], gets: [], deferred: null } }
function session(pane) {
    if (!pane.clipboardState) pane.clipboardState = state()
    return pane.clipboardState
}

function set(pane, paths, moving) {
    var s = session(pane)
    s.generation += 1
    s.deferred = null
    var clip = { paths: paths, moving: moving, token: "" }
    pane.clipboard = clip
    s.sets.push({ pane: pane, backend: pane.backend, clip: clip })
    pane.backend.send({ c: "clipSet", op: moving ? "cut" : "copy", paths: paths })
}

function take(queue, backend) {
    for (var i = 0; i < queue.length; i++) {
        if (queue[i].backend === backend) return queue.splice(i, 1)[0]
    }
    return null
}

function replace(pane, message) {
    pane.clipboard = message.clip === "copy" || message.clip === "cut"
        ? { paths: message.paths || [], moving: message.clip === "cut", token: message.token || "" }
        : empty()
}

function pendingEcho(s, message) {
    if (!message.token) return false
    for (var i = 0; i < s.sets.length; i++) {
        var clip = s.sets[i].clip
        if (clip.moving !== (message.clip === "cut") || clip.paths.length !== message.paths.length) continue
        var equal = true
        for (var j = 0; j < clip.paths.length; j++)
            if (clip.paths[j] !== message.paths[j]) { equal = false; break }
        if (equal) return true
    }
    return false
}

function selection(pane, message, s) {
    s.deferred = null
    if (message.token && s.ownTokens[message.token]) return
    // A watcher can see our owner before set answers with its token.
    if (pendingEcho(s, message)) { s.deferred = {pane: pane, message: message}; return }
    replace(pane, message)
}

function receive(pane, message) {
    var s = session(pane)
    if (message.op === "set") {
        var entry = take(s.sets, pane.backend)
        if (!entry) return
        if (!message.ok) {
            entry.pane.message("Copied in this window only: " + message.error, true)
        } else {
            // Both panes can echo any earlier owner after a later set has answered.
            if (message.token) s.ownTokens[message.token] = true
            // The collision card may already hold this cut, so its snapshot keeps the token too.
            entry.clip.token = message.token
            if (pane.clipboard === entry.clip)
                pane.clipboard = { paths: entry.clip.paths, moving: entry.clip.moving, token: message.token }
        }
        var deferred = s.deferred
        if (deferred) {
            s.deferred = null
            selection(deferred.pane, deferred.message, s)
        }
    } else if (message.op === "changed") {
        var index = s.failed.indexOf(pane.backend)
        if (message.error) {
            if (index < 0) s.failed.push(pane.backend)
            return
        }
        if (index >= 0) s.failed.splice(index, 1)
        selection(pane, message, s)
    } else if (message.op === "get") {
        var waiting = take(s.gets, pane.backend)
        if (!waiting) return
        // A refused read keeps the in-window copy usable without claiming system ownership.
        if (message.ok && waiting.generation === s.generation) replace(pane, message)
        waiting.ready()
    } else if (message.op === "clear" && message.ok === false) {
        pane.message("Could not clear the system clipboard: " + message.error, true)
    }
}

function read(pane, ready) {
    var s = session(pane)
    if (s.failed.indexOf(pane.backend) < 0) { ready(); return }
    for (var i = 0; i < s.gets.length; i++) {
        if (s.gets[i].backend === pane.backend) {
            pane.message("Still reading the clipboard; try again.", false)
            return
        }
    }
    s.gets.push({ backend: pane.backend, ready: ready, generation: s.generation })
    pane.backend.send({ c: "clipGet" })
}

// All paste verbs read the same file selection, including the no-watcher fallback.
function paste(pane, linkKind, forceMove) {
    var dest = pane.path
    function ready() {
        if (pane.path !== dest || pane.listInFlight || pane.recentMode) {
            pane.message("The paste destination changed; try again.", false)
            return
        }
        var clip = pane.clipboard
        var sources = clip.paths
        if (sources.length === 0) {
            pane.message("There is nothing to paste; y copies and x cuts.", false)
            return
        }
        pane.collide.ask({ c: linkKind ? "link" : "transfer",
            op: linkKind || (forceMove || clip.moving ? "move" : "copy"), paths: sources, dest: dest },
            null, !linkKind && clip.moving)
    }
    read(pane, ready)
}

// Clear only the cut captured by this transfer, never a newer selection on the card.
function spent(pane, clip, spendsCut) {
    if (ClipMarks.spent(clip, spendsCut) === clip) return
    pane.backend.send(clip.token ? { c: "clipClear", token: clip.token }
                                : { c: "clipClear", cut: clip.paths })
    if (pane.clipboard === clip || (pane.clipboard.paths === clip.paths && pane.clipboard.token === clip.token))
        pane.clipboard = empty()
}
