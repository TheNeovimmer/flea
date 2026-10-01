.pragma library

.import "Filter.js" as Filter
.import "Format.js" as Format
.import "RecentMode.js" as RecentMode
.import "Search.js" as Search
.import "Sort.js" as Sort
.import "Startup.js" as Startup
.import "TabMove.js" as TabMove

// Hidden tabs are snapshots, so the pane and backend still own only one listing.
// The nine-tab cap matches TUI's direct digit selection; GUI shortcuts cycle through the same state.

var MAX = 9

// Where a tab snapshotted now should reopen: a search sets pane.path to the scope it walks, so the
// directory the user was in is searchFrom, and every caller reads this BEFORE dropOverlay clears it.
// A history is not a directory, so a pane standing on one records the folder it was opened over.
function restingPath(pane) {
    if (pane.searchMode === "results" && (pane.searchFrom || "").length > 0)
        return pane.searchFrom
    return RecentMode.restingPath(pane) || pane.path
}

function snapshot(pane, path) {
    var where = path === undefined ? restingPath(pane) : path
    // A cursor and a selection read off a search's own listing name nothing in the directory the
    // tab records, so a tab stepping back out of a search starts at its first row with none.
    var elsewhere = where !== pane.path
    return {
        path: where,
        history: pane.history.slice(),
        forwardHistory: (pane.forwardHistory || []).slice(),
        cursorIndex: elsewhere ? 0 : pane.cursorIndex,
        viewMode: pane.viewMode,
        showHidden: pane.showHidden,
        selected: elsewhere ? [] : pane.selectedIndices().slice(),
        // A lone row restores with only(), so a tab switch never re-arms the row a tap left behind.
        follows: elsewhere ? false : pane.selection.follows(),
        sortBy: pane.backend.sortBy,
        sortDesc: pane.backend.sortDesc,
        // Issue 94, nixfred: the counter every list bumps, so a selection only returns to its own rows.
        listRequests: pane.backend.listRequests,
        // The directory's filesystem, so a drop on this tab while another shows decides move against copy.
        dev: elsewhere ? 0 : pane.backend.dirDev
    }
}

function pack(items, index) {
    return {
        items: items,
        index: index,
        pendingCursor: -1,
        pendingSortBy: "",
        pendingSortDesc: false
    }
}

function label(path, home) {
    if (!path || path === "/")
        return "/"
    if (home && path === home)
        return "Home"
    var leaf = Format.leafPart(Format.tilde(path, home || ""))
    return leaf.length > 0 ? leaf : path
}

// The current tab's path lives on the pane, not in the snapshot, so a navigate does not wait for a switch.
function labelAt(pane, i) {
    return label(pathAt(pane.tabs, currentIndex(pane), i, pane.path), pane.home)
}

// The path tab i draws: the live pane path for the current tab, the snapshot's for a hidden one.
// Takes the values rather than the pane so ui/TabBar.qml's binding can read each one by name.
function pathAt(tabs, index, i, currentPath) {
    if (i === index)
        return currentPath
    return tabs && tabs.items && tabs.items[i] ? tabs.items[i].path : ""
}

// The tab's filesystem the same way, 0 when unknown, which ui/js/Drag.js verbFor reads as copy.
function devAt(tabs, index, i, currentDev) {
    if (i === index)
        return currentDev
    return tabs && tabs.items && tabs.items[i] ? Number(tabs.items[i].dev) || 0 : 0
}

function labels(pane) {
    var n = count(pane)
    var out = []
    for (var i = 0; i < n; i++)
        out.push(labelAt(pane, i))
    return out
}

function count(pane) {
    return pane.tabs && pane.tabs.items && pane.tabs.items.length > 0 ? pane.tabs.items.length : 1
}

function currentIndex(pane) {
    return pane.tabs ? pane.tabs.index : 0
}

// Issue 93, nixfred: says whether it dropped a walk's results, which are not the directory's rows.
// One shared step for the search; see ui/js/Search.js leaveWalk.
// A Recent listing is dropped the same way; see ui/js/RecentMode.js dropOverlay.
function dropOverlay(pane) {
    var dropped = pane.searchMode === "results" || RecentMode.dropOverlay(pane)
    Search.leaveWalk(pane)
    Filter.close(pane)
    return dropped
}

function closePreview(pane) {
    if (pane.preview && pane.preview.active)
        pane.preview.close()
}

function busy(pane) {
    if (pane.listInFlight) {
        pane.message("A directory is already loading.", false)
        return true
    }
    return false
}

