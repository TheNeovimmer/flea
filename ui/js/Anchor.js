.pragma library

.import "AnchorHold.js" as Hold

// Re-reading the open listing without moving the user off it. Two callers with one mechanism: a
// change another program made under the listing (ui/PaneWire.qml's watch) and Flea's own delete.
// Split out of ui/js/Nav.js, which sits at the 300-line JS cap, the same way tests/js/watch.js was
// split out of tests/js/nav.js; ui/js/Nav.js keeps navigation and this keeps the return.

// ui/PaneWire.qml watchBusy: a re-read renumbers every row, so it waits while an interaction
// owns the rows: an open rename editor, an open menu or a menu action waiting on its reply (a
// re-read flips menuSelectionIdentity and the reply is refused), a filter line being typed, a
// search walk (which owns the rows outright), a rubber-band drag, a file drag, the collision
// card's transfer, or a listing already in flight. A bare selection holds nothing back: xw5
// re-anchors the marks by file identity instead, so another window's change shows at once.
function busy(pane) {
    if (!pane)
        return true
    if (pane.menuActions && (pane.menuActions.pendingAction || pane.menuActions.pendingActivation === true))
        return true
    if (pane.dragActive === true || pane.awaitingPaths === true)
        return true
    if (pane.fileDragActive === true || pane.fileDragAwaiting === true)
        return true
    if (pane.listArea && (pane.listArea.dragActive === true || pane.listArea.dragAwaiting === true))
        return true
    // F2 fallback: a mark outside the held window needs a paths resolve; without a backend
    // that can answer it the re-read waits, as before xw5. Empty listings hold nothing.
    if (pane.total > 0 && Hold.hasUnheld(pane) && !Hold.canResolve(pane))
        return true
    return pane.listInFlight || pane.renamingIndex >= 0 || pane.renamePending
        || pane.menuVisible || (pane.menuActions && pane.menuActions.opened) || pane.filterTyping || pane.searchMode.length > 0
        || pane.selectionBand !== null || (pane.collide && pane.collide.pending !== null)
}

function watched(pane, renames, rowH) {
    return anchoredRefresh(pane, false, renames || null, selectedMarks(pane), rowH)
}

// Flea's own delete. The rows that were marked are gone, so there is usually no name to return to:
// the anchor is the cursor row that was deleted and apply()'s own fallback then lands on
// whatever took its place, which is Finder's rule. It selects that row as well, so the next delete
// follows without reaching for the mouse; reported 2026-09-11, "deleting one refreshes the entire
// file list and loses my selection, so I have to start over". A delete that failed leaves the row
// standing, and then the name matches and the cursor goes back exactly where it was.
function afterDelete(pane, landed) {
    // A block leaves as a block, so the cursor belongs on the row the block left rather than on the
    // row below wherever it sat inside it; a delete that failed keeps the row it was already on.
    if (landed && pane.trashedFirst >= 0)
        pane.cursorIndex = pane.trashedFirst
    pane.trashedFirst = -1
    return anchoredRefresh(pane, true, null, null)
}

// A rename commit keeps the row the operator was on: the pointer's row for a click-away,
// the renamed row for Enter (the cursor still sits on the source, so that leaf maps to dest).
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

