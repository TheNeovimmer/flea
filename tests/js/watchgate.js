.import "sourcefixture.js" as Source

// The shipped go-step of tests/watch-views.qml run over a stub window, so a peek reply that replaces the cache but keeps an old entry is a sequence here.
function run(check) {
    var src = Source.source("tests/watch-views.qml")
    var code = Source.slice(src, "function begin(index)", "    FloatingWindow {")
    var open = "/r/parent/open", sub = open + "/sub"
    var scene = function () {
        var clock = 1000, started = [], logs = []
        var key = function (path) { return path + "|h" }
        var area = { peeked: ({}), peekKey: key, answered: function (path) { return area.peeked[key(path)] !== undefined } }
        var pane = { columnsArea: area, path: open, total: 4, listInFlight: false, listingState: "ready", open: function (path) { pane.path = path } }
        var root = {
            mode: "columns", open: open, stale: 0, stepBudgetMs: 8000, stepIndex: -1, stepStarted: 0, finish: function () {},
            steps: [{ label: "enter-child", go: sub }, { label: "after", args: ["create", sub + "/x.txt"], shown: function () { return [] } }],
            holds: function () { return true }, pane: function () { return pane }
        }
        var make = new Function("root", "body", "outsideProcess", "Quickshell", "Date", "console", code + "; return { begin: begin, advance: advance }")
        var fns = make(root, { item: {} }, { createObject: function (parent, props) { started.push(props.command.join(" ")) } },
            { env: function () { return "outside" } }, { now: function () { return clock } }, { log: function (line) { logs.push(line) } })
        root.begin = fns.begin
        return {
            root: root, area: area, pane: pane, key: key, started: function () { return started.length }, logs: logs, advance: fns.advance,
            tick: function (ms) { clock += ms }
        }
    }
    var oldRows = [{ n: "before" }], freshRows = [{ n: "after" }]

    // A reply for the folder just left replaces the cache object but carries the awaited entry forward untouched.
    var held = scene()
    held.area.peeked[held.key(open)] = oldRows
    held.root.begin(0)
    held.area.peeked = (function () { var next = {}; next[held.key(open)] = oldRows; return next })()
    held.advance()
    check("a replaced cache holding the old awaited entry does not end the move", held.started(), 0)
    var next = {}
    next[held.key(open)] = freshRows
    held.area.peeked = next
    held.advance()
    check("a new entry for the awaited neighbour ends it", held.started(), 1)

    // The cache cleared by the move and answered afresh is the ordinary path.
    var clean = scene()
    clean.area.peeked[clean.key(open)] = oldRows
    clean.root.begin(0)
    clean.area.peeked = ({})
    clean.advance()
    check("an empty cache after the move waits for the answer", clean.started(), 0)
    var landed = {}
    landed[clean.key(open)] = freshRows
    clean.area.peeked = landed
    clean.advance()
    check("and the answer ends the wait", clean.started(), 1)

    // A reply for some other folder never satisfies the wait for the awaited one.
    var other = scene()
    other.area.peeked[other.key(open)] = oldRows
    other.root.begin(0)
    var elsewhere = {}
    elsewhere[other.key(open)] = oldRows
    elsewhere[other.key("/r/elsewhere")] = freshRows
    other.area.peeked = elsewhere
    other.advance()
    check("a fresh entry for another folder does not end the move", other.started(), 0)

    // No answer at all runs out the budget and is counted stale, never passed.
    var silent = scene()
    silent.area.peeked[silent.key(open)] = oldRows
    silent.root.begin(0)
    silent.area.peeked = (function () { var kept = {}; kept[silent.key(open)] = oldRows; return kept })()
    silent.tick(silent.root.stepBudgetMs + 1)
    silent.advance()
    check("a move with no new answer counts as stale", silent.root.stale, 1)
    check("and says so", silent.logs.length === 1 && silent.logs[0].indexOf("STALE") >= 0, true)

    // The climb back awaits the child column the same way.
    var climb = scene()
    climb.root.steps = [{ label: "climb-back", go: open }, { label: "after", args: ["create", sub + "/y.txt"], shown: function () { return [] } }]
    climb.pane.path = sub
    climb.area.peeked[climb.key(sub)] = oldRows
    climb.root.begin(0)
    climb.area.peeked = (function () { var kept = {}; kept[climb.key(sub)] = oldRows; return kept })()
    climb.advance()
    check("the climb back does not end on the old child entry", climb.started(), 0)
    var child = {}
    child[climb.key(sub)] = freshRows
    climb.area.peeked = child
    climb.advance()
    check("and ends on a new one", climb.started(), 1)
}
