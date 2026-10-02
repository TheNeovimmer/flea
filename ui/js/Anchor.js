.pragma library

.import "AnchorHold.js" as Hold

// Re-reading the open listing without moving the user off it, for a foreign change and Flea's own delete.
var FALLBACK_ROW_H = 37 // Theme.fileRowHeight when the caller names none.

// A re-read renumbers every row, so it waits while an interaction owns the rows, while any paths asker resolves, or while unheld marks have no resolver.
function busy(pane) {
    if (!pane)
        return true
    if (pane.menuActions && (pane.menuActions.pendingAction || pane.menuActions.pendingActivation === true))
        return true
    if (pane.dragActive === true || pane.awaitingPaths === true)
        return true
    if (pane.pathsPending)
        return true
    if (pane.clipPending !== undefined && pane.clipPending !== null)
        return true
    // F2 fallback: a mark outside the held window needs a paths resolve; without a backend that answers it the re-read waits. Empty listings hold nothing.
    if (pane.total > 0 && Hold.hasUnheld(pane) && !Hold.canResolve(pane))
        return true
    return pane.listInFlight || pane.renamingIndex >= 0 || pane.renamePending
        || pane.menuVisible || (pane.menuActions && pane.menuActions.opened) || pane.filterTyping || pane.searchMode.length > 0
        || pane.selectionBand !== null || (pane.collide && pane.collide.pending !== null)
}

function watched(pane, rowH) {
    return anchoredRefresh(pane, false, selectedMarks(pane), rowH)
}

// Flea's own delete: the anchor is the deleted cursor row and apply()'s fallback lands on whatever took its place, which is Finder's rule. A failed delete matches by name instead.
// Sample input: afterDelete(pane, true) with pane.trashedFirst set by Ops.trash.
function afterDelete(pane, landed) {
    if (landed && pane.trashedFirst >= 0)
        pane.cursorIndex = pane.trashedFirst
    pane.trashedFirst = -1
    return anchoredRefresh(pane, true, null)
}

// A rename commit keeps the row the operator was on: the pointer's row for a click-away, the renamed row for Enter.
function pointerRow(pane, request) {
    var row = pane.rowFor(pane.cursorIndex)
    var name = row ? String(row.n) : ""
    var src = leaf(request.source)
    var dst = request.destination ? leaf(request.destination) : ""
    if (name === src && dst.length > 0)
        name = dst
    return { name: name, index: pane.cursorIndex, start: pane.held, path: pane.path, select: true }
}

function leaf(path) {
    var text = String(path || "")
    var cut = text.lastIndexOf("/")
    return cut < 0 ? text : text.substring(cut + 1)
}

function anchoredRefresh(pane, select, marks, rowH) {
    if (pane.listInFlight) {
        return null
    }
    var row = pane.rowFor(pane.cursorIndex)
    var lone = pane.selection && typeof pane.selection.follows === "function" ? !!pane.selection.follows() : false
    var rh = Hold.rowHeight(pane, rowH)
    var view = Hold.viewRow(pane)
    var area = pane.listArea || null
    var contentY = area && typeof area.contentY === "number" ? area.contentY : 0
    var originY = area && typeof area.originY === "number" ? area.originY : 0
    // The path rides along because the anchor can outlive one rows reply: a navigation between the two below would otherwise put this directory's cursor row onto the next directory's listing.
    var anchor = { name: row ? String(row.n) : "", index: pane.cursorIndex, start: pane.held,
                   path: pane.path, select: select === true,
                   marks: marks || null, kept: [], hadMarks: marks !== null && marks.length > 0,
                   lone: lone, offset: view * rh + originY - contentY, rowH: rh, view: view }
    // F2: names outside the held window come from one batched paths request before the swap, tagged so the reply reaches only this asker.
    if (anchor.marks) {
        var need = []
        for (var i = 0; i < anchor.marks.length; i++) {
            if (anchor.marks[i].name === null)
                need.push(anchor.marks[i].index)
        }
        if (need.length > 0 && !pane.pathsPending && (pane.clipPending === undefined || pane.clipPending === null)) {
            var sent = false
            try {
                if (pane.backend && pane.backend.send) { pane.backend.send({ c: "paths", rows: need }); sent = true }
                else if (pane.backend && pane.backend.askPaths) { pane.backend.askPaths(need); sent = true }
            } catch (e) { console.warn("flea: anchor paths ask failed, listing without unheld names") }
            if (sent) {
                anchor.needPaths = need
                pane.pathsPending = { kind: "anchor" }
                return anchor
            }
        }
    }
    Hold.startList(pane, anchor)
    return anchor
}

