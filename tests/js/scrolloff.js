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
}
