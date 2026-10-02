.import "../../ui/js/RecentMode.js" as RecentMode
.import "sourcefixture.js" as Source

// The main window's Recent place. ui/Pane.qml holds the mode, this holds what it does.

function pane(path) {
    var p = {
        path: path || "/home/gm/Work",
        recentMode: "",
        recentFrom: "",
        recentPaths: [],
        recentSortBy: "",
        recentSortDesc: false,
        listInFlight: false,
        listedSeen: false,
        listingPath: "",
        storageClass: "local",
        fsName: "btrfs",
        fsFree: 42,
        listingPreferences: "prefs",
        appliedListingPreferences: "",
        windowSize: 200,
        said: [],
        listed: [],
        opened: []
    }
    p.message = function (text) { p.said.push(text) }
    p.join = function (base, name) { return base === "/" ? "/" + name : base + "/" + name }
    p.rowFor = function (index) { return p.rows[index - p.held] || null }
    p.held = 0
    p.rows = []
    p.holds = []
    p.total = 0
    p.kindNames = []
    p.cursorIndex = 0
    p.viewMode = "list"
    p.searchMode = ""
    p.searchQuery = ""
    p.searchRunning = false
    p.searchCancelled = false
    p.searchFrom = ""
    p.searchScanned = 0
    p.cancelled = []
    p.swap = { hold: function (ask) { p.holds.push("hold"); return false } }
    p.backend = {
        sortBy: "name",
        sortDesc: false,
        listPaths: function (paths, first) { p.listed.push(paths.join(",") + "|" + first) },
        searchcancel: function () { p.cancelled.push("search") }
    }
    // Nav.forget's own members, spelled the way ui/js/Nav.js writes them.
    p.clearSelection = function () {}
    p.listArea = { primeSettle: function () {} }
    p.thumbState = {}
    p.dirSizeState = {}
    // Mirrors ui/Pane.qml openWithoutHistory: every navigation leaves Recent.
    p.openWithoutHistory = function (next) {
        p.recentMode = ""
        p.recentFrom = ""
        p.recentPaths = []
        RecentMode.restoreSort(p)
        p.opened.push(next)
        p.path = next
    }
    // Mirrors ui/Pane.qml restoreRecentSort, which ui/js/Search.js reaches through the pane.
    p.restoreRecentSort = function () { RecentMode.restoreSort(p) }
    return p
}

