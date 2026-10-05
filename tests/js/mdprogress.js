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
    // A slow stretch beats by the clock too: a few hundred events cost seconds when the box is loaded, and the pane waits only for silence.
    var clock = 0
    var tick = 0
    MdBlocks.useClock(function () { clock += tick; return clock })
    var clocked = []
    // A heading before each paragraph writes a block at once, so the head goes out early in the rendering pass.
    for (var c = 0; c < 4 * MdBlocks.CLOCK_EVENTS; c++)
        clocked.push("# clock heading " + c, "clock line " + c + " carries ordinary words")
    var clockedSource = clocked.join("\n") + "\n"
    var still = 0
    var slow = 0
    var rendering = 0
    var headSent = false
    try {
        tick = 0
        MdBlocks.blocks(clockedSource, dir, chrome, ink, 0, undefined, function () { still++ })
        tick = MdBlocks.PROGRESS_MS
        MdBlocks.blocks(clockedSource, dir, chrome, ink, 0, undefined, function () { slow++ })
        // The head is sent from the rendering pass, so a beat after it came from that pass and not the collecting one.
        MdBlocks.blocks(clockedSource, dir, chrome, ink, 1, function () { headSent = true }, function () { if (headSent) rendering++ })
    } finally {
        MdBlocks.useClock(Date.now)
    }
    check("the clocked fixture is short of the event beat", clocked.length < MdBlocks.PROGRESS_EVENTS, true)
    check("a parse on a stopped clock never beats", still, 0)
    check("a parse whose events each cost PROGRESS_MS beats in both passes", slow >= 2, true)
    check("the rendering pass beats by the clock after its head", rendering >= 1, true)
    // A headed request is acked before any other message, a headless one never is.
    var workerSource = Source.source("ui/MarkdownWorker.js")
    var onMessage = Source.block(workerSource, "WorkerScript.onMessage = function (msg)", "ui/MarkdownWorker.js")
    function ask(msg) {
        var seen = []
        var stubWorker = { sendMessage: function (m) { seen.push(m) } }
        // The stub beats whenever it is handed a listener, so a beat the worker forwards for a headless request shows up.
        var beat = function (onProgress) { if (onProgress !== undefined) onProgress(); return [{ type: "run", text: "stub" }] }
        var stubBlocks = { blocks: function (source, dir, chrome, ink, headCount, onHead, onProgress) { return beat(onProgress) },
            sliceDue: function () { return function () { return false } },
            blockJob: function (source, dir, chrome, ink, headCount, onHead, onProgress) { return { run: function () { return beat(onProgress) } } } }
        new Function("WorkerScript", "MdBlocks", "msg", "state", onMessage.replace(/\bheld\b/g, "state.held"))(stubWorker, stubBlocks, msg, { held: null })
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
