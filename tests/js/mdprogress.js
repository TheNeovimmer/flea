.import "../../ui/js/MdBlocks.js" as MdBlocks
.import "sourcefixture.js" as Source

// The parse heartbeat proofs: both block passes beat, and a headed worker request is acked first.
function run(check) {
    var dir = "/doc"
    var chrome = "#181825"
    var ink = "#c0caf5"
    // Each plain line sends one line event per pass, so this many lines beats several times whatever PROGRESS_EVENTS is.
    var beatsWanted = 3
    var wanted = beatsWanted * MdBlocks.PROGRESS_EVENTS
    var lines = []
    for (var i = 0; i < wanted; i++)
        lines.push("progress line " + i + " carries ordinary words")
    var source = lines.join("\n") + "\n"
    var sent = source.split("\n").length
    var floor = Math.floor(sent / MdBlocks.PROGRESS_EVENTS)
    check("the fixture is long enough to beat", floor >= beatsWanted, true)
    var beats = 0
    var parsed = MdBlocks.blocks(source, dir, chrome, ink, 0, undefined, function () { beats++ })
    check("a parse beats at least once per PROGRESS_EVENTS line events", beats >= floor, true)
    check("the collecting pass beats too", beats >= 2 * floor, true)
    check("the beating parse still lands its blocks", parsed.length > 0, true)
    var landed = MdBlocks.blocks(source, dir, chrome, ink, 0, undefined)
    check("no listener means no heartbeat and no throw", landed.length === parsed.length, true)
    // A headed request is acked before any other message, a headless one never is.
    var workerSource = Source.source("ui/MarkdownWorker.js")
    var onMessage = Source.block(workerSource, "WorkerScript.onMessage = function (msg)", "ui/MarkdownWorker.js")
    function ask(msg) {
        var seen = []
        var stubWorker = { sendMessage: function (m) { seen.push(m) } }
        // The stub beats whenever it is handed a listener, so a beat the worker forwards for a headless request shows up.
        var stubBlocks = { blocks: function (source, dir, chrome, ink, headCount, onHead, onProgress) { if (onProgress !== undefined) onProgress(); return [{ type: "run", text: "stub" }] } }
        new Function("WorkerScript", "MdBlocks", "msg", onMessage)(stubWorker, stubBlocks, msg)
        return seen
    }
    var headed = ask({ seq: 7, source: "hi", dir: dir, chrome: chrome, ink: ink, head: 96 })
    check("a headed request is acked before any other message", headed.length > 0 && headed[0].ack === true && headed[0].seq === 7, true)
    var headless = ask({ seq: 8, source: "hi", dir: dir, chrome: chrome, ink: ink })
    var acked = headless.filter(function (m) { return m.ack === true })
    check("a headless request is never acked", acked.length, 0)
    check("a headed request forwards the parse's beats", headed.filter(function (m) { return m.progress === true && m.seq === 7 }).length, 1)
    check("a headless request never beats", headless.filter(function (m) { return m.progress === true }).length, 0)
}
