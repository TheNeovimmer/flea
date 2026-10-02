.import "tabsfixture.js" as Fixture
.import "../../ui/js/TabMove.js" as TabMove
.import "../../ui/js/Tabs.js" as Tabs

// Tabs040 callout 1: tabs reorder by drag and by keys. The drag answers an
// insertion point off the pointer; the keys move the current tab by one.
function run(check) {
    function three(path, index) {
        var pane = Fixture.pane(path || "/tmp/a")
        pane.tabs = { items: [{ path: "/tmp/a" }, { path: "/tmp/b" }, { path: "/tmp/c" }],
                      index: index === undefined ? 1 : index,
                      pendingCursor: -1, pendingSortBy: "", pendingSortDesc: false }
        return pane
    }
    function order(pane) {
        return pane.tabs.items.map(function (item) { return item.path }).join(",")
    }

    var left = three("/tmp/b", 1)
    Tabs.act("tabMoveLeft", left)
    check("{ swaps the current tab with its left neighbour", order(left), "/tmp/b,/tmp/a,/tmp/c")
    check("and the current tab stays current", Tabs.currentIndex(left), 0)
    check("and moving lists nothing", left.listed.join(","), "")

    var right = three("/tmp/b", 1)
    Tabs.act("tabMoveRight", right)
    check("} swaps the current tab with its right neighbour", order(right), "/tmp/a,/tmp/c,/tmp/b")
    check("and the current tab stays current", Tabs.currentIndex(right), 2)
    check("and moving lists nothing either", right.listed.join(","), "")

    var first = three("/tmp/a", 0)
    Tabs.act("tabMoveLeft", first)
    check("{ on the first tab is a no-op", order(first) + "|" + Tabs.currentIndex(first), "/tmp/a,/tmp/b,/tmp/c|0")

    var last = three("/tmp/c", 2)
    Tabs.act("tabMoveRight", last)
    check("} on the last tab is a no-op", order(last) + "|" + Tabs.currentIndex(last), "/tmp/a,/tmp/b,/tmp/c|2")

    var toFirst = three("/tmp/c", 2)
    Tabs.move(toFirst, 2, 0)
    check("a drag to the near end lands first", order(toFirst), "/tmp/c,/tmp/a,/tmp/b")
    check("and the dragged tab stays current", Tabs.currentIndex(toFirst), 0)

    var toLast = three("/tmp/a", 0)
    Tabs.move(toLast, 0, 2)
    check("a drag to the far end lands last", order(toLast), "/tmp/b,/tmp/c,/tmp/a")
    check("and the dragged tab stays current there too", Tabs.currentIndex(toLast), 2)

    var behind = three("/tmp/c", 2)
    Tabs.move(behind, 0, 2)
    check("moving a tab across the current one keeps the same tab current",
          order(behind) + "|" + Tabs.currentIndex(behind), "/tmp/b,/tmp/c,/tmp/a|1")

    var sorted = three("/tmp/b", 1)
    sorted.tabs.items[0].sortBy = "size"
    sorted.tabs.items[2].sortBy = "mtime"
    Tabs.act("tabMoveRight", sorted)
    check("each tab keeps its own sort order across a move",
          sorted.tabs.items.map(function (item) { return item.sortBy }).join(","), "size,mtime,name")

    var single = Fixture.pane("/tmp/only")
    Tabs.act("tabMoveLeft", single)
    Tabs.act("tabMoveRight", single)
    check("a single tab moves nowhere and gains no tab state", single.tabs, null)

    var bad = three("/tmp/b", 1)
    Tabs.move(bad, -1, 0)
    Tabs.move(bad, 0, 9)
    Tabs.move(bad, 1, 1)
    check("an out-of-range or empty move changes nothing", order(bad) + "|" + Tabs.currentIndex(bad), "/tmp/a,/tmp/b,/tmp/c|1")

    check("an insertion left of the strip clamps to the near end", TabMove.insertionAt(-20, 100, 3), 0)
    check("an insertion inside the first tab lands before it", TabMove.insertionAt(49, 100, 3), 0)
    check("an insertion past a tab middle lands after it", TabMove.insertionAt(50, 100, 3), 1)
    check("an insertion past the last tab clamps to the far end", TabMove.insertionAt(999, 100, 3), 3)
    check("a step left clamps at the near end", TabMove.step(0, -1, 3), 0)
    check("a step right clamps at the far end", TabMove.step(2, 1, 3), 2)

    // No row acts while a listing is out, so a move then refuses like selectAt does.
    var busyMove = three("/tmp/b", 1)
    busyMove.listInFlight = true
    busyMove.tabs.pendingSortBy = "size"
    busyMove.tabs.pendingCursor = 7
    Tabs.move(busyMove, 2, 0)
    check("a move while a listing is out is refused",
        order(busyMove) + "|" + busyMove.said[busyMove.said.length - 1], "/tmp/a,/tmp/b,/tmp/c|A directory is already loading.")
    check("and it keeps the pending restore", busyMove.tabs.pendingSortBy + "|" + busyMove.tabs.pendingCursor, "size|7")
    // The rail's favourite drag answers its landing and its line from the same helper.
    // The rail's favourite drag answers its landing and its line from the same helper.
    var down = TabMove.railReorder(30, 1, 30, 5)
    check("a rail drag down one lands one lower", down.to, 2)
    check("and draws the line below it", down.line, 3)
    var up = TabMove.railReorder(-30, 1, 30, 5)
    check("a rail drag up one lands one higher", up.to, 0)
    check("and draws the line above it", up.line, 0)
    check("a rail drag past the near end clamps its landing", TabMove.railReorder(-999, 0, 30, 5).to, 0)
    check("and its line clamps too", TabMove.railReorder(-999, 0, 30, 5).line, 0)
    check("a rail drag past the far end clamps its landing", TabMove.railReorder(999, 4, 30, 5).to, 4)
    check("and its line rests past the last row", TabMove.railReorder(999, 4, 30, 5).line, 5)
    check("a sub-half-row rail drag lands nowhere", TabMove.railReorder(10, 1, 30, 5).to, 1)
}
