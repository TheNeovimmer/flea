.import "../../ui/js/ScrollOff.js" as ScrollOff
.import "sourcefixture.js" as Source

// The cursor keeps three rows of context above and below while scrolling, and still
// reaches the first and last rows. Pure index maths; the views turn the answer into pixels.

function run(check) {
    check("the context lives in its own module", typeof ScrollOff.firstFor, "function")
    if (typeof ScrollOff.firstFor !== "function")
        return
    check("three rows of context is the rule", ScrollOff.CONTEXT, 3)

    // A 36-row viewport over 100 rows, first visible 10, cursor on 20: inside the margin, nothing moves.
    check("a cursor inside the margin moves nothing", ScrollOff.firstFor(10, 36, 20, 100), 10)
    // Cursor two below the top edge: the window slides so three stand above it.
    check("a cursor three below the edge stands pat", ScrollOff.firstFor(10, 36, 13, 100), 10)
    check("a cursor one below the edge pulls one row", ScrollOff.firstFor(10, 36, 11, 100), 8)
    check("a cursor on the edge pulls three", ScrollOff.firstFor(10, 36, 10, 100), 7)
    // Cursor near the bottom edge: the window slides down instead.
    check("a cursor on the last visible row pushes three below it", ScrollOff.firstFor(10, 36, 45, 100), 13)
    check("a cursor past the window jumps with its context", ScrollOff.firstFor(10, 36, 80, 100), 48)
    // The ends still reach: the first row pins the window to the top and the last to the bottom.
    check("the first row pins the window to the top", ScrollOff.firstFor(5, 36, 0, 100), 0)
    check("the last row pins it to the bottom", ScrollOff.firstFor(60, 36, 99, 100), 64)
    check("and the second row still shows its context above", ScrollOff.firstFor(5, 36, 1, 100), 0)
    // A listing shorter than the viewport never scrolls at all.
    check("a short listing pins to the origin", ScrollOff.firstFor(0, 36, 12, 20), 0)
    check("an empty listing pins too", ScrollOff.firstFor(0, 36, 0, 0), 0)

    // A partly drawn bottom row is not visible: height 1310 at row 31 holds 42
    // whole rows, not the ceil's 43, so End parks past the last row's bottom.
    check("the fully visible count exists", typeof ScrollOff.fullyVisible, "function")
    if (typeof ScrollOff.fullyVisible !== "function")
        return
    check("the fully visible count floors a partial row", ScrollOff.fullyVisible(1310, 31), 42)
    check("a short viewport still holds one row", ScrollOff.fullyVisible(10, 31), 1)
    var endFirst = ScrollOff.firstFor(0, ScrollOff.fullyVisible(1310, 31), 149, 150)
    check("End parks at or past the last row's bottom", endFirst * 31 + 1310 >= 150 * 31, true)
    check("End parks exactly there", endFirst, 108)
    // The floor must not break the upward context: cursor at the top still pins to the origin.
    var topFirst = ScrollOff.firstFor(40, ScrollOff.fullyVisible(1310, 31), 0, 150)
    check("a top-edge move pins to the origin", topFirst, 0)
    var nearTop = ScrollOff.firstFor(40, ScrollOff.fullyVisible(1310, 31), 1, 150)
    check("a near-top move keeps its upward context", nearTop, 0)
    var list = Source.source("ui/List.qml")
    check("the list scrolls from the fully visible count",
          list.indexOf("ScrollOff.fullyVisible(root.height, rowH)") >= 0, true)
    var columnPane = Source.source("ui/ColumnPane.qml")
    check("the columns view scrolls from the fully visible count",
          columnPane.indexOf("ScrollOff.fullyVisible(view.height, rowH)") >= 0, true)

    // A viewport shorter than the margin parks the cursor outside it: list 110 px
    // tall at 31 px rows holds 3, so first 7 cursor 10 Down to 11 must not want 12.
    check("a short window keeps its margin inside itself", ScrollOff.firstFor(7, 3, 11, 20), 10)
    var shortVisibles = [1, 2, 3, 4, ScrollOff.fullyVisible(110, 31)]
    for (var vi = 0; vi < shortVisibles.length; vi++) {
        var vis = shortVisibles[vi]
        var total = 20
        var walk = 0
        var holds = true
        for (var down = 0; down < total; down++) {
            var wDown = ScrollOff.firstFor(walk, vis, down, total)
            if (down < wDown || down > wDown + vis - 1)
                holds = false
            walk = wDown
        }
        for (var up = total - 1; up >= 0; up--) {
            var wUp = ScrollOff.firstFor(walk, vis, up, total)
            if (up < wUp || up > wUp + vis - 1)
                holds = false
            walk = wUp
        }
        check("a short viewport of " + vis + " keeps the cursor inside down then up", holds, true)
    }

    // A pixel wheel scroll can cut the first row at the top edge while the index
    // window does not move: contentY 20 leaves row 0 20 px under the edge, so
    // Home finds want 0 === first 0 and must still scroll to align it.
    check("the pixel align rule exists", typeof ScrollOff.needsAlign, "function")
    if (typeof ScrollOff.needsAlign === "function") {
        check("a cut first row needs aligning", ScrollOff.needsAlign(0, 0, 10, 20, 310, 31), true)
        check("an aligned first row needs nothing", ScrollOff.needsAlign(0, 0, 10, 0, 310, 31), false)
        check("a middle row never aligns the window", ScrollOff.needsAlign(5, 0, 10, 20, 310, 31), false)
        check("the index alone misses the cut", ScrollOff.firstFor(0, 10, 0, 20), 0)
    }
    check("the list aligns a cut cursor row",
          list.indexOf("ScrollOff.needsAlign") >= 0, true)
    check("the columns view aligns a cut cursor row",
          columnPane.indexOf("ScrollOff.needsAlign") >= 0, true)

    // A click never scrolls the list under the pointer: pointer moves carry
    // context 0 through the one showCursor path, while keyboard moves keep 3.
    // Viewport 36 rows, first 10: row 43 stands two above the bottom edge.
    check("a pointer two above the bottom edge moves nothing",
          ScrollOff.firstFor(10, 36, 43, 100, 0), 10)
    check("a keyboard move to the same row keeps its three rows",
          ScrollOff.firstFor(10, 36, 43, 100), 11)
    check("and the default is the keyboard's three",
          ScrollOff.firstFor(10, 36, 43, 100, undefined), 11)
    // The first row past a 42-row window is cut by the bottom edge: a click
    // shows it whole with one row, a keyboard move keeps three below it.
    check("a pointer to a cut bottom row shows it whole",
          ScrollOff.firstFor(0, 42, 42, 150, 0), 1)
    check("a keyboard move to the same cut row keeps three",
          ScrollOff.firstFor(0, 42, 42, 150), 4)
    // Both views carry the click's context through the one path, never a copy.
    check("the list threads the click context to firstFor",
          list.indexOf("firstFor(first, visible, view, root.pane.shownTotal, context)") >= 0, true)
    check("the columns view threads it too",
          columnPane.indexOf("firstFor(first, visibleRows, viewIndex, total, context)") >= 0, true)
    var pane = Source.source("ui/Pane.qml")
    check("the pane threads it to both views",
          pane.indexOf("showCursor(view, context)") >= 0, true)
    check("and setCursor carries it", pane.indexOf("Filter.setCursor(root, index, context)") >= 0, true)
    var filter = Source.source("ui/js/Filter.js")
    check("the filter carries it to the pane",
          filter.indexOf("pane.showRow(to, context)") >= 0, true)
    var tap = Source.source("ui/js/Tap.js")
    check("a left click carries context 0", tap.indexOf("selectOnly(index, 0)") >= 0, true)
    check("a right click carries it too", tap.indexOf("setCursor(index, 0)") >= 0, true)
    var marks = Source.source("ui/js/Marks.js")
    check("a shift click carries it", marks.indexOf("Filter.setCursor(pane, index, 0)") >= 0, true)
    check("the columns selection follow keeps context 0",
          columnPane.indexOf("showCursor(root.pane ? Filter.viewOf(root.pane.shown, root.selectedIndex) : root.selectedIndex, 0)") >= 0, true)
}
