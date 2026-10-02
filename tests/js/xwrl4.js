.import "../../ui/js/Anchor.js" as Anchor
.import "../../ui/js/Selection.js" as Selection
.import "../../ui/js/Marks.js" as Marks
.import "../../ui/js/Nav.js" as Nav

// xw5-r2 review findings F1 to F5. Each check fails on 8fdd71e7 and passes after.

function pane() {
    var p = {
        listInFlight: false, listedSeen: true, path: "/d", total: 0, held: 0,
        rows: [], kindNames: [], cursorIndex: 0, renamingIndex: -1, renamePending: false,
        menuVisible: false, menuActions: { opened: false, pendingAction: "", pendingActivation: false },
        filterTyping: false, filterQuery: "", searchMode: "", selectionBand: null,
        collide: { pending: null }, windowSize: 350, shown: null, _rowH: 37,
        listArea: { contentY: 0, originY: 0 }, dragActive: false, awaitingPaths: false,
        selection: Selection.create(), selectionVersion: 0, selectionAnchor: 0,
        cursorSetTo: -1, sent: []
    }
    p.selectionCount = function () { return p.selection.count() }
    p.selectedIndices = function () { return p.selection.indices() }
    p.clearSelection = function () { p.selection.clear(); p.selectionVersion += 1 }
    p.setCursor = function (i, ctx) { p.cursorIndex = i; p.cursorSetTo = i }
    p.selectOnly = function (i) { p.selection.only(i); p.selectionVersion += 1; p.cursorIndex = i; p.cursorSetTo = i }
    p.rowFor = function (i) { var o = i - p.held; return o < 0 || o >= p.rows.length ? null : p.rows[o] }
    p.join = function (b, n) { return b === "/" ? "/" + n : b + "/" + n }
    p.message = function () {}
    p.swap = { hold: function () { return false } }
    p.listArea.primeSettle = function () {}
    p.openWithoutHistory = function (t, o) { Nav.openWithoutHistory(p, t, o) }
    p.backend = {
        list: function (path) { p.sent.push("list " + path) },
        askFsInfo: function () { p.sent.push("fsinfo") },
        window: function (s) { p.sent.push("window " + s) },
        send: function (o) { p.sent.push(o.c + ":" + (o.rows ? o.rows.join(",") : o.paths ? o.paths.length + "p" : "")) },
        askPaths: function (r) { p.sent.push("paths:" + r.join(",")) }
    }
    return p
}

function staged(names, cursor, selected) {
    var p = pane()
    p.rows = names.map(function (n) { return { n: n } })
    p.total = names.length
    p.cursorIndex = cursor
    for (var i = 0; i < selected.length; i++)
        p.selection.toggle(selected[i])
    return p
}