// Only ever called for a switch that re-listed nothing; the clamp is the belt on top of that, since
// an index past the end would select a row that is not there at all.
function restoreSelection(pane, selected, follows) {
    pane.clearSelection()
    if (!selected || selected.length === 0)
        return
    if (follows === true && selected.length === 1 && selected[0] < pane.total) {
        pane.selection.only(selected[0])
        pane.selectionVersion++
        return
    }
    var kept = 0
    for (var i = 0; i < selected.length; i++) {
        if (selected[i] < pane.total) {
            pane.selection.toggle(selected[i])
            kept++
        }
    }
    if (kept > 0)
        pane.selectionVersion++
}

function apply(pane, item, dropped) {
    // Issue 93: a search dropped onto the scope it walked leaves rows that are not that directory's.
    var same = pane.path === item.path && pane.showHidden === item.showHidden && dropped !== true
    var viewChanged = pane.viewMode !== item.viewMode
    pane.history = item.history.slice()
    pane.forwardHistory = (item.forwardHistory || []).slice()
    pane.viewMode = item.viewMode
    pane.showHidden = item.showHidden
    if (same) {
        if (pane.backend && (pane.backend.sortBy !== item.sortBy || pane.backend.sortDesc !== item.sortDesc)) {
            // Issue 94: the one reset a reorder takes, ui/js/Sort.js's, which this branch half repeated.
            Sort.resort(pane, item.sortBy, item.sortDesc)
            pane.tabs.pendingCursor = item.cursorIndex
            return
        }
        // The switch that re-reads nothing, unless something else did: the watch and a write both list.
        pane.setCursor(item.cursorIndex)
        if (pane.backend && item.listRequests === pane.backend.listRequests) {
            restoreSelection(pane, item.selected, item.follows)
            return
        }
        pane.clearSelection()
        return
    }
    pane.tabs.pendingCursor = item.cursorIndex
    pane.tabs.pendingSortBy = item.sortBy
    pane.tabs.pendingSortDesc = item.sortDesc
    // The tab's own dotfile answer is restored above, so the listing keeps it rather than taking the
    // standing preference. A tab in another view clears at once: these rows were never listed in that view.
    pane.openWithoutHistory(item.path, { keepHidden: true, clearAtOnce: viewChanged })
}

function applyPending(pane) {
    if (!pane.tabs)
        return
    var t = pane.tabs
    // Issue 91, nixfred: spent on the first reply either way, or an order already in force never was.
    if (t.pendingSortBy && t.pendingSortBy.length > 0 && pane.backend) {
        var by = t.pendingSortBy
        var desc = t.pendingSortDesc
        t.pendingSortBy = ""
        if (pane.backend.sortBy !== by || pane.backend.sortDesc !== desc) {
            pane.backend.sort(by, desc)
            pane.backend.sortBy = by
            pane.backend.sortDesc = desc
            pane.backend.window(0, pane.windowSize)
            return
        }
    }
    if (t.pendingCursor >= 0) {
        var last = pane.total > 0 ? pane.total - 1 : 0
        pane.setCursor(Math.min(t.pendingCursor, last))
        t.pendingCursor = -1
    }
}

function currentItems(pane, here) {
    if (pane.tabs && pane.tabs.items && pane.tabs.items.length > 0)
        return pane.tabs.items.slice()
    return [snapshot(pane, here)]
}

// A caller may name where the new tab lands, which is what the Places row menu's own row does;
// without one it is Settings, View, Opening that decides, and that still defaults to this folder.
function openNew(pane, where) {
    if (busy(pane))
        return
    // Before the preview and the search go: a refused tenth tab must cost the user nothing.
    if (count(pane) >= MAX) {
        pane.message("Nine tabs is the most.", false)
        return
    }
    var here = restingPath(pane)
    closePreview(pane)
    var dropped = dropOverlay(pane)
    // Settings > View > Opening decides where the new tab lands; it cloned the current folder before
    // 0.2.1 and that is still the default. The tab the operator leaves keeps the path it was on.
    var target = where || Startup.newTabPath(pane.uiState, here, pane.home)
    var items = currentItems(pane, here)
    var index = currentIndex(pane)
    items[index] = snapshot(pane, here)
    items.push(snapshot(pane, target))
    pane.tabs = pack(items, items.length - 1)
    // dropOverlay clears the search but leaves the pane on the scope it walked and its rows on that
    // walk's results, so a target equal to the scope still has to be listed again. Escape already does.
    if (pane.path !== target || dropped)
        pane.openWithoutHistory(target)
}

// Ctrl+Return on the cursor row, the keyboard twin of Tap.tappedTab's middle
// click: that directory in a new tab, leaving the cursor and selection alone.
function openCursorTab(pane) {
    var row = pane.rowFor ? pane.rowFor(pane.cursorIndex) : null
    if (!row || !row.d || typeof row.n !== "string") {
        pane.message("Only a folder opens in a new tab.", false)
        return
    }
    var base = pane.path
    openNew(pane, base === "/" ? "/" + row.n : base + "/" + row.n)
}