// The batched paths answer for F2: fills unheld names, then starts the list the swap holds.
function fillPaths(pane, anchor, list) {
    return Hold.fillPaths(pane, anchor, list)
}

// True only for the anchor's own tagged reply; a clipboard, drag or compress reply takes nothing.
function takesPaths(pane, anchor) {
    return !!(anchor && anchor.needPaths && pane.pathsPending && pane.pathsPending.kind === "anchor")
}

// A failed or refused anchor ask ends the anchor on its found-or-clamped index and releases its tag.
// Sample input: failAnchor(pane, { name: "gone", index: 4, marks: [], kept: [] }) lands min(4, total - 1).
function failAnchor(pane, anchor, rowH) {
    if (!anchor)
        return null
    anchor.needPaths = null
    anchor.locateDone = true
    if (pane.pathsPending && pane.pathsPending.kind === "anchor")
        pane.pathsPending = null
    // A failed ask still owes the listing that draws the outside change, unless one is already out.
    if (!pane.listInFlight)
        Hold.startList(pane, anchor)
    var at = indexOf(pane, anchor.name)
    if (pane.total > 0) {
        landOn(pane, at >= 0 ? at : Math.min(anchor.index, pane.total - 1), anchor)
        Hold.restoreView(pane, anchor, rowH)
    }
    finishMarks(pane, anchor)
    return null
}

// PaneWire's located guard: a reply for another directory belongs to nobody here, a refused one ends the anchor.
// Sample input: takeLocated(pane, anchor, { directory: "/d", ok: true, matches: [{ path: "/d/a", index: 3 }] }).
function takeLocated(pane, anchor, message, rowH) {
    if (!anchor || !anchor.locateSent || anchor.locateDone)
        return { handled: false, anchor: anchor }
    if (!message || message.directory !== pane.path)
        return { handled: false, anchor: anchor }
    if (message.ok === false)
        return { handled: true, anchor: failAnchor(pane, anchor, rowH) }
    return { handled: true, anchor: fillLocated(pane, anchor, message.matches || [], rowH) }
}

// The marks the re-read carries across by file identity: an index renumbers under a fresh list, so each marked row's name is recorded and looked up again when the rows land. A gone name loses its mark rather than re-pointing at another file.
function selectedMarks(pane) {
    if (!pane.selectedIndices)
        return []
    var out = []
    var indices = pane.selectedIndices()
    for (var i = 0; i < indices.length; i++) {
        var row = pane.rowFor(indices[i])
        out.push({ index: indices[i], name: row ? String(row.n) : null })
    }
    return out
}

// The listing row holding a name in the window the pane holds now, or -1.
function indexOf(pane, name) {
    for (var i = 0; i < pane.rows.length; i++) {
        if (String(pane.rows[i].n) === name)
            return pane.held + i
    }
    return -1
}

// Moves whatever the held window holds from pending to kept, naming nothing on screen: the take lands once, when the anchor resolves, so no rows reply in between draws a half-restored set.
function sweepMarks(pane, anchor) {
    if (!anchor.marks)
        return
    var pending = []
    for (var m = 0; m < anchor.marks.length; m++) {
        var mark = anchor.marks[m]
        if (mark.name === null)
            continue
        var at = indexOf(pane, mark.name)
        if (at >= 0)
            anchor.kept.push(at)
        else
            pending.push(mark)
    }
    anchor.marks = pending
}

