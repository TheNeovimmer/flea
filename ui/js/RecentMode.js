.pragma library

.import "DirSizes.js" as DirSizes
.import "Nav.js" as Nav
.import "Thumbs.js" as Thumbs

// Recent lists the history's paths under "/", newest first via mtime desc.
var OFF = ""
var RESULTS = "results"

// Opening the rail row keeps where it stood and asks for the history's paths.
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

// A refresh re-reads the history, so the rows that return are the ones still there.
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
