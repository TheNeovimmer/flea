.import "../../ui/js/Startup.js" as Startup
.import "../../ui/js/FavGuard.js" as FavGuard

// Settings > View > Opening, which decides where a window opens and where a new tab opens. Before
// 0.2.1 a window always opened on $HOME unless the command line named a path, and a new tab always
// cloned the folder the pane rested on; both are still the defaults, and both are settings now.

var HOME = "/home/gm"

function run(check) {
    // The shipped defaults, which are also what a ui.json holding none of these keys reads as.
    check("a fresh install opens in home", Startup.startPath({}, HOME, ""), HOME)
    check("and no state at all still opens in home", Startup.startPath(null, HOME, ""), HOME)
    check("a fresh install opens a new tab where the pane already is",
          Startup.newTabPath({}, "/home/gm/Pictures", HOME), "/home/gm/Pictures")

    // A path the caller named outranks every setting, the precedence --select already has.
    var chosen = { startIn: "folder", startFolder: "/home/gm/Work" }
    check("a path named on the command line wins over the chosen folder",
          Startup.startPath(chosen, HOME, "/tmp/asked"), "/tmp/asked")
    check("and over home", Startup.startPath({}, HOME, "/tmp/asked"), "/tmp/asked")
    check("the chosen folder opens when nothing was named",
          Startup.startPath(chosen, HOME, ""), "/home/gm/Work")

    // "Last folder" reads the path ui/WindowBody.qml records as the pane moves.
    var last = { startIn: "last", lastPath: "/home/gm/Pictures/2026" }
    check("last folder opens where the pane was left", Startup.startPath(last, HOME, ""), "/home/gm/Pictures/2026")

    // A mode with nothing behind it falls back to home rather than to "", which would be no path at
    // all: a first run with "Last folder" already selected has recorded nothing yet.
    check("last folder with nothing recorded falls back to home",
          Startup.startPath({ startIn: "last" }, HOME, ""), HOME)
    check("a chosen folder that was never chosen falls back to home",
          Startup.startPath({ startIn: "folder", startFolder: "" }, HOME, ""), HOME)
    check("a mode this build does not know falls back to home",
          Startup.startPath({ startIn: "fromANewerFlea" }, HOME, ""), HOME)

    // Where a new tab lands, which is its own setting and not the window's.
    var here = "/home/gm/Downloads"
    check("a new tab can open in home instead", Startup.newTabPath({ newTab: "home" }, here, HOME), HOME)
    check("a new tab can open where the window would",
          Startup.newTabPath({ newTab: "start", startIn: "folder", startFolder: "/srv" }, here, HOME), "/srv")
    check("and the start mode it follows is resolved, not copied",
          Startup.newTabPath({ newTab: "start", startIn: "last", lastPath: "/mnt/vault" }, here, HOME), "/mnt/vault")
    check("a start mode with nothing behind it still lands a new tab on home",
          Startup.newTabPath({ newTab: "start", startIn: "folder" }, here, HOME), HOME)
    check("a tab mode this build does not know clones the current folder",
          Startup.newTabPath({ newTab: "fromANewerFlea" }, here, HOME), here)

    // The command line names the window, never a tab opened later inside it.
    check("a new tab never inherits the path the window was asked for",
          Startup.newTabPath({ newTab: "start" }, here, HOME), HOME)

    // ui.json is a file the operator can edit. src/uistate.rs Rule::Place is the trust boundary and
    // refuses anything but a place or "", so what reaches here is a string or an absent key.
    check("a null recorded path falls back to home",
          Startup.startPath({ startIn: "last", lastPath: null }, HOME, ""), HOME)

    // A saved dual view and a command-line folder: the focused side takes the folder and the other keeps its own.
    var pair = function(dual, start, named) {
        var answer = Startup.dualPaths(dual, start, named)
        return answer.paths.join(" | ") + " @" + answer.launchSide
    }
    var saved = { paths: ["/home/gm/Music", "/home/gm/Work"], focus: 0 }
    check("with nothing named a saved pair opens as it was left",
          pair(saved, HOME, ""), "/home/gm/Music | /home/gm/Work @-1")
    check("a named folder goes to the left side when it had focus",
          pair(saved, "/tmp/asked", "/tmp/asked"), "/tmp/asked | /home/gm/Work @0")
    check("a start folder the named one did not come from is left behind, not launched",
          pair(saved, "/home/gm/Pictures", "/tmp/asked"), "/tmp/asked | /home/gm/Work @0")
    check("and to the right side when it had focus",
          pair({ paths: saved.paths, focus: 1 }, "/tmp/asked", "/tmp/asked"), "/home/gm/Music | /tmp/asked @1")
    check("a start folder is left behind on the right side too",
          pair({ paths: saved.paths, focus: 1 }, "/home/gm/Pictures", "/tmp/asked"), "/home/gm/Music | /tmp/asked @1")
    check("a pair saved with no focus recorded gives the named folder to the left side",
          pair({ paths: saved.paths }, "/tmp/asked", "/tmp/asked"), "/tmp/asked | /home/gm/Work @0")
    check("with no saved pair both sides start where one pane would",
          pair({}, "/home/gm/Pictures", ""), "/home/gm/Pictures | /home/gm/Pictures @-1")
    // start differs from the named folder here, as it does when the second pane loads before the first has opened.
    check("and a named folder with no saved pair opens on both sides, the left side's",
          pair(null, "/home/gm/Pictures", "/tmp/asked"), "/tmp/asked | /tmp/asked @0")
    check("a saved pair of the wrong length is no pair",
          pair({ paths: ["/home/gm/Music"], focus: 1 }, "/home/gm/Pictures", "/tmp/asked"), "/tmp/asked | /tmp/asked @0")

    // Defect 26: restoring the last folder has a listing deadline past which Home stays reachable.
    check("the restore waits this long for its listing", Startup.LISTING_WAIT_MS, 10000)
    check("a landed listing is ready whatever the clock says", Startup.listingStateFor(true, 0), "ready")
    check("a listing still out inside the wait is loading", Startup.listingStateFor(false, 9999), "loading")
    check("a listing still out at the wait is not responding", Startup.listingStateFor(false, 10000), "waiting")
    check("a listing still out past the wait stays waiting", Startup.listingStateFor(false, 60000), "waiting")

    // Defect 25: the favourite inspector always clears its guard, a dead mount included.
    check("the inspector waits this long for its answer", FavGuard.INSPECT_WAIT_MS, 10000)
    check("an answer inside the wait keeps the guard honest", FavGuard.expired(0, 9999), false)
    check("no answer at the wait clears the guard", FavGuard.expired(0, 10000), true)
    check("no answer past the wait stays cleared", FavGuard.expired(5000, 60000), true)
}
