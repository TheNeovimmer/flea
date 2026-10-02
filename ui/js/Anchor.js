.pragma library

// Re-reading the open listing without moving the user off it. Two callers with one mechanism: a
// change another program made under the listing (ui/PaneWire.qml's watch) and Flea's own delete.
// Split out of ui/js/Nav.js, which sits at the 300-line JS cap, the same way tests/js/watch.js was
// split out of tests/js/nav.js; ui/js/Nav.js keeps navigation and this keeps the return.

// ui/PaneWire.qml watchBusy: a re-read renumbers rows, so it waits while anything names one, including a menu reply in flight.
function busy(pane) {
    if (!pane)
        return true
    if (pane.menuActions && (pane.menuActions.pendingAction || pane.menuActions.pendingActivation === true))
        return true
    return pane.listInFlight || pane.renamingIndex >= 0 || pane.renamePending
        || pane.menuVisible || (pane.menuActions && pane.menuActions.opened) || pane.filterTyping || pane.searchMode.length > 0
        || pane.selectionCount() > 0 || pane.selectionBand !== null || (pane.collide && pane.collide.pending !== null)
}

// A change another program made under the open listing, unlike ui/js/Nav.js refresh() which follows
// Flea's own write. The rows are read again and the cursor is put back on the file it was on by name,
// because a create above it renumbers every row below and a listing that jumped back to the top
// would move the user while they were reading it. Returns the anchor apply() resolves, or null.
function watched(pane, wantChanged) {
    return anchoredRefresh(pane, false, wantChanged)
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
    return anchoredRefresh(pane, true)
}

// A listing past its wait stops loading the pane: late rows are dropped as replaced.
function clearWaiting(pane) {
    if (pane.listingState === "waiting") {
        pane.listInFlight = false
        pane.listingState = "loading"
        pane.stateMessage = ""
        return true
    }
    return false
}

// Which row a full target path names, NFC-matched the way the backend lists it.
function selectMatch(rows, target, folder) {
    var base = String(folder || "")
    var text = String(target || "")
    var leaf = base.length <= 1 ? text.substring(1) : text.substring(base.length + 1)
    if (base.length > 1 && text.substring(0, base.length + 1) !== base + "/")
        return -1
    var want = typeof leaf.normalize === "function" ? leaf.normalize("NFC") : leaf
    for (var i = 0; i < rows.length; i++) {
        if (String(rows[i].n || "") === leaf)
            return i
    }
    for (var j = 0; j < rows.length; j++) {
        var name = String(rows[j].n || "")
        var norm = typeof name.normalize === "function" ? name.normalize("NFC") : name
        if (norm === want)
            return j
    }
    return -1
}

// The cursor index for a full target path, or -1 when the listing holds no such row.
function matchListed(pane, target) {
    var at = selectMatch(pane.rows, target, pane.path)
    return at >= 0 ? pane.held + at : -1
}

// A rename commit keeps the pointer's row on click-away or the renamed row on Enter, mapping the source leaf to the destination.
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

function anchoredRefresh(pane, select, wantChanged) {
    if (pane.listInFlight) {
        return null
    }
    var row = pane.rowFor(pane.cursorIndex)
    // The path rides along because the anchor can outlive one rows reply: a navigation between the
    // two below would otherwise put this directory's cursor row onto the next directory's listing.
    var anchor = { name: row ? String(row.n) : "", index: pane.cursorIndex, start: pane.held,
                   path: pane.path, select: select === true }
    // A filter narrows the rows the pane holds rather than choosing which directory it holds, so it
    // survives a re-read of the same directory; every other caller of openWithoutHistory drops it.
    pane.openWithoutHistory(pane.path, { keptQuery: pane.filterQuery, wantChanged: wantChanged === true })
    // The re-read answers from row 0, so a cursor deep in a large directory needs its own window back
    // before the anchor's name can be looked for anywhere near where it was.
    if (anchor.start > 0) {
        pane.backend.window(anchor.start, pane.windowSize)
    }
    return anchor
}

// Runs on each rows reply while an anchor stands. The name can arrive in the listing's own first
// window or in the one asked for above, so a miss in the first is not yet a miss. A name that is
// gone from both leaves the old index, which keeps the view where the user left it.
function apply(pane, anchor) {
    if (!anchor) {
        return null
    }
    if (pane.path !== anchor.path) {
        return null
    }
    for (var i = 0; i < pane.rows.length; i++) {
        if (String(pane.rows[i].n) === anchor.name) {
            landOn(pane, pane.held + i, anchor)
            return null
        }
    }
    // Still the first window rather than the one asked for above, so keep waiting, but only while that
    // window can still exist: a listing that shrank past the offset comes back clamped to row 0 instead.
    if (anchor.start > 0 && pane.held === 0 && pane.total > anchor.start) {
        return anchor
    }
    if (pane.total > 0) {
        landOn(pane, Math.min(anchor.index, pane.total - 1), anchor)
    }
    return null
}

// A watch's anchor only moves the cursor, because the operator's own selection belongs to them and a
// change another program made must not rewrite it. A delete's anchor selects, because the rows that
// were selected no longer exist and a cursor with nothing marked is a keyboard that has to start over.
function landOn(pane, index, anchor) {
    if (anchor.select)
        pane.selectOnly(index, 0)
    else
        pane.setCursor(index, 0)
}

// A preference re-list keeps selection and cursor by name; a mark outside the held window has no name to keep, so a partial selection clears whole rather than keeping its subset.
function preference(pane) {
    var rowFor = pane.rowFor ? function (i) { return pane.rowFor(i) } : null
    var cursorRow = rowFor ? rowFor(pane.cursorIndex) : null
    var names = []
    var indices = pane.selectedIndices ? pane.selectedIndices() : []
    if (rowFor) {
        for (var i = 0; i < indices.length; i++) {
            var row = rowFor(indices[i])
            if (!row) { names = []; break }
            names.push(String(row.n))
        }
    } else if (indices.length > 0) {
        names = []
    }
    return { name: cursorRow ? String(cursorRow.n) : "", index: pane.cursorIndex,
             start: pane.held, path: pane.path, selected: names }
}

// Resolves only on the rows reply for the asked window; a scrolled reply or a moved cursor drops the anchor instead of yanking it.
function applyPreference(pane, anchor) {
    if (!anchor)
        return null
    if (pane.path !== anchor.path)
        return null
    if (pane.cursorIndex !== 0 && pane.cursorIndex !== anchor.index)
        return null
    if (pane.held !== anchor.start) {
        if (anchor.start > 0 && pane.held === 0 && pane.total > anchor.start)
            return anchor
        if (!(anchor.start > 0 && pane.total <= anchor.start))
            return null
    }
    var cursorAt = -1
    for (var i = 0; i < pane.rows.length; i++) {
        if (String(pane.rows[i].n) === anchor.name) {
            cursorAt = pane.held + i
            break
        }
    }
    if (cursorAt < 0 && pane.total > 0)
        cursorAt = Math.min(anchor.index, pane.total - 1)
    var marks = []
    for (var s = 0; s < anchor.selected.length; s++) {
        for (var r = 0; r < pane.rows.length; r++) {
            if (String(pane.rows[r].n) === anchor.selected[s]) {
                marks.push(pane.held + r)
                break
            }
        }
    }
    if (cursorAt >= 0)
        pane.setCursor(cursorAt, 0)
    pane.selection.clear()
    for (var m = 0; m < marks.length; m++)
        pane.selection.toggle(marks[m])
    if (marks.length > 0 || cursorAt >= 0)
        pane.selectionVersion++
    return null
}