// The one take, on the anchor resolving: the rows the re-read cleared are marked again on the same files, and whatever is gone stays gone. A lone selection restores with only(), the way Tabs.restoreSelection does, so a plain click never turns sticky behind the re-read.
function finishMarks(pane, anchor) {
    var kept = anchor.kept || []
    anchor.kept = []
    anchor.marks = []
    if (!anchor.hadMarks)
        return
    if (anchor.lone === true && kept.length === 1) {
        pane.selection.only(kept[0])
        pane.selectionAnchor = pane.cursorIndex
        pane.selectionVersion += 1
        return
    }
    for (var i = 0; i < kept.length; i++)
        pane.selection.toggle(kept[i])
    pane.selectionAnchor = pane.cursorIndex
    if (kept.length > 0)
        pane.selectionVersion += 1
}

// Runs on each rows reply while an anchor stands. A miss in the listing's first window is not yet a miss when the anchor asked for its own window above. A gone name falls back to the clamped old index, which keeps the view where the user left it.
function apply(pane, anchor, rowH) {
    if (!anchor) {
        return null
    }
    if (pane.path !== anchor.path) {
        return null
    }
    if (anchor.needPaths)
        return anchor
    sweepMarks(pane, anchor)
    // F3: past the first window the cursor name alone must not finish held marks past it.
    if (anchor.start > 0 && pane.held !== anchor.start && pane.total > anchor.start)
        return anchor
    var at = indexOf(pane, anchor.name)
    // F2: marks past the held window resolve through one batched locate after.
    if (anchor.marks && anchor.marks.length > 0 && !anchor.locateDone && Hold.canResolve(pane)) {
        var paths = []
        for (var m = 0; m < anchor.marks.length; m++) {
            if (anchor.marks[m].name !== null)
                paths.push(pane.join(pane.path, anchor.marks[m].name))
        }
        if (paths.length > 0 && !anchor.locateSent) {
            var sent = false
            try {
                if (pane.backend && pane.backend.send) { pane.backend.send({ c: "locate", paths: paths }); sent = true }
                else if (pane.backend && pane.backend.askLocate) { pane.backend.askLocate(paths); sent = true }
            } catch (e) { console.warn("flea: anchor locate ask failed, landing on the clamped index") }
            if (!sent)
                return failAnchor(pane, anchor, rowH)
            anchor.locateSent = true
            anchor.locatePaths = paths
            // A gone cursor file still lands on the clamped old index while its marks resolve.
            if (pane.total > 0) {
                landOn(pane, at >= 0 ? at : Math.min(anchor.index, pane.total - 1), anchor)
                Hold.restoreView(pane, anchor, rowH)
            }
            return anchor
        }
        if (anchor.locateSent && !anchor.locateDone)
            return anchor
    }
    if (at >= 0) {
        landOn(pane, at, anchor)
        Hold.restoreView(pane, anchor, rowH)
        finishMarks(pane, anchor)
        return null
    }
    // Still the first window rather than the one asked for above, so keep waiting, but only while that window can still exist: a listing that shrank past the offset comes back clamped to row 0 instead.
    if (anchor.start > 0 && pane.held === 0 && pane.total > anchor.start) {
        return anchor
    }
    if (pane.total > 0) {
        landOn(pane, Math.min(anchor.index, pane.total - 1), anchor)
        Hold.restoreView(pane, anchor, rowH)
    }
    finishMarks(pane, anchor)
    return null
}

// The batched locate answer for F2: indices outside the held window join kept, the gone stay gone, and the cursor lands found-or-clamped either way.
// Sample input: fillLocated(pane, anchor, [{ path: "/d/a", index: 3 }]) keeps 3 and lands the cursor.
function fillLocated(pane, anchor, matches, rowH) {
    if (!anchor)
        return null
    Hold.fillLocated(pane, anchor, matches)
    var at = indexOf(pane, anchor.name)
    if (pane.total > 0) {
        landOn(pane, at >= 0 ? at : Math.min(anchor.index, pane.total - 1), anchor)
        Hold.restoreView(pane, anchor, rowH)
    }
    finishMarks(pane, anchor)
    return null
}

// A watch's anchor moves the cursor and re-marks the same files: the operator's marks belong to them, and a change another program made must not move those marks onto other files. A delete's anchor selects instead, because its rows no longer exist and a bare cursor would restart the keyboard.
function landOn(pane, index, anchor) {
    if (anchor.select)
        pane.selectOnly(index, 0)
    else
        pane.setCursor(index, 0)
}
