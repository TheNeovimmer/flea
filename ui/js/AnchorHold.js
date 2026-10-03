.pragma library

// The resolve and the viewport restore Anchor.js calls, split out at its hard cap.
var FALLBACK_ROW_H = 37 // Theme.fileRowHeight when the pane names none.

function hasUnheld(pane) {
    if (!pane.selectedIndices || !pane.rowFor)
        return false
    var indices = pane.selectedIndices()
    for (var i = 0; i < indices.length; i++) {
        if (!pane.rowFor(indices[i]))
            return true
    }
    return false
}

function canResolve(pane) {
    return !!(pane.backend && (pane.backend.send || pane.backend.askPaths))
}

function holdLeaf(path) {
    var text = String(path || "")
    var cut = text.lastIndexOf("/")
    return cut < 0 ? text : text.substring(cut + 1)
}

// The row height the anchor measures in: a grid tile row in the grid view, a text row elsewhere.
function rowHeight(pane, rowH) {
    if (pane.viewMode === "grid" && pane.listArea && typeof pane.listArea.cellHeightPx === "number")
        return pane.listArea.cellHeightPx
    return rowH || pane.anchorRowHeight || FALLBACK_ROW_H
}

// The cursor's view position as a restorable row: a tile row in the grid view, a list row elsewhere.
function viewRow(pane) {
    var view = cursorView(pane)
    if (pane.viewMode === "grid" && pane.listArea && typeof pane.listArea.columns === "number" && pane.listArea.columns > 0)
        return Math.floor(view / pane.listArea.columns)
    return view
}

// Lists the anchor's own directory; a navigation while the anchor waited drops the anchor and lists nothing, so the debt never travels.
function startList(pane, anchor) {
    if (!anchor || pane.path !== anchor.path)
        return null
    if (pane.recentMode && pane.recentMode.length > 0) {
        // Recent may deliver cached history synchronously, so its run must already see the anchor.
        pane.wire.anchor = anchor
        pane.refresh("")
        return anchor
    }
    pane.openWithoutHistory(anchor.path, { keptQuery: pane.filterQuery, wantChanged: anchor.wantChanged === true, inPlace: true })
    if (anchor.wantChanged) {
        pane.reloadFrom = anchor.reloadFrom
        pane.reloadChanged = -1
    }
    if (anchor.start > 0)
        pane.backend.window(anchor.start, pane.windowSize)
    return anchor
}

function fillPaths(pane, anchor, list) {
    if (!anchor || !anchor.needPaths)
        return anchor
    var need = anchor.needPaths
    for (var i = 0; i < need.length && i < list.length; i++) {
        var path = String(list[i] || "")
        var nm = pane.recentMode && pane.recentMode.length > 0 ? path.substring(1) : holdLeaf(path)
        for (var m = 0; m < anchor.marks.length; m++) {
            if (anchor.marks[m].index === need[i])
                anchor.marks[m].name = nm
        }
    }
    anchor.needPaths = null
    if (pane.pathsPending && pane.pathsPending.kind === "anchor")
        pane.pathsPending = null
    return startList(pane, anchor)
}

function cursorView(pane) {
    if (pane.shown === null || pane.shown === undefined)
        return pane.cursorIndex
    var at = pane.shown.indexOf(pane.cursorIndex)
    return at < 0 ? 0 : at
}

function fillLocated(pane, anchor, matches) {
    if (!anchor)
        return null
    anchor.locateDone = true
    var byPath = {}
    for (var i = 0; i < (matches || []).length; i++) {
        var item = matches[i]
        byPath[String(item.path || "")] = Number(item.index)
    }
    var pending = []
    for (var m = 0; m < (anchor.marks || []).length; m++) {
        var mark = anchor.marks[m]
        var key = (mark.name !== null && pane.join) ? pane.join(pane.path, mark.name) : ""
        var at = byPath[key]
        if (at !== undefined && at >= 0)
            anchor.kept.push(at)
        else if (mark.name !== null)
            pending.push(mark)
    }
    anchor.marks = pending
    return anchor
}

function restoreView(pane, anchor, rowH) {
    var area = pane.listArea || null
    if (!area || anchor.offset === undefined)
        return
    var rh = rowHeight(pane, rowH || anchor.rowH)
    var originY = typeof area.originY === "number" ? area.originY : 0
    var view = viewRow(pane)
    var y = view * rh + originY - anchor.offset
    // A restore past either end draws a blank strip, so clamp to the area's valid range when it names one.
    if (typeof area.contentY === "number") {
        if (typeof area.contentHeight === "number" && typeof area.height === "number") {
            var hi = Math.max(originY, area.contentHeight - area.height + originY)
            y = Math.max(originY, Math.min(hi, y))
        }
        area.contentY = y
    }
}
