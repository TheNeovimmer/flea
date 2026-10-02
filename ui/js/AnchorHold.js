.pragma library

// F2 and F4 helpers split from Anchor.js at its hard cap. Anchor owns the
// anchor lifecycle, this owns the resolve and the viewport restore it calls.
function hasUnheld(pane) {
    try {
        if (!pane.selectedIndices || !pane.rowFor)
            return false
        var indices = pane.selectedIndices()
        for (var i = 0; i < indices.length; i++) {
            if (!pane.rowFor(indices[i]))
                return true
        }
    } catch (e) {}
    return false
}

function canResolve(pane) {
    try {
        if (pane.backend && (pane.backend.send || pane.backend.askPaths))
            return true
    } catch (e) {}
    return false
}

function holdLeaf(path) {
    var text = String(path || "")
    var cut = text.lastIndexOf("/")
    return cut < 0 ? text : text.substring(cut + 1)
}

function startList(pane, anchor) {
    pane.openWithoutHistory(pane.path, { keptQuery: pane.filterQuery })
    if (anchor.start > 0)
        pane.backend.window(anchor.start, pane.windowSize)
}

function fillPaths(pane, anchor, list) {
    if (!anchor || !anchor.needPaths)
        return anchor
    var need = anchor.needPaths
    for (var i = 0; i < need.length && i < list.length; i++) {
        var nm = holdLeaf(String(list[i] || ""))
        for (var m = 0; m < anchor.marks.length; m++) {
            if (anchor.marks[m].index === need[i])
                anchor.marks[m].name = nm
        }
    }
    anchor.needPaths = null
    startList(pane, anchor)
    return anchor
}

function cursorView(pane) {
    try {
        if (pane.shown === null || pane.shown === undefined)
            return pane.cursorIndex
        var at = pane.shown.indexOf(pane.cursorIndex)
        return at < 0 ? 0 : at
    } catch (e) {}
    return pane.cursorIndex
}

function fillLocated(pane, anchor, matches, joinName) {
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
        var key = ""
        try { key = pane.join(pane.path, joinName(mark.name)) } catch (e) {}
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
    try {
        var area = pane.listArea || null
        if (!area || anchor.offset === undefined)
            return
        var rh = rowH || anchor.rowH || pane._rowH || 37
        var originY = typeof area.originY === "number" ? area.originY : 0
        var view = cursorView(pane)
        if (typeof area.contentY === "number")
            area.contentY = view * rh + originY - anchor.offset
    } catch (e) {}
}