function anchoredRefresh(pane, select, renames, marks, rowH) {
    if (pane.listInFlight) {
        return null
    }
    var row = pane.rowFor(pane.cursorIndex)
    var lone = false
    try { lone = !!(pane.selection && pane.selection.follows && pane.selection.follows()) } catch (e) {}
    var rh = rowH || pane._rowH || 37
    var view = Hold.cursorView(pane)
    var area = pane.listArea || null
    var contentY = area && typeof area.contentY === "number" ? area.contentY : 0
    var originY = area && typeof area.originY === "number" ? area.originY : 0
    // The path rides along because the anchor can outlive one rows reply: a navigation between the
    // two below would otherwise put this directory's cursor row onto the next directory's listing.
    var anchor = { name: row ? String(row.n) : "", index: pane.cursorIndex, start: pane.held,
                   path: pane.path, select: select === true, renames: renames || null,
                   marks: marks || null, kept: [], hadMarks: marks !== null && marks.length > 0,
                   lone: lone, offset: view * rh + originY - contentY, rowH: rh, view: view }
    // F2: names outside the held window come from one batched paths request before the swap.
    if (anchor.marks) {
        var need = []
        for (var i = 0; i < anchor.marks.length; i++) {
            if (anchor.marks[i].name === null)
                need.push(anchor.marks[i].index)
        }
        if (need.length > 0) {
            var sent = false
            try {
                if (pane.backend && pane.backend.send) { pane.backend.send({ c: "paths", rows: need }); sent = true }
                else if (pane.backend && pane.backend.askPaths) { pane.backend.askPaths(need); sent = true }
            } catch (e) {}
            if (sent) {
                anchor.needPaths = need
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

// The marks the re-read carries across by file identity: a selection names rows by index, and a
// fresh list renumbers every row, so each marked row's name is recorded and looked up again when
// the rows land. A name that is gone when the rows land loses its mark rather than re-pointing at
// another file (which is how a delete hits the wrong ones). Unheld names arrive through one
// batched paths request before the swap, so no per-file sweep pays rule 1.
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

// A rename the watcher reported as a pair keeps identity across the new name; any other rename is
// a delete plus a create as far as the one-line changed notice says, so the mark goes.
function pairedName(anchor, name) {
    if (anchor.renames && anchor.renames[name] !== undefined)
        return String(anchor.renames[name])
    return name
}

// The listing row holding a name in the window the pane holds now, or -1.
function indexOf(pane, name) {
    for (var i = 0; i < pane.rows.length; i++) {
        if (String(pane.rows[i].n) === name)
            return pane.held + i
    }
    return -1
}

// Moves whatever the held window holds from pending to kept, naming nothing on screen: the take
// lands once, when the anchor resolves, so no rows reply in between draws a half-restored set.
function sweepMarks(pane, anchor) {
    if (!anchor.marks)
        return
    var pending = []
    for (var m = 0; m < anchor.marks.length; m++) {
        var mark = anchor.marks[m]
        if (mark.name === null)
            continue
        var at = indexOf(pane, pairedName(anchor, mark.name))
        if (at >= 0)
            anchor.kept.push(at)
        else
            pending.push(mark)
    }
    anchor.marks = pending
}

// The one take, on the anchor resolving: the rows the re-read cleared are marked again on the same
// files, and whatever is gone stays gone. A lone selection restores with only(), the way
// Tabs.restoreSelection does, so a plain click never turns sticky behind the re-read.
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

// Runs on each rows reply while an anchor stands. The name can arrive in the listing's own first
// window or in the one asked for above, so a miss in the first is not yet a miss. A name that is
// gone from both leaves the old index, which keeps the view where the user left it. The cursor
// lands through setCursor with context 0, which moves no viewport; the offset recorded at the
// request restores contentY, so the cursor row stays at the same screen y.
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
    var at = indexOf(pane, pairedName(anchor, anchor.name))
    // F2: marks past the held window resolve through one batched locate after.
    if (anchor.marks && anchor.marks.length > 0 && !anchor.locateDone && Hold.canResolve(pane)) {
        var paths = []
        for (var m = 0; m < anchor.marks.length; m++) {
            if (anchor.marks[m].name !== null)
                paths.push(pane.join(pane.path, pairedName(anchor, anchor.marks[m].name)))
        }
        if (paths.length > 0 && !anchor.locateSent) {
            anchor.locateSent = true
            anchor.locatePaths = paths
            try {
                if (pane.backend && pane.backend.send)
                    pane.backend.send({ c: "locate", paths: paths })
                else if (pane.backend && pane.backend.askLocate)
                    pane.backend.askLocate(paths)
            } catch (e) {}
            if (at >= 0) {
                landOn(pane, at, anchor)
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
    // Still the first window rather than the one asked for above, so keep waiting, but only while that
    // window can still exist: a listing that shrank past the offset comes back clamped to row 0 instead.
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

// The batched locate answer for F2: indices outside the held window join kept, the gone stay gone.
function fillLocated(pane, anchor, matches) {
    if (!anchor)
        return null
    Hold.fillLocated(pane, anchor, matches, function (name) { return pairedName(anchor, name) })
    finishMarks(pane, anchor)
    return null
}

// A watch's anchor moves the cursor and re-marks the same files: the operator's marks belong to
// them, and a change another program made must not move those marks onto other files, which is why
// the re-read carries names and a name that is gone loses its mark. A delete's anchor selects,
// because the rows that were selected no longer exist and a cursor with nothing marked is a
// keyboard that has to start over.
function landOn(pane, index, anchor) {
    if (anchor.select)
        pane.selectOnly(index, 0)
    else
        pane.setCursor(index, 0)
}
