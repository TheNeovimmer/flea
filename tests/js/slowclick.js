.import "../../ui/js/SlowClick.js" as SlowClick
.import "../../ui/js/Tap.js" as Tap
.import "sourcefixture.js" as Source

// Slow-click rename shared by the three views: tap arms a pane timer, double click cancels, fire renames a still-held sole row.

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
        selectionCount: function () { return this.picked.length },
        isSelected: function (i) { return this.picked.indexOf(i) >= 0 },
        commitOpenRename: function () {},
        selectOnly: function (i) { this.picked = [i]; this.cursorIndex = i; this.did.push("selectOnly") },
        toggleSelectAt: function (i) { this.did.push("toggleSelect") },
        extendSelectionTo: function (i) { this.did.push("extendSelect") },
        setCursor: function (i) { this.cursorIndex = i },
        act: function (action) { this.did.push(action) },
        did: [],
        cancelled: 0,
        cancelSlowClick: function () { this.cancelled += 1; SlowClick.cancel(this) }
    }
}

function run(check) {
    // The name slot can be wider or taller than the glyphs it draws.
    var label = { visible: true, width: 200, height: 40, contentWidth: 60, contentHeight: 16,
        mapFromItem: function (owner, x, y) { return { x: x, y: y } } }
    check("a left-aligned name hits its drawn text", Tap.onName(label, null, { x: 10, y: 8 }, false), true)
    check("blank space in the name slot is not text", Tap.onName(label, null, { x: 100, y: 8 }, false), false)
    check("a centered caption hits at its middle", Tap.onName(label, null, { x: 100, y: 8 }, true), true)
    check("a centered caption excludes its side padding", Tap.onName(label, null, { x: 10, y: 8 }, true), false)
    check("a caption excludes its reserved empty line", Tap.onName(label, null, { x: 100, y: 30 }, true), false)
    label.visible = false
    check("a hidden name is never a hit", Tap.onName(label, null, { x: 10, y: 8 }, false), false)
    check("the slow click lives in SlowClick.js", typeof SlowClick.arm, "function")
    check("with a fire and a cancel beside it",
          typeof SlowClick.fire + "|" + typeof SlowClick.cancel, "function|function")
    check("fire takes the pane and the drag state alone", SlowClick.fire.length, 2)
    if (typeof SlowClick.arm !== "function" || typeof SlowClick.fire !== "function")
        return
    var none = Qt.NoModifier

    // The first tap only selects, so it arms nothing and renames nothing.
    var first = root()
    check("the arming tap starts no timer", SlowClick.arm(first, 4, none, 1000, 400), false)
    // The second tap inside the interval is the double click's own first half, so it never arms.
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
    check("the timer fires a rename when nothing moved", SlowClick.fire(fired), true)
    check("and the rename went out", fired.did.join(","), "rename")
    // The slow click is the pointer path, so its rename carries context 0 and the list never moves under it.
    var firedCtx = root()
    SlowClick.arm(firedCtx, 4, none, 1000, 400)
    SlowClick.arm(firedCtx, 4, none, 1500, 400)
    var firedArgs = []
    firedCtx.act = function (action, menuId, paths, context) { firedArgs = [action, context] }
    SlowClick.fire(firedCtx)
    check("the timer's rename carries pointer context", firedArgs.join("|"), "rename|0")
    // A double click cancels the armed timer through the pane and opens instead.
    var doubled = root()
    SlowClick.arm(doubled, 4, none, 1000, 400)
    SlowClick.arm(doubled, 4, none, 1500, 400)
    Tap.tapped(4, 2, none, doubled)
    doubled.cancelSlowClick()
    check("a second tap in time opens", doubled.did.join(","), "selectOnly,open")
    check("and the cancelled timer renames nothing", SlowClick.fire(doubled), false)
    // A cursor or selection change before it fires cancels.
    var left = root()
    SlowClick.arm(left, 4, none, 1000, 400)
    SlowClick.arm(left, 4, none, 1500, 400)
    left.picked = [5]
    left.cursorIndex = 5
    check("a selection that moved cancels the timer", SlowClick.fire(left), false)
    check("and nothing went out", left.did.length, 0)
    var stepped = root()
    SlowClick.arm(stepped, 4, none, 1000, 400)
    SlowClick.arm(stepped, 4, none, 1500, 400)
    stepped.cursorIndex = 6
    check("a cursor that moved cancels it too", SlowClick.fire(stepped), false)
    // A rename that started meanwhile wins.
    var raced = root()
    SlowClick.arm(raced, 4, none, 1000, 400)
    SlowClick.arm(raced, 4, none, 1500, 400)
    raced.renamingIndex = 4
    check("an edit that opened meanwhile cancels it", SlowClick.fire(raced), false)

    // The gate: modifiers, multi-selections, drags, searches and the setting itself.
    var modified = root()
    SlowClick.arm(modified, 4, none, 1000, 400)
    check("a ctrl tap never arms", SlowClick.arm(modified, 4, Qt.ControlModifier, 2000, 400), false)
    var multi = root()
    SlowClick.arm(multi, 4, none, 1000, 400)
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
    SlowClick.arm(found, 4, none, 1000, 400)
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
    // A double click in single-click mode still opens once: the second tap adds nothing.
    Tap.tapped(9, 2, none, folder)
    check("a second tap in single-click mode opens nothing again", folder.did.join(","), "selectOnly,open")
    var plain = root()
    Tap.tapped(9, 1, none, plain)
    check("double-click mode still only selects on one tap", plain.did.join(","), "selectOnly")

    // A first click on an unselected row never arms off the selection the tap itself just made.
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

    // An open menu or an active drag blocks the timer, and a menu request cancels the arm outright.
    var menud = root()
    SlowClick.arm(menud, 4, none, 1000, 400)
    SlowClick.arm(menud, 4, none, 1500, 400)
    menud.menuVisible = true
    check("an open menu blocks the timer", SlowClick.fire(menud), false)
    var dragd = root()
    SlowClick.arm(dragd, 4, none, 1000, 400)
    SlowClick.arm(dragd, 4, none, 1500, 400)
    dragd.dragActive = true
    check("an active drag blocks the timer", SlowClick.fire(dragd), false)
    var liveDrag = root()
    SlowClick.arm(liveDrag, 4, none, 1000, 400)
    SlowClick.arm(liveDrag, 4, none, 1500, 400)
    check("a live drag passed to fire blocks it too", SlowClick.fire(liveDrag, true), false)
    var menureq = root()
    menureq.slowClickAt = 1000
    menureq.slowClickIndex = 4
    menureq.picked = [4]
    menureq.cursorIndex = 4
    Tap.tappedMenu(4, { scenePosition: null }, menureq, { openAt: function (pos) {} })
    check("a menu request cancels the slow click", menureq.slowClickIndex, -2)
    check("and it ran through the pane", menureq.cancelled, 1)

    // wasSoleSelection reads O(1) facts, never the whole index array a select-all would build.
    var calls = 0
    var counted = root()
    counted.selectedIndices = function () { calls += 1; return this.picked }
    check("wasSoleSelection answers sole without the array", SlowClick.wasSoleSelection(counted, 4), true)
    check("and it built no index array to do it", calls, 0)

    // The views capture sole selection before the tap selects for it, so the capture reads above the tap.
    var list = Source.source("ui/List.qml")
    check("the list captures sole selection before it taps",
          list.indexOf("slowClickWasSole") >= 0 && list.indexOf("slowClickWasSole") < list.indexOf("Tap.tapped("), true)
    var grid = Source.source("ui/GridArea.qml")
    check("the grid captures sole selection before it taps",
          grid.indexOf("slowClickWasSole") >= 0 && grid.indexOf("slowClickWasSole") < grid.indexOf("Tap.tapped("), true)
    var columns = Source.source("ui/ColumnsArea.qml")
    check("the columns view captures sole selection before it taps",
          columns.indexOf("slowClickWasSole") >= 0 && columns.indexOf("slowClickWasSole") < columns.indexOf("Tap.tappedMiddle("), true)

    // Each view cancels the armed timer on the second tap, so a double click opens without renaming.
    check("the list cancels the arm on a second tap",
          Source.slice(list, "onTapped:", "Flea.RowDrag").indexOf("tapCount === 2) root.pane.cancelSlowClick()") >= 0, true)
    check("the grid cancels the arm on a second tap",
          Source.slice(grid, "onTapped:", "Flea.RowDrag").indexOf("tap.tapCount === 2) root.pane.cancelSlowClick()") >= 0, true)
    check("the columns view cancels the arm on a second tap",
          Source.slice(columns, "onPicked:", "onMenuRequested:").indexOf("tapCount === 2) root.pane.cancelSlowClick()") >= 0, true)

    // A press held past the timer never fires while the button is down; the release still arms.
    check("a list press stops the slow-click timer",
          list.indexOf("onPressedChanged: if (pressed) root.pane.pressSlowClick()") >= 0, true)
    check("a grid press stops the slow-click timer",
          grid.indexOf("onPressedChanged: if (pressed) root.pane.pressSlowClick()") >= 0, true)
    var columnPane = Source.source("ui/ColumnPane.qml")
    check("a columns press emits before the release arms",
          columnPane.indexOf("signal rowPressed(int index)") >= 0
          && columnPane.indexOf("onPressedChanged: if (pressed) root.rowPressed(cell.listingIndex)") >= 0, true)
    check("the columns view stops the timer on that press",
          columns.indexOf("onRowPressed: root.pane.pressSlowClick()") >= 0, true)
    var pane = Source.source("ui/Pane.qml")
    check("a press stops the timer without clearing the tap record",
          pane.indexOf("function pressSlowClick() { slowClickTimer.stop() }") >= 0, true)
    check("a cancel stops the timer and clears the tap record",
          pane.indexOf("function cancelSlowClick() { slowClickTimer.stop(); SlowClick.cancel(root) }") >= 0, true)
    // A press on empty ground holds the button past the interval, so it stops the pane timer too.
    var band = Source.source("ui/SelectionBand.qml")
    check("an empty-ground press stops the slow-click timer",
          Source.slice(band, "onPressed:", "onPositionChanged:").indexOf("cancelSlowClick") >= 0, true)
}
