.import "../../ui/js/Tap.js" as Tap

// Slow-click rename: a second single click on the name of the only selected row,
// after the double-click interval, starts rename in place. It never fires on a
// double click or a drag, and single-click mode opens instead of renaming.

function root() {
    return {
        singleClick: false,
        clickRename: true,
        searchMode: "",
        renamingIndex: -1,
        renamePending: false,
        selectionBand: null,
        dragActive: false,
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
    check("the slow click decides in Tap.js", typeof Tap.slowClick, "function")
    if (typeof Tap.slowClick !== "function")
        return
    var none = Qt.NoModifier

    // The first tap only selects, so it arms the window and renames nothing.
    var first = root()
    Tap.tapped(4, 1, none, first)
    check("the arming tap renames nothing", Tap.slowClick(4, none, 1000, 400, first), false)
    // The second tap inside the double-click interval is the double click's own first half.
    var quick = root()
    Tap.tapped(4, 1, none, quick)
    Tap.slowClick(4, none, 1000, 400, quick)
    check("a second tap inside the interval renames nothing", Tap.slowClick(4, none, 1200, 400, quick), false)
    // The second tap after the interval starts the rename.
    var slow = root()
    Tap.tapped(4, 1, none, slow)
    Tap.slowClick(4, none, 1000, 400, slow)
    check("a second tap after the interval renames", Tap.slowClick(4, none, 1500, 400, slow), true)
    check("exactly at the interval is still the double click", (function () {
        var edge = root()
        Tap.tapped(4, 1, none, edge)
        Tap.slowClick(4, none, 1000, 400, edge)
        return Tap.slowClick(4, none, 1400, 400, edge)
    })(), false)
    // A tap on another row re-arms rather than renaming.
    var moved = root()
    Tap.tapped(4, 1, none, moved)
    Tap.slowClick(4, none, 1000, 400, moved)
    Tap.tapped(7, 1, none, moved)
    check("a tap on another row re-arms instead", Tap.slowClick(7, none, 2000, 400, moved), false)

    // The gate: modifiers, multi-selections, drags, searches and the setting itself.
    var modified = root()
    Tap.tapped(4, 1, none, modified)
    Tap.slowClick(4, none, 1000, 400, modified)
    check("a ctrl tap never renames", Tap.slowClick(4, Qt.ControlModifier, 2000, 400, modified), false)
    var multi = root()
    multi.picked = [4, 5]
    check("a second row marked means no rename", Tap.slowClick(4, none, 2000, 400, multi), false)
    var dragged = root()
    Tap.tapped(4, 1, none, dragged)
    Tap.slowClick(4, none, 1000, 400, dragged)
    dragged.dragActive = true
    check("a drag never renames", Tap.slowClick(4, none, 2000, 400, dragged), false)
    var lifted = root()
    Tap.tapped(4, 1, none, lifted)
    Tap.slowClick(4, none, 1000, 400, lifted)
    check("the live drag state rides the sixth argument", Tap.slowClick(4, none, 2000, 400, lifted, true), false)
    check("and a settled one lets it through", Tap.slowClick(4, none, 2600, 400, lifted, false), true)
    var found = root()
    found.searchMode = "results"
    check("a search result never slow-renames", Tap.slowClick(4, none, 2000, 400, found), false)
    var off = root()
    off.clickRename = false
    Tap.tapped(4, 1, none, off)
    Tap.slowClick(4, none, 1000, 400, off)
    check("the setting switches it off", Tap.slowClick(4, none, 2000, 400, off), false)
    var single = root()
    single.singleClick = true
    Tap.tapped(4, 1, none, single)
    Tap.slowClick(4, none, 1000, 400, single)
    check("single-click mode never slow-renames", Tap.slowClick(4, none, 2000, 400, single), false)

    // Single-click mode opens folders and files on one tap, and still selects with a modifier.
    var folder = root()
    folder.singleClick = true
    folder.rowFor = function () { return { n: "sub", d: true } }
    Tap.tapped(9, 1, none, folder)
    check("one tap in single-click mode opens the row", folder.did.join(","), "selectOnly,open")
    var file = root()
    file.singleClick = true
    Tap.tapped(9, 1, none, file)
    check("a file opens on one tap too", file.did.join(","), "selectOnly,open")
    var held = root()
    held.singleClick = true
    Tap.tapped(9, 1, Qt.ControlModifier, held)
    check("ctrl still only selects there", held.did.join(","), "toggleSelect")
    var shifted = root()
    shifted.singleClick = true
    Tap.tapped(9, 1, Qt.ShiftModifier, shifted)
    check("and shift still only extends", shifted.did.join(","), "extendSelect")
    var plain = root()
    Tap.tapped(9, 1, none, plain)
    check("double-click mode still only selects on one tap", plain.did.join(","), "selectOnly")
}
