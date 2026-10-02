.import "../../ui/js/RecentMode.js" as RecentMode
.import "sourcefixture.js" as Source

// The main window's Recent place. ui/Pane.qml holds the mode, this holds what it does.

function pane(path) {
    var p = {
        path: path || "/home/gm/Work",
        recentMode: "",
        recentFrom: "",
        recentPaths: [],
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
    p.openWithoutHistory = function (next) { p.opened.push(next); p.path = next }
    return p
}

function run(check) {
    // Opening the rail row moves to the history's base and asks for its paths, after the
    // jump's own bounded read; the folder it was opened over is kept for the way back.
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

    // A history replaces whatever the pane was showing: a running walk is cancelled and its
    // mode cleared, so no header outlives its rows.
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

    // An operation under the listing re-reads the history through the rail rather than
    // re-listing the base, which would draw the root over the place just left.
    var changed = pane("/home/gm/Work")
    RecentMode.run(changed, ["/home/gm/a.txt"])
    changed.listInFlight = false
    var reread = 0
    changed.sidebar = { readRecent: function () { reread += 1 } }
    RecentMode.refresh(changed, "/home/gm/a.txt")
    check("a refresh re-reads the history", reread, 1)
    check("and holds the operated row for the rows that return", changed.pendingSelect, "/home/gm/a.txt")

    // With the rail hidden the sidebar is unloaded, so the paths the listing stands on are asked again.
    var hidden = pane("/home/gm/Work")
    RecentMode.run(hidden, ["/home/gm/a.txt"])
    hidden.listInFlight = false
    hidden.sidebar = null
    RecentMode.refresh(hidden, "")
    check("a refresh with no rail re-asks the standing paths", hidden.listed.join(","), "/home/gm/a.txt|200,/home/gm/a.txt|200")

    // o opens the directory that holds the cursor row and puts the cursor on it.
    var revealing = pane("/home/gm/Work")
    RecentMode.run(revealing, ["/home/gm/Docs/a.txt"])
    revealing.listInFlight = false
    revealing.rows = [{ n: "home/gm/Docs/a.txt", d: false }]
    revealing.cursorIndex = 0
    RecentMode.reveal(revealing)
    check("reveal opens the row's own folder", revealing.opened.join(","), "/home/gm/Docs")
    check("selecting the row it came from", revealing.pendingSelect, "/home/gm/Docs/a.txt")
    check("and the mode is off", revealing.recentMode, "")

    // A tab switch drops the overlay so the snapshot keeps the folder order.
    var switching = pane("/home/gm/Work")
    switching.backend.sortBy = "kind"
    switching.backend.sortDesc = true
    RecentMode.run(switching, ["/home/gm/a.txt"])
    check("dropping the overlay hands the standing order back",
          RecentMode.dropOverlay(switching) + "|" + switching.backend.sortBy + "|" + switching.backend.sortDesc,
          "true|kind|true")

    // The sort run() stashes lives on the real pane, so a stub object cannot hide a missing declaration.
    var paneSource = Source.source("ui/Pane.qml")
    check("Pane.qml declares recentSortBy", paneSource.indexOf("property string recentSortBy") >= 0, true)
    check("Pane.qml declares recentSortDesc", paneSource.indexOf("property bool recentSortDesc") >= 0, true)

    // The menu reaches past key dispatch, so one helper refuses a paste in Recent for both routes.
    var pasteBranch = Source.slice(paneSource, "function pasteLink(kind, paths)", "function setCursor(index, context)")
    check("Pane.pasteLink shares the refusal", pasteBranch.indexOf("RecentMode.refusePaste") >= 0, true)
    check("Focus.act shares the refusal", Source.source("ui/js/Focus.js").indexOf("RecentMode.refusePaste") >= 0, true)
    check("the helper stands for both routes", typeof RecentMode.refusePaste, "function")
    if (typeof RecentMode.refusePaste === "function") {
        var history = { recentMode: "results", said: "" }
        history.message = function (text) { history.said = text }
        check("it refuses in Recent", RecentMode.refusePaste(history), true)
        check("and says why", history.said, "This listing is a history, and cannot take a paste.")
        var browsing = { recentMode: "", said: "" }
        browsing.message = function (text) { browsing.said = text }
        check("and stays silent off Recent", RecentMode.refusePaste(browsing), false)
    } else {
        check("it refuses in Recent", "missing", true)
        check("and says why", "missing", "This listing is a history, and cannot take a paste.")
        check("and stays silent off Recent", "missing", false)
    }
}