function run(check) {
    // The pane declares the sort Recent hands back, so run writes a member Qt accepts.
    var declared = Source.source("ui/Pane.qml")
    check("the pane declares the sort Recent hands back",
        declared.indexOf("property string recentSortBy") >= 0, true)
    check("and whether that sort descended",
        declared.indexOf("property bool recentSortDesc") >= 0, true)
    // Opening the rail row moves to the history's base and keeps where it stood.
    var standing = pane("/home/gm/Work")
    RecentMode.run(standing, ["/home/gm/a.txt", "/home/gm/b.txt"])
    check("opening Recent moves to the history's base", standing.path, "/")
    check("and keeps where it stood", standing.recentFrom, "/home/gm/Work")
    check("and the mode stands", standing.recentMode, "results")
    check("and the base is asked for those paths", standing.listed.join(","), "/home/gm/a.txt,/home/gm/b.txt|200")
    check("and the disk beside the counts is unknown", standing.fsName + "|" + standing.fsFree, "|0")
    check("and Used describes the history's own newest-first order", standing.backend.sortBy + "|" + standing.backend.sortDesc, "mtime|true")

    // A second open while one lands replaces nothing and says so, the way a navigation does.
    RecentMode.run(standing, ["/home/gm/c.txt"])
    check("an open while one lands is refused", standing.said.join(","), "A directory is already loading.")
    check("and keeps the first open's paths", standing.listed.length, 1)

    // A history replaces the standing listing, so a running walk is cancelled.
    var walking = pane("/home/gm/Work")
    walking.searchMode = "results"
    walking.searchRunning = true
    walking.viewMode = "grid"
    RecentMode.run(walking, ["/home/gm/a.txt"])
    check("a walk is cancelled before the history answers", walking.cancelled.join(","), "search")
    check("and its mode is cleared", walking.searchMode + "|" + walking.searchRunning, "|false")

    // Leaving Recent re-lists the folder it was opened over, pushing no history entry.
    standing.listInFlight = false
    RecentMode.close(standing)
    check("leaving Recent hands back the folder it was opened over", standing.opened.join(","), "/home/gm/Work")
    check("and the mode is off", standing.recentMode + "|" + standing.recentFrom, "|")
    check("and the newest-first order does not follow it out",
          standing.backend.sortBy + "|" + standing.backend.sortDesc, "name|false")

    // A refresh re-reads the history rather than re-listing the base.
    var changed = pane("/home/gm/Work")
    RecentMode.run(changed, ["/home/gm/a.txt"])
    changed.listInFlight = false
    var reread = 0
    var rereadPane = null
    changed.sidebar = { readRecent: function (asker) { reread += 1; rereadPane = asker || null } }
    RecentMode.refresh(changed, "/home/gm/a.txt")
    check("a refresh re-reads the history", reread, 1)
    check("and holds the operated row for the rows that return", changed.pendingSelect, "/home/gm/a.txt")
    check("and names the asking pane", rereadPane === changed, true)
    check("and lists nothing itself", changed.listed.length, 1)

    // With the rail hidden the sidebar is unloaded, so the paths the listing stands on are asked again.
    var hidden = pane("/home/gm/Work")
    RecentMode.run(hidden, ["/home/gm/a.txt"])
    hidden.listInFlight = false
    hidden.sidebar = null
    RecentMode.refresh(hidden, "")
    check("a refresh with no rail re-asks the standing paths", hidden.listed.join(","), "/home/gm/a.txt|200,/home/gm/a.txt|200")

    // A held open keeps its rows, an unheld one clears them for the listing behind it.
    var held = pane("/home/gm/Work")
    held.rows = [{ n: "home/gm/a.txt", d: false }]
    held.swap = { hold: function () { held.holds.push("hold"); return true } }
    RecentMode.run(held, ["/home/gm/a.txt"])
    check("a held open keeps its rows", held.rows.length, 1)
    var unheld = pane("/home/gm/Work")
    unheld.rows = [{ n: "home/gm/a.txt", d: false }]
    RecentMode.run(unheld, ["/home/gm/a.txt"])
    check("an unheld open clears its rows", unheld.rows.length, 0)
    // o opens the directory that holds the cursor row and puts the cursor on it.
    var revealing = pane("/home/gm/Work")
    revealing.backend.sortBy = "kind"
    revealing.backend.sortDesc = true
    RecentMode.run(revealing, ["/home/gm/Docs/a.txt"])
    revealing.listInFlight = false
    revealing.rows = [{ n: "home/gm/Docs/a.txt", d: false }]
    revealing.cursorIndex = 0
    RecentMode.reveal(revealing)
    check("reveal opens the row's own folder", revealing.opened.join(","), "/home/gm/Docs")
    check("selecting the row it came from", revealing.pendingSelect, "/home/gm/Docs/a.txt")
    check("and the mode is off", revealing.recentMode, "")
    check("and hands the standing order back", revealing.backend.sortBy + "|" + revealing.backend.sortDesc, "kind|true")
    // A root-level file reveals the root itself rather than going silent.
    var rootRow = pane("/home/gm/Work")
    RecentMode.run(rootRow, ["/a.txt"])
    rootRow.listInFlight = false
    rootRow.rows = [{ n: "a.txt", d: false }]
    rootRow.cursorIndex = 0
    RecentMode.reveal(rootRow)
    check("a root-level row reveals the root", rootRow.opened.join(","), "/")
    // A reveal while a listing lands refuses before it clears the way back.
    var busy = pane("/home/gm/Work")
    RecentMode.run(busy, ["/home/gm/a.txt"])
    busy.rows = [{ n: "home/gm/a.txt", d: false }]
    RecentMode.reveal(busy)
    check("a reveal while one lands is refused", busy.said.join(","), "A directory is already loading.")
    check("and keeps the mode, the way back, and opens nothing",
          busy.recentMode + "|" + busy.recentFrom + "|" + busy.opened.length, "results|/home/gm/Work|0")
    // Escape while a listing lands refuses before it clears the way back.
    var loading = pane("/home/gm/Work")
    RecentMode.run(loading, ["/home/gm/a.txt"])
    loading.opened = []
    RecentMode.close(loading)
    check("a close while one lands is refused", loading.said.join(","), "A directory is already loading.")
    check("and keeps the way back", loading.recentFrom, "/home/gm/Work")
    check("and opens nothing", loading.opened.length, 0)

    // A tab switch drops the overlay the way close does, keeping the folder's order.
    var switching = pane("/home/gm/Work")
    switching.backend.sortBy = "kind"
    switching.backend.sortDesc = true
    RecentMode.run(switching, ["/home/gm/a.txt"])
    check("dropping the overlay hands the standing order back",
          RecentMode.dropOverlay(switching) + "|" + switching.backend.sortBy + "|" + switching.backend.sortDesc,
          "true|kind|true")

    // A hop out of Recent without close still hands the standing order back.
    var hopping = pane("/home/gm/Work")
    hopping.backend.sortBy = "kind"
    hopping.backend.sortDesc = true
    RecentMode.run(hopping, ["/home/gm/a.txt"])
    hopping.listInFlight = false
    hopping.openWithoutHistory("/home/gm/Elsewhere")
    check("a hop out of Recent restores the standing order through the mirror",
          hopping.backend.sortBy + "|" + hopping.backend.sortDesc, "kind|true")
    check("and the mode is off after the hop", hopping.recentMode, "")
    check("and lands where the hop asked", hopping.opened.join(","), "/home/gm/Elsewhere")
    // A walk started from Recent restores through the pane, and every navigation restores direct.
    var searchSrc = Source.source("ui/js/Search.js")
    check("a walk started from Recent hands the standing order back",
          searchSrc.indexOf("root.restoreRecentSort()") >= 0, true)
    check("and the pane answers that call inside restoreRecentSort",
          Source.slice(declared, "function restoreRecentSort()", "function openRecent(").indexOf("RecentMode.restoreSort(root)") >= 0, true)
    check("and every navigation restores direct inside openWithoutHistory",
          Source.slice(declared, "function openWithoutHistory(", "if (!root.listInFlight)").indexOf("RecentMode.restoreSort(root)") >= 0, true)
}
