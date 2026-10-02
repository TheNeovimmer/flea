.pragma library

.import "DirSizes.js" as DirSizes
.import "Nav.js" as Nav
.import "Thumbs.js" as Thumbs

// The main window's Recent place, beside ui/js/Search.js's walk:
// "" off, "results" once the history answered. The listing is built with listpaths, the same
// request the picker's Recent location already uses, so the backend stats each path and drops
// the ones that are gone, and the order the history gave is the order kept, newest first. The
// pane's own path is "/", the base listpaths answers under, so join and every per-row facility
// keep working untouched; the breadcrumb says Recent and the disk reads unknown, because one
// history spans mounts and names no filesystem of its own.

// The Used mark describes the history's own newest-first order, and the recorded backend order
// is its nearest backend order: the history's visited stamps track modification closely enough
// that no row visibly contradicts it, and the first click on either mark sends a real sort.
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
    // The newest-first order is kept for the way back, so leaving restores it.
    if (pane.recentMode.length === 0 && pane.backend) {
        pane.recentSortBy = pane.backend.sortBy
        pane.recentSortDesc = pane.backend.sortDesc === true
    }
    if (pane.recentFrom.length === 0) {
        pane.recentFrom = pane.path
    }
    // A history replaces whatever the pane was showing, the way a navigation does: a walk
    // left standing would keep its own header, mode and rows over this listing.
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

// Leaving Recent re-lists the folder it was opened over, which is not the base it stands on:
// a history is not a navigation, so no history entry is pushed, the way a search leaves none.
function close(pane) {
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
        pane.sidebar.readRecent()
        return
    }
    run(pane, pane.recentPaths || [])
}

// The folder a tab records for a pane standing on its history, "" for every other pane, so the
// tab lands on the folder Recent was opened over and never on the base it stands on.
function restingPath(pane) {
    return pane.recentMode === RESULTS && pane.recentFrom.length > 0 ? pane.recentFrom : ""
}

// A tab switch drops the mode the way it drops a walk's results, and says whether it dropped one,
// so a target equal to the standing base still re-lists instead of keeping the history's rows.
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

// o on a recent row opens the directory that holds it and puts the cursor on the row, the same
// reveal a search result answers; Enter opens the file itself, so the two keys cannot disagree.
function reveal(pane) {
    var row = pane.rowFor(pane.cursorIndex)
    if (!row) {
        return
    }
    var full = pane.join(pane.path, row.n)
    var cut = full.lastIndexOf("/")
    if (cut <= 0) {
        return
    }
    pane.recentMode = OFF
    pane.recentFrom = ""
    pane.pendingSelect = full
    pane.openWithoutHistory(full.substring(0, cut))
}
