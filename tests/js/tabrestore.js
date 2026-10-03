.import "tabsfixture.js" as Fixture
.import "../../ui/js/Tabs.js" as Tabs

// Tabs040 callout 2: with "Flea opens in" on Last folder the window reopens every tab in
// order at its folder. restorePlan() is the pure startup decision, remembered() what a path
// change writes, restoreItems() the shape a plan takes back. Nothing here can stat a path,
// so a folder that no longer exists stays in the plan and the listing's own error names it.

function planOf(paths, index) {
    return { startIn: "last", lastTabs: { paths: paths, index: index } }
}

function run(check) {
    var plan = Tabs.restorePlan(planOf(["/a", "/b", "/c"], 1), "")
    check("several tabs reopen in order", plan.paths.join(","), "/a,/b,/c")
    check("with the remembered tab current", plan.index, 1)

    check("Home starts without a plan", Tabs.restorePlan({ startIn: "home" }, ""), null)
    check("and so does Chosen folder",
          Tabs.restorePlan({ startIn: "folder", startFolder: "/a" }, ""), null)
    check("a path named on the command line outranks the strip",
          Tabs.restorePlan(planOf(["/a", "/b"], 1), "/tmp/asked"), null)

    // A folder deleted since it was remembered is kept: the listing's error is what names it,
    // the way startPath leaves a missing lastPath to that same error.
    var gone = Tabs.restorePlan(planOf(["/gone", "/b"], 0), "")
    check("a missing folder stays in the plan", gone.paths.join(","), "/gone,/b")
    check("an empty strip falls back to the single start", Tabs.restorePlan(planOf([], 0), ""), null)
    check("and so does an old file holding only lastPath",
          Tabs.restorePlan({ startIn: "last", lastPath: "/a" }, ""), null)

    // Past the nine-tab cap the front of the strip survives and the index clamps into it.
    var many = []
    for (var n = 0; n < 11; n++)
        many.push("/t" + n)
    var capped = Tabs.restorePlan(planOf(many, 10), "")
    check("past the cap nine tabs reopen", capped.paths.length, 9)
    check("in the order they were remembered", capped.paths.join(","), many.slice(0, 9).join(","))
    check("with the index clamped to the last survivor", capped.index, 8)
    check("a negative index clamps to the first", Tabs.restorePlan(planOf(["/a", "/b"], -1), "").index, 0)
    check("and a non-number reads as the first", Tabs.restorePlan(planOf(["/a", "/b"], "1"), "").index, 0)
    check("while a non-string entry voids the whole strip",
          Tabs.restorePlan({ startIn: "last", lastTabs: { paths: ["/a", 7], index: 0 } }, ""), null)

    // A restored tab starts exactly like a tab opened fresh at that folder: restoreItems()
    // goes through the same snapshot() openNew() records, so the standing view, sort and hidden
    // preference come from the pane rather than from literals.
    var fresh = Fixture.pane("/here")
    fresh.viewMode = "grid"
    fresh.showHidden = true
    fresh.history = ["/home/gm"]
    fresh.cursorIndex = 7
    fresh.backend.sortBy = "size"
    fresh.backend.sortDesc = true
    var restored = Tabs.restoreItems(fresh, ["/here"])
    Tabs.openNew(fresh)
    var stateOnly = function (key, value) { return key === "tabIdentity" ? undefined : value }
    check("restored and fresh tabs have distinct identities", restored[0].tabIdentity !== fresh.tabs.items[1].tabIdentity, true)
    check("a restored snapshot equals a freshly opened tab's state",
          JSON.stringify(restored[0], stateOnly), JSON.stringify(fresh.tabs.items[1], stateOnly))
    check("and the fresh tab is the new current one", Tabs.currentIndex(fresh), 1)

    // A restored tab lists its folder on first visit, like any background tab's first visit.
    var pane = Fixture.pane("/a")
    pane.tabs = Tabs.pack(Tabs.restoreItems(pane, ["/a", "/b"]), 0)
    Tabs.selectAt(pane, 1)
    check("a restored tab lists its folder on first visit", pane.listed.join(","), "/b")
    check("and becomes current", Tabs.currentIndex(pane), 1)

    // The write taken before landing names the folder being opened, not the one left.
    var lag = Fixture.pane("/a")
    lag.listInFlight = false
    lag.listingPath = ""
    lag.dropPath = "/a"
    lag.openWithoutHistory = function (next) { lag.listInFlight = true; lag.listingPath = next; lag.dropPath = next; lag.listed.push(next) }
    lag.land = function () { lag.path = lag.listingPath; lag.dropPath = lag.path; lag.listInFlight = false; lag.listingPath = "" }
    lag.tabs = Tabs.pack(Tabs.restoreItems(lag, ["/a", "/b"]), 0)
    Tabs.selectAt(lag, 1)
    check("a switch before landing already names the folder being opened",
          JSON.stringify(Tabs.remembered(lag)),
          JSON.stringify({ paths: ["/a", "/b"], index: 1 }))
    lag.land()
    check("and after landing it still does",
          JSON.stringify(Tabs.remembered(lag)),
          JSON.stringify({ paths: ["/a", "/b"], index: 1 }))

    // What a strip change writes: open, switch and move all reassign pane.tabs, which is the
    // signal ui/WindowBody.qml hooks for its own write, so the stored order never goes stale.
    var strip = Fixture.pane("/a")
    strip.tabs = Tabs.pack(Tabs.restoreItems(strip, ["/a", "/b"]), 0)
    Tabs.act("tabNext", strip)
    check("a switch is remembered with its new current tab",
          JSON.stringify(Tabs.remembered(strip)),
          JSON.stringify({ paths: ["/a", "/b"], index: 1 }))
    // The strip a switch writes once the pane has moved: the new tab's own path at the new
    // index, never the previous tab's path (ui/WindowBody.qml defers the write past the move,
    // because pane.tabs is reassigned before apply() moves the pane).
    var nested = Fixture.pane("/tabs/alpha")
    nested.tabs = Tabs.pack(Tabs.restoreItems(nested, ["/tabs", "/tabs/alpha"]), 1)
    Tabs.selectAt(nested, 0)
    check("a switch records the new tab's own path once the pane has moved",
          JSON.stringify(Tabs.remembered(nested)),
          JSON.stringify({ paths: ["/tabs", "/tabs/alpha"], index: 0 }))
    Tabs.act("tabNew", strip)
    check("an opened tab joins the remembered strip",
          JSON.stringify(Tabs.remembered(strip)),
          JSON.stringify({ paths: ["/a", "/b", "/b"], index: 2 }))
    Tabs.moveCurrent(strip, -1)
    check("a reorder is remembered in its new order",
          JSON.stringify(Tabs.remembered(strip)),
          JSON.stringify({ paths: ["/a", "/b", "/b"], index: 1 }))

    // What a path change writes, through the same moments lastPath is written.
    var single = Fixture.pane("/x")
    check("a pane with no tabs remembers its one folder", JSON.stringify(Tabs.remembered(single)),
          JSON.stringify({ paths: ["/x"], index: 0 }))
    var multi = Fixture.pane("/two-moved")
    multi.tabs = { items: [{ path: "/one" }, { path: "/two" }], index: 1,
                   pendingCursor: -1, pendingSortBy: "", pendingSortDesc: false }
    check("the current tab is remembered live, not as its stale snapshot",
          JSON.stringify(Tabs.remembered(multi)),
          JSON.stringify({ paths: ["/one", "/two-moved"], index: 1 }))
    var searching = Fixture.pane("/")
    searching.searchMode = "results"
    searching.searchFrom = "/home/gm/Work"
    check("a tab left in search results remembers where the user was",
          JSON.stringify(Tabs.remembered(searching)),
          JSON.stringify({ paths: ["/home/gm/Work"], index: 0 }))
}