function selectAt(pane, i) {
    if (busy(pane))
        return
    var here = restingPath(pane)
    var items = currentItems(pane, here)
    if (i < 0 || i >= items.length) {
        pane.message("No tab " + (i + 1) + ".", false)
        return
    }
    var index = currentIndex(pane)
    if (i === index)
        return
    closePreview(pane)
    var dropped = dropOverlay(pane)
    items[index] = snapshot(pane, here)
    pane.tabs = pack(items, i)
    apply(pane, items[i], dropped)
}

function closeAt(pane, i) {
    if (busy(pane))
        return
    var items = currentItems(pane)
    if (items.length <= 1) {
        pane.message("Can't close the last tab.", false)
        return
    }
    if (i < 0 || i >= items.length) {
        pane.message("No tab " + (i + 1) + ".", false)
        return
    }
    var index = currentIndex(pane)
    items.splice(i, 1)
    var next = index
    if (i < index)
        next = index - 1
    else if (i === index)
        next = Math.min(i, items.length - 1)
    if (i === index) {
        closePreview(pane)
        var dropped = dropOverlay(pane)
        pane.tabs = pack(items, next)
        apply(pane, items[next], dropped)
    } else {
        pane.tabs = pack(items, next)
    }
}

function move(pane, from, to) {
    var items = currentItems(pane)
    if (items.length < 2)
        return
    var index = currentIndex(pane)
    items[index] = snapshot(pane, restingPath(pane))
    pane.tabs = pack(items, TabMove.reorder(items, from, to, index))
}

// Tabs040 callout 1: the { and } keys move the current tab one place. A reorder
// keeps the strip only: the pane stays on its path and lists nothing.
function moveCurrent(pane, delta) {
    var total = count(pane)
    if (total < 2)
        return
    var from = currentIndex(pane)
    move(pane, from, TabMove.step(from, delta, total))
}

function act(action, pane) {
    if (action === "tabMoveLeft" || action === "tabMoveRight") {
        moveCurrent(pane, action === "tabMoveRight" ? 1 : -1)
        return
    }
    if (action === "tabNext" || action === "tabPrevious") {
        var total = count(pane)
        var direction = action === "tabNext" ? 1 : -1
        selectAt(pane, (currentIndex(pane) + total + direction) % total)
        return
    }
    if (action === "tabNew") {
        openNew(pane)
        return
    }
    if (action === "tabClose") {
        closeAt(pane, currentIndex(pane))
        return
    }
    if (action.length === 4 && action.indexOf("tab") === 0 && action.charAt(3) >= "1" && action.charAt(3) <= "9")
        selectAt(pane, parseInt(action.charAt(3), 10) - 1)
}

// Tabs040 callout 2: with "Flea opens in" on Last folder the window reopens every tab in
// order. remembered() runs where lastPath is written and carries no new trigger; restorePlan()
// is the pure startup decision tests/js/tabrestore.js drives; restoreItems() shapes the plan
// into snapshots apply() can switch to. A folder that no longer exists is kept, because nothing
// here can stat a path: the listing's own error names it, the way startPath leaves a missing
// lastPath to that same error.
function remembered(pane) {
    var here = restingPath(pane)
    var items = pane.tabs && pane.tabs.items && pane.tabs.items.length > 0 ? pane.tabs.items : null
    if (!items)
        return { paths: [here], index: 0 }
    var index = currentIndex(pane)
    var out = []
    for (var i = 0; i < items.length; i++)
        out.push(i === index ? here : String((items[i] || {}).path || ""))
    return { paths: out, index: index }
}

// Null unless Last folder holds a remembered strip: Home and Chosen folder start exactly as
// startPath answers, a named path outranks the strip, and an old file without the key, an
// empty strip or one with nothing usable falls back to that same startPath answer.
function restorePlan(state, argvPath) {
    if (argvPath && String(argvPath).length > 0)
        return null
    var data = state || {}
    if ((data.startIn || "home") !== "last")
        return null
    var stored = data.lastTabs || null
    var kept = stored && Array.isArray(stored.paths) ? stored.paths : []
    var paths = []
    for (var i = 0; i < kept.length && paths.length < MAX; i++) {
        if (typeof kept[i] === "string" && kept[i].length > 0)
            paths.push(kept[i])
    }
    if (paths.length === 0)
        return null
    var index = stored && stored.index === Math.floor(stored.index) ? stored.index : 0
    if (index < 0 || index >= paths.length)
        index = Math.min(Math.max(index, 0), paths.length - 1)
    return { paths: paths, index: index }
}

// A restored tab starts exactly like a tab opened fresh at that folder: snapshot() is what
// openNew() records for its own new tab, so the standing view, sort and hidden preference all
// come from the pane rather than from literals here.
function restoreItems(pane, paths) {
    var out = []
    for (var i = 0; i < paths.length; i++)
        out.push(snapshot(pane, String(paths[i])))
    return out
}
