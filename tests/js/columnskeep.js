.import "../../ui/js/Columns.js" as Columns
.import "sourcefixture.js" as Source

// The backend watches exactly the column directories drawn: every peek names them, and a column that comes back is asked again.
function run(check) {
    var keep = { drawn: [] }
    var asked = function (plan) { return plan.map(function (one) { return one.path + ":" + one.again }).join("|") }
    check("a first refresh asks every column, ancestors then the child", asked(Columns.keepAsks(keep, ["/a", "/a/b"], "/a/b/c")), "/a:true|/a/b:true|/a/b/c:true")
    check("and draws exactly those", keep.drawn.join("|"), "/a|/a/b|/a/b/c")
    check("a column still drawn is asked as before", asked(Columns.keepAsks(keep, ["/a", "/a/b"], "/a/b/d")), "/a:false|/a/b:false|/a/b/d:true")
    check("the child that left is no longer drawn", keep.drawn.join("|"), "/a|/a/b|/a/b/d")
    check("a file under the cursor draws no child column", asked(Columns.keepAsks(keep, ["/a", "/a/b"], "")), "/a:false|/a/b:false")
    check("a column that scrolled away and returns is asked again", asked(Columns.keepAsks(keep, ["/a", "/a/b"], "/a/b/d")), "/a:false|/a/b:false|/a/b/d:true")
    check("a narrow window with no folder under the cursor draws nothing", Columns.keepAsks({ drawn: [] }, [], "").length, 0)
    check("a child that is also an ancestor is named once", Columns.keepAsks({ drawn: [] }, ["/a"], "/a").length, 1)
    var area = Source.source("ui/ColumnsArea.qml")
    var refreshBody = Source.slice(area, "function refreshNeighbours", "function askMeta")
    check("refresh asks from the keep plan", refreshBody.indexOf("Columns.keepAsks(root.keep, Columns.neighbourAsks(root.pane.path, root.width, root.columnsLimit), root.childPath)") >= 0
        && refreshBody.indexOf("root.ask(one.path, one.again, one.again)") >= 0, true)
    check("every column peek carries the drawn set", Source.slice(area, "function ask(path, again, rearm)", "// Hidden view asks nothing")
        .indexOf("root.pane.showHidden, undefined, root.keep.drawn)") >= 0, true)
    check("the wire carries it as keep", Source.source("ui/Backend.qml").indexOf("watch: Array.isArray(keep), keep: keep") >= 0, true)
    runReturn(check)
}

// The shipped ask, answered and refresh bodies and the reply handler, run over a stub backend that holds its replies, so a race between asks and replies is a sequence here.
function columnsArea(area) {
    var load = function (from, to) { return new Function("root", "Columns", "return (" + Source.slice(area, from, to) + ")") }
    var childColumn = { emptyItem: { animateEntrance: true, markItem: { settle: function () {} } } }
    var inert = { cancel: function () {}, stop: function () {} }
    var held = []
    var replies = []
    var sent = []
    var root = {
        visible: true, width: 1300, columnsLimit: undefined, peeked: ({}), pending: ({}), denials: ({}), peekVersion: 0, keep: { drawn: [] },
        childPath: "", shownChildPath: "", cursorIsDir: true,
        pane: { path: "/a/b", windowSize: 35, showHidden: false, backend: { peek: function (path, size, hidden, focus, keep) {
            // The backend's own rule: a watching peek keeps only the drawn folders, then arms the one it answers.
            sent.push(path)
            if (Array.isArray(keep) && keep.length > 0) held = held.filter(function (one) { return keep.indexOf(one) >= 0 })
            if (Array.isArray(keep) && keep.indexOf(path) >= 0 && held.indexOf(path) < 0) held.push(path)
            replies.push({ path: path, rows: [{ n: "scan" + (sent.length - 1) }] })
        } } },
        askMeta: function () {}, askThumb: function () {}, showCursorRow: function () {},
        peekKey: function (path) { return Columns.peekKey(path, false, false) }
    }
    root.ask = load("function ask(path, again", "    // Hidden view asks nothing")(root, Columns)
    root.answered = load("function answered(path)", "    // again re-asks")(root, Columns)
    var refresh = load("function refreshNeighbours()", "    // One row, only when")(root, Columns)
    var onPeeked = new Function("root", "Columns", "childColumn", "thirdSwap", "folderFallback",
        "return (" + Source.slice(area, "function onPeeked(path, hidden, total, rows, readFailed, mode, hiddenLast, first)", "\n    }\n\n    // A new listing") + ")")(root, Columns, childColumn, inert, inert)
    return {
        root: root, held: function () { return held.slice().sort().join("|") }, sent: function () { return sent.join("|") },
        // Moves the cursor to a child folder and runs the refresh the view runs for it.
        cursorOn: function (child) { root.childPath = child; refresh() },
        // Delivers the held replies in order, optionally skipping the ones for a path.
        deliver: function (skip) {
            var rest = []
            replies.forEach(function (one) { if (one.path === skip) rest.push(one); else onPeeked(one.path, false, one.rows.length, one.rows, false, 0, false, 35) })
            replies = rest
        },
        rowsOf: function (path) { var rows = root.peeked[root.peekKey(path)]; return rows ? rows.map(function (row) { return row.n }).join("|") : "" }
    }
}

// A column that leaves the drawn set and comes back before its first reply must end watched, and both replies must land.
function runReturn(check) {
    var area = Source.source("ui/ColumnsArea.qml")
    var view = columnsArea(area)
    var c = "/a/b/c", d = "/a/b/d"
    view.cursorOn(c)
    view.deliver(c)
    view.cursorOn(d)
    view.cursorOn(c)
    check("the returning column is asked again with its first ask still out", view.sent().split("|").filter(function (one) { return one === c }).length, 2)
    check("the backend then watches the column that came back", view.held().indexOf(c) >= 0, true)
    check("and no longer the one that left", view.held().indexOf(d) < 0, true)
    view.deliver("")
    check("both replies for the returning column are stored", view.rowsOf(c) !== "", true)
    check("the later reply is the one kept", view.rowsOf(c).indexOf("scan") === 0 && view.rowsOf(c) === "scan" + (view.sent().split("|").length - 1), true)
    check("a refresh with nothing moved asks nothing more", (function () { var before = view.sent(); view.cursorOn(c); return view.sent() === before })(), true)
    var calm = columnsArea(area)
    calm.cursorOn(c)
    calm.deliver("")
    calm.cursorOn(d)
    calm.deliver("")
    calm.cursorOn(c)
    check("a column that returns after its reply is asked once more", calm.sent().split("|").filter(function (one) { return one === c }).length, 2)
    check("and watched", calm.held().indexOf(c) >= 0, true)
}