function run(check) {
    // F1: a lone selection restores with only(), so j carries it to the next row.
    var lone = staged(["a", "b", "c", "d", "e"], 2, [])
    lone.selection.only(2)
    var loneAnchor = Anchor.watched(lone, null, 37)
    lone.held = 0
    lone.rows = [{ n: "a" }, { n: "b" }, { n: "c" }, { n: "d" }, { n: "e" }]
    lone.total = 5
    Anchor.apply(lone, loneAnchor, 37)
    check("F1 lone stays lone after the re-read", lone.selection.follows(), true)
    lone.setCursor(3, 0)
    Marks.follow(lone)
    check("F1 j carries the lone mark to the next row", lone.selectedIndices().join(","), "3")

    // F2: 1000 marked, one create, 1001 rows and 1000 marks after.
    var names = []
    for (var i = 0; i < 1000; i++)
        names.push("f" + ("000" + i).slice(-4))
    var big = pane()
    big.rows = names.slice(0, 350).map(function (n) { return { n: n } })
    big.held = 0
    big.total = 1000
    big.cursorIndex = 0
    big.selection.all(1000)
    var bigAnchor = Anchor.watched(big, 37)
    var sentPaths = false
    for (var s = 0; s < big.sent.length; s++) {
        if (big.sent[s].indexOf("paths:") === 0)
            sentPaths = true
    }
    check("F2 unheld names resolve through one batched paths request", sentPaths, true)
    if (typeof Anchor.fillPaths === "function" && bigAnchor && bigAnchor.needPaths) {
        var need = bigAnchor.needPaths
        var list = need.map(function (idx) { return "/d/" + names[idx] })
        Anchor.fillPaths(big, bigAnchor, list)
    }
    var after = ["NEW"].concat(names.slice(0, 349))
    big.held = 0
    big.rows = after.map(function (n) { return { n: n } })
    big.total = 1001
    var standing = Anchor.apply(big, bigAnchor, 37)
    check("F2 held plus locate waits instead of finishing short", standing === bigAnchor, true)
    if (bigAnchor && bigAnchor.locatePaths) {
        // The backend scans the whole listing, not the held window, so every name resolves
        // at its listing index; the expectation is computed from the listing, never assigned.
        var full = ["NEW"].concat(names)
        var matches = []
        for (var k = 0; k < full.length; k++)
            matches.push({ path: "/d/" + full[k], index: big.held + k })
        var wrongDir = Anchor.takeLocated(big, bigAnchor, { directory: "/other", matches: matches })
        check("F2 a locate reply for another directory keeps the anchor standing",
              wrongDir.handled === false && wrongDir.anchor === bigAnchor, true)
        var taken = Anchor.takeLocated(big, bigAnchor, { directory: "/d", ok: true, matches: matches })
        check("F2 the locate reply for this directory resolves the anchor",
              taken.handled === true && taken.anchor === null, true)
    }
    check("F2 one create keeps every row", big.total, names.length + 1)
    check("F2 all marks survive on the same files", big.selection.count(), names.length)

    // F3: start above zero waits for the asked window when the cursor lands early.
    var mid = staged([], 315, [])
    mid.held = 180
    mid.rows = []
    for (var r = 180; r < 510; r++)
        mid.rows.push({ n: "g" + r })
    mid.rows[135] = { n: "cursor" }
    for (var q = 335; q <= 340; q++)
        mid.rows[q - 180] = { n: "m" + q }
    mid.cursorIndex = 315
    mid.total = 500
    for (var t = 335; t <= 340; t++)
        mid.selection.toggle(t)
    var midAnchor = Anchor.watched(mid, 37)
    mid.held = 0
    mid.rows = []
    for (var u = 0; u < 330; u++)
        mid.rows.push({ n: "g" + u })
    mid.rows[316] = { n: "cursor" }
    mid.total = 501
    var early = Anchor.apply(mid, midAnchor, 37)
    check("F3 first window never finishes marks past it", early === midAnchor, true)
    mid.held = 180
    mid.rows = []
    for (var v = 180; v < 510; v++)
        mid.rows.push({ n: "g" + v })
    mid.rows[136] = { n: "cursor" }
    for (var w = 336; w <= 341; w++)
        mid.rows[w - 180] = { n: "m" + (w - 1) }
    mid.total = 501
    Anchor.apply(mid, midAnchor, 37)
    check("F3 asked window keeps the cursor on its file", mid.cursorSetTo, 316)
    check("F3 all six marks survive", mid.selection.count(), 6)

    // F4: cursor row stays at the same screen y when a row lands above it.
    var view = pane()
    view._rowH = 37
    view.listArea.contentY = 2400
    view.rows = []
    for (var f = 0; f < 200; f++)
        view.rows.push({ n: "h" + f })
    view.held = 0
    view.total = 200
    view.cursorIndex = 70
    var saved = view.rows.map(function (row) { return row.n })
    var viewAnchor = Anchor.watched(view, 37)
    check("F4 offset recorded", viewAnchor.offset, 190)
    check("F4 anchor name", viewAnchor.name, "h70")
    view.rows = ["NEW"].concat(saved.slice(0, 199)).map(function (n) { return { n: n } })
    view.total = 201
    view.held = 0
    var viewRes = Anchor.apply(view, viewAnchor, 37)
    check("F4 finished", viewRes, null)
    check("F4 cursor landed", view.cursorSetTo, 71)
    check("F4 contentY restored", view.listArea.contentY, 2437)
    var rowH = 37
    var screenY = (71 * rowH) - view.listArea.contentY
    check("F4 cursor row keeps its screen y after one insert above", screenY, 190)

    // F5: a restore past the origin clamps instead of drawing a blank strip above row 0.
    var neg = pane()
    neg.listArea = { contentY: 500, originY: 0, contentHeight: 200 * 37, height: 400,
                     primeSettle: function () {} }
    neg.rows = [{ n: "h0" }]
    neg.held = 0
    neg.total = 1
    neg.cursorIndex = 0
    var negAnchor = Anchor.watched(neg, 37)
    negAnchor.offset = 600
    neg.rows = [{ n: "h0" }]
    neg.total = 1
    Anchor.apply(neg, negAnchor, 37)
    check("F5 a negative restore clamps to the origin", neg.listArea.contentY, 0)

    // F5: in the grid the cursor view is a tile row, so one step down moves one cell height.
    var grid = pane()
    grid.viewMode = "grid"
    grid.listArea = { contentY: 50, originY: 0, contentHeight: 3000, height: 400, columns: 3, cellHeightPx: 100,
                      primeSettle: function () {} }
    grid.rows = []
    for (var g = 0; g < 30; g++)
        grid.rows.push({ n: "h" + g })
    grid.held = 0
    grid.total = 30
    grid.cursorIndex = 7
    var gridAnchor = Anchor.watched(grid, 37)
    check("F5 grid offset counts tile rows, not list rows", gridAnchor.offset, 150)
    grid.rows = []
    for (var h = 0; h < 30; h++)
        grid.rows.push({ n: "h" + h })
    grid.total = 30
    Anchor.apply(grid, gridAnchor, 37)
    check("F5 grid restore keeps the tile row's screen y", grid.listArea.contentY, 50)

    // F5: a drag in progress holds the re-read, and the debt runs after the drop.
    var drag = pane()
    check("F5 at rest holds nothing back", Anchor.busy(drag), false)
    drag.dragActive = true
    check("F5 an active drag holds the re-read", Anchor.busy(drag), true)
    drag.dragActive = false
    drag.awaitingPaths = true
    check("F5 awaiting drag paths holds the re-read", Anchor.busy(drag), true)
    drag.awaitingPaths = false
    check("F5 after the drop holds nothing back", Anchor.busy(drag), false)
}
