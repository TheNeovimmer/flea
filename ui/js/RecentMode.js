.pragma library

.import "DirSizes.js" as DirSizes
.import "Nav.js" as Nav
.import "Thumbs.js" as Thumbs

// Recent lists the history's paths under "/", newest first via mtime desc.
var OFF = ""
var RESULTS = "results"

// One refusal for both paste routes: the menu reaches past key dispatch, so it shares this.
function refusePaste(pane) {
    if (pane.recentMode.length > 0) {
        pane.message("This listing is a history, and cannot take a paste.", false)
        return true
    }
    return false
}

// Opening the rail row: the pane keeps where it stood, moves to the history's base, and asks
// for its paths, after the jump's own bounded read. No fsinfo is asked: a history spans mounts,
// so the bar beside the counts reads unknown the way the board draws it.
function run(pane, paths) {
    if (pane.listInFlight) {
        pane.message("A directory is already loading.", false)
        return
    }
    // The standing order is kept for the way back, not the mtime it replaces.
    if (pane.recentMode.length === 0 && pane.backend) {
        pane.recentSortBy = pane.backend.sortBy
        pane.recentSortDesc = pane.backend.sortDesc === true
    }
    if (pane.recentFrom.length === 0) {
        pane.recentFrom = pane.path
    }
    // A history replaces the standing listing, so a walk is cancelled first.
    if (pane.searchRunning) {
        pane.backend.searchcancel()
    }
    pane.searchMode = ""
    pane.searchQuery = ""
    pane.searchRunning = false
    pane.searchCancelled = false
    pane.searchFrom = ""
    pane.searchScanned = 0
    // The paths this listing stands on, so a refresh with the rail hidden still re-asks them.
    pane.recentPaths = paths || []
    pane.listInFlight = true
    pane.listedSeen = false
    pane.path = "/"
    pane.recentMode = RESULTS
    pane.listingPath = "/"
    pane.storageClass = ""
    pane.fsName = ""
    pane.fsFree = 0
    var ask = {}
    if (!pane.swap.hold(ask)) {
        Nav.forget(pane)
    }
    pane.appliedListingPreferences = pane.listingPreferences
    pane.backend.listPaths(pane.recentPaths, pane.windowSize)
    pane.backend.sortBy = "mtime"
    pane.backend.sortDesc = true
}

// Leaving Recent re-lists the folder it was opened over, pushing no history entry.
function close(pane) {
    if (pane.listInFlight) {
        pane.message("A directory is already loading.", false)
        return
    }
    var back = pane.recentFrom.length > 0 ? pane.recentFrom : "/"
    pane.recentMode = OFF
    pane.recentFrom = ""
    pane.recentPaths = []
    restoreSort(pane)
    pane.openWithoutHistory(back)
}

// The order run() replaced, handed back before the folder re-lists.
function restoreSort(pane) {
    if (pane.backend && typeof pane.recentSortBy === "string" && pane.recentSortBy.length > 0) {
        pane.backend.sortBy = pane.recentSortBy
        pane.backend.sortDesc = pane.recentSortDesc === true
    }
    pane.recentSortBy = ""
    pane.recentSortDesc = false
}

// A plain hop leaves Recent through one step, so every navigation restores the same order.
function leave(pane) {
    if (pane.recentMode.length > 0) {
        restoreSort(pane)
    }
    pane.recentMode = OFF
    pane.recentFrom = ""
    pane.recentPaths = []
}

// An operation changed a file under the listing, so the history is read again rather than the
// base re-listed: re-listing "/" would draw the root over the place just left, and the backend
// drops whatever the operation took, so the rows that return are the ones still there. With the
// rail hidden the sidebar is unloaded, so the paths this listing stands on are asked again.
function refresh(pane, selectPath) {
    pane.pendingSelect = selectPath ? selectPath : ""
    pane.pendingMenu = false
    if (pane.sidebar) {
        pane.sidebar.readRecent(pane)
        return
    }
    run(pane, pane.recentPaths || [])
}

// The folder a tab records on a history, "" elsewhere, so it lands where it stood.
function restingPath(pane) {
    return pane.recentMode === RESULTS && pane.recentFrom.length > 0 ? pane.recentFrom : ""
}

// A tab switch drops the mode and says whether it dropped one.
function dropOverlay(pane) {
    if (pane.recentMode.length === 0) {
        return false
    }
    pane.recentMode = OFF
    pane.recentFrom = ""
    pane.recentPaths = []
    restoreSort(pane)
    return true
}

// o opens the row's own folder; Enter opens the file itself, so the two cannot disagree.
function reveal(pane) {
    if (pane.listInFlight) {
        pane.message("A directory is already loading.", false)
        return
    }
    var row = pane.rowFor(pane.cursorIndex)
    if (!row) {
        return
    }
    var full = pane.join(pane.path, row.n)
    var cut = full.lastIndexOf("/")
    if (cut < 0) {
        return
    }
    var dir = cut === 0 ? "/" : full.substring(0, cut)
    pane.recentMode = OFF
    pane.recentFrom = ""
    pane.recentPaths = []
    restoreSort(pane)
    pane.pendingSelect = full
    pane.openWithoutHistory(dir)
}
