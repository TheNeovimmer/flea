.import "../../ui/js/SlowClick.js" as SlowClick
.import "../../ui/js/Tap.js" as Tap

// Slow-click rename, one shared mechanism for the three views: a tap arms a
// pane timer of the double-click interval, a second tap in time cancels it and
// opens as a double click does, and the timer fires a rename only when the
// cursor and the sole selection are still that row and nothing else started.

function root() {
    return {
        singleClick: false,
        clickRename: true,
        searchMode: "",
        renamingIndex: -1,
        renamePending: false,
        selectionBand: null,
        dragActive: false,
        menuVisible: false,
        cursorIndex: 4,
        picked: [4],
        slowClickAt: 0,
        slowClickIndex: -2,
        selectedIndices: function () { return this.picked },
        commitOpenRename: function () {},
        selectOnly: function (i) { this.picked = [i]; this.cursorIndex = i; this.did.push("selectOnly") },
        toggleSelectAt: function (i) { this.did.push("toggleSelect") },
        extendSelectionTo: function (i) { this.did.push("extendSelect") },
        setCursor: function (i) { this.cursorIndex = i },
        act: function (action) { this.did.push(action) },
        did: []
    }
}

function run(check) {
    check("the slow click lives in SlowClick.js", typeof SlowClick.arm, "function")
    check("with a fire and a cancel beside it",
          typeof SlowClick.fire + "|" + typeof SlowClick.cancel, "function|function")
    if (typeof SlowClick.arm !== "function" || typeof SlowClick.fire !== "function")
        return
    var none = Qt.NoModifier

    // The first tap only selects, so it arms nothing and renames nothing.
    var first = root()
    check("the arming tap starts no timer", SlowClick.arm(first, 4, none, 1000, 400), false)
    // The second tap inside the double-click interval is the double click's own
    // first half: it opens through tapped() and never arms.
    var quick = root()
    SlowClick.arm(quick, 4, none, 1000, 400)
    check("a second tap inside the interval arms nothing", SlowClick.arm(quick, 4, none, 1200, 400), false)
    // The second tap after the interval arms the timer.
    var slow = root()
    SlowClick.arm(slow, 4, none, 1000, 400)
    check("a second tap after the interval arms the timer", SlowClick.arm(slow, 4, none, 1500, 400), true)
    check("exactly at the interval is still the double click", (function () {
        var edge = root()
        SlowClick.arm(edge, 4, none, 1000, 400)
        return SlowClick.arm(edge, 4, none, 1400, 400)
    })(), false)
    // A tap on another row re-arms rather than firing.
    var moved = root()
    SlowClick.arm(moved, 4, none, 1000, 400)
    moved.picked = [7]
    moved.cursorIndex = 7
    check("a tap on another row re-arms instead", SlowClick.arm(moved, 7, none, 2000, 400), false)

    // The timer firing with the row still under the cursor renames.
    var fired = root()
    SlowClick.arm(fired, 4, none, 1000, 400)
    SlowClick.arm(fired, 4, none, 1500, 400)
    check("the timer fires a rename when nothing moved", SlowClick.fire(fired, 2000, 400), true)
    check("and the rename went out", fired.did.join(","), "rename")
    // A double click cancels the armed timer and opens instead.
    var doubled = root()
    SlowClick.arm(doubled, 4, none, 1000, 400)
    SlowClick.arm(doubled, 4, none, 1500, 400)
    Tap.tapped(4, 2, none, doubled)
    SlowClick.cancel(doubled)
    check("a second tap in time opens", doubled.did.join(","), "selectOnly,open")
    check("and the cancelled timer renames nothing", SlowClick.fire(doubled, 2000, 400), false)
    // A cursor or selection change before it fires cancels.
    var left = root()
    SlowClick.arm(left, 4, none, 1000, 400)
    SlowClick.arm(left, 4, none, 1500, 400)
    left.picked = [5]
    left.cursorIndex = 5
    check("a selection that moved cancels the timer", SlowClick.fire(left, 2000, 400), false)
    check("and nothing went out", left.did.length, 0)
    var stepped = root()
    SlowClick.arm(stepped, 4, none, 1000, 400)
    SlowClick.arm(stepped, 4, none, 1500, 400)
    stepped.cursorIndex = 6
    check("a cursor that moved cancels it too", SlowClick.fire(stepped, 2000, 400), false)
    // A rename that started meanwhile wins.
    var raced = root()
    SlowClick.arm(raced, 4, none, 1000, 400)
    SlowClick.arm(raced, 4, none, 1500, 400)
    raced.renamingIndex = 4
    check("an edit that opened meanwhile cancels it", SlowClick.fire(raced, 2000, 400), false)

    // The gate: modifiers, multi-selections, drags, searches and the setting itself.
    var modified = root()
    SlowClick.arm(modified, 4, none, 1000, 400)
    check("a ctrl tap never arms", SlowClick.arm(modified, 4, Qt.ControlModifier, 2000, 400), false)
    var multi = root()
    multi.picked = [4, 5]
    check("a second row marked means no arm", SlowClick.arm(multi, 4, none, 2000, 400), false)
    var dragged = root()
    SlowClick.arm(dragged, 4, none, 1000, 400)
    dragged.dragActive = true
    check("a drag never arms", SlowClick.arm(dragged, 4, none, 2000, 400), false)
    var lifted = root()
    SlowClick.arm(lifted, 4, none, 1000, 400)
    check("the live drag state rides the sixth argument", SlowClick.arm(lifted, 4, none, 2000, 400, true), false)
    var found = root()
    found.searchMode = "results"
    check("a search result never arms", SlowClick.arm(found, 4, none, 2000, 400), false)
    var off = root()
    off.clickRename = false
    SlowClick.arm(off, 4, none, 1000, 400)
    check("the setting switches it off", SlowClick.arm(off, 4, none, 2000, 400), false)
    var single = root()
    single.singleClick = true
    SlowClick.arm(single, 4, none, 1000, 400)
    check("single-click mode never arms", SlowClick.arm(single, 4, none, 2000, 400), false)

    // Single-click mode opens folders and files on one tap, and still selects with a modifier.
    var folder = root()
    folder.singleClick = true
    folder.rowFor = function () { return { n: "sub", d: true } }
    Tap.tapped(9, 1, none, folder)
    check("one tap in single-click mode opens the row", folder.did.join(","), "selectOnly,open")
    var plain = root()
    Tap.tapped(9, 1, none, plain)
    check("double-click mode still only selects on one tap", plain.did.join(","), "selectOnly")

    // The timer owns the window: it can fire with Date.now() exactly the
    // interval after the arm, which the old elapsed recheck rejected.
    var exact = root()
    SlowClick.arm(exact, 4, none, 1000, 400)
    SlowClick.arm(exact, 4, none, 1500, 400)
    check("firing at exactly arm time plus interval renames", SlowClick.fire(exact, 1900, 400), true)
    check("and the rename went out", exact.did.join(","), "rename")

    // A first click on an unselected row must not arm off the selection the
    // tap itself just made: the views capture sole selection before tapped.
    var firstClick = root()
    SlowClick.arm(firstClick, 4, none, 1000, 400)
    firstClick.picked = [4]
    firstClick.cursorIndex = 4
    check("a first click on an unselected row arms nothing",
          SlowClick.arm(firstClick, 4, none, 4000, 400, undefined, false), false)
    var secondClick = root()
    SlowClick.arm(secondClick, 4, none, 1000, 400)
    secondClick.picked = [4]
    secondClick.cursorIndex = 4
    check("a true second click on the sole selected row still arms",
          SlowClick.arm(secondClick, 4, none, 1500, 400, undefined, true), true)

    // An open menu or an active drag blocks the timer, and a menu request
    // cancels the arm outright.
    var menud = root()
    SlowClick.arm(menud, 4, none, 1000, 400)
    SlowClick.arm(menud, 4, none, 1500, 400)
    menud.menuVisible = true
    check("an open menu blocks the timer", SlowClick.fire(menud, 2000, 400), false)
    var dragd = root()
    SlowClick.arm(dragd, 4, none, 1000, 400)
    SlowClick.arm(dragd, 4, none, 1500, 400)
    dragd.dragActive = true
    check("an active drag blocks the timer", SlowClick.fire(dragd, 2000, 400), false)
    var liveDrag = root()
    SlowClick.arm(liveDrag, 4, none, 1000, 400)
    SlowClick.arm(liveDrag, 4, none, 1500, 400)
    check("a live drag passed to fire blocks it too", SlowClick.fire(liveDrag, 2000, 400, true), false)
    var menureq = root()
    menureq.slowClickAt = 1000
    menureq.slowClickIndex = 4
    menureq.picked = [4]
    menureq.cursorIndex = 4
    Tap.tappedMenu(4, { scenePosition: null }, menureq, { openAt: function (pos) {} })
    check("a menu request cancels the slow click", menureq.slowClickIndex, -2)
}
