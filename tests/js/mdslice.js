.import "../../ui/js/MdBlocks.js" as MdBlocks
.import "sourcefixture.js" as Source

// A parse run in slices answers what the whole parse answers, and the worker reads a newer request between two slices.
function run(check) {
    var dir = "/doc"
    var chrome = "#181825"
    var ink = "#c0caf5"
    // One of each construct that carries state across lines: containers, lazy lines, fences, tables, references, notes, front matter, math and setext.
    var piece = ["# Head {n}", "", "A paragraph {n} with [a ref][r{n}] and a note[^n{n}].", "lazy line", "", "> quote {n}", "> - item", ">   nested",
        "continues lazily", "", "- one", "  - two", "    - three {n}", "", "```sh", "echo {n}", "```", "", "| a | b |", "| - | - |", "| {n} | 2 |", "",
        "Setext {n}", "===", "", "$$x^{n}$$", "", "[r{n}]: http://example.invalid/{n}", "[^n{n}]: the note {n}", ""]
    var lines = ["---", "title: slice", "---"]
    for (var n = 0; n < 12; n++)
        lines = lines.concat(piece.map(function (line) { return line.replace(/\{n\}/g, String(n)) }))
    var source = lines.join("\n") + "\n"
    var whole = JSON.stringify(MdBlocks.blocks(source, dir, chrome, ink, 0, undefined))
    var everies = [1, 3, 17]
    var slices = 0
    var same = true
    var heads = 0
    for (var e = 0; e < everies.length; e++) {
        var job = MdBlocks.blockJob(source, dir, chrome, ink, 4, function () { heads++ }, undefined)
        var answer = null
        var guard = 0
        // Each slice gets its own budget of lines, so every slice goes on from where the last one stopped.
        while (answer === null && guard++ < 10000) {
            var used = 0
            var every = everies[e]
            answer = job.run(function () { return used++ >= every })
            slices++
        }
        same = same && answer !== null && JSON.stringify(answer) === whole
    }
    check("a parse run in slices of 1, 3 and 17 lines answers the whole parse's blocks", same, true)
    check("the slices were many", slices > 100, true)
    check("each sliced parse sent its head once", heads, everies.length)
    var deepSource = new Array(MdBlocks.NESTING_LIMIT + 3).join("> ") + "deep\n" + source
    var deepJob = MdBlocks.blockJob(deepSource, dir, chrome, ink, 0, undefined, undefined)
    var deepAnswer = null
    while (deepAnswer === null) {
        var spent = 0
        deepAnswer = deepJob.run(function () { return spent++ >= 2 })
    }
    check("a sliced parse of a too deep document answers the sentinel", deepAnswer.length === 1 && deepAnswer[0].type === "deep", true)
    // The worker: a headed request runs one slice per message, and a newer request or a cancel drops the held parse.
    var workerSource = Source.source("ui/MarkdownWorker.js")
    var onMessage = Source.block(workerSource, "WorkerScript.onMessage = function (msg)", "ui/MarkdownWorker.js")
    var seen = []
    var stubWorker = { sendMessage: function (m) { seen.push(m) } }
    var stubBlocks = {
        sliceDue: function () { return function () { return false } },
        blockJob: function (source, dir, chrome, ink, headCount, onHead, onProgress) {
            var left = 2
            return { run: function () { return left-- > 0 ? null : [{ type: "run", text: source }] } }
        }
    }
    var step = new Function("WorkerScript", "MdBlocks", "msg", "state", onMessage.replace(/\bheld\b/g, "state.held"))
    var state = { held: null }
    function send(msg) { seen = []; step(stubWorker, stubBlocks, msg, state); return seen }
    var first = send({ seq: 3, source: "one", dir: dir, chrome: chrome, ink: ink, head: 96 })
    check("a headed request is acked, then answers a slice and no reply", first.length === 2 && first[0].ack === true && first[1].yielded === true && first[1].seq === 3, true)
    check("a continue for the held request runs its next slice", send({ seq: 3, cont: true }).map(function (m) { return m.yielded === true }).join(), "true")
    var done = send({ seq: 3, cont: true })
    check("the last slice answers the whole parse", done.length === 1 && done[0].seq === 3 && done[0].blocks[0].text === "one" && done[0].yielded === undefined, true)
    check("a continue after the parse is done is ignored", send({ seq: 3, cont: true }).length, 0)
    send({ seq: 4, source: "two", dir: dir, chrome: chrome, ink: ink, head: 96 })
    send({ seq: 5, source: "three", dir: dir, chrome: chrome, ink: ink, head: 96 })
    check("a newer request replaces the held parse, so the old seq's continue is ignored", send({ seq: 4, cont: true }).length, 0)
    check("the newer request's continue runs", send({ seq: 5, cont: true }).length, 1)
    send({ seq: 6, cont: true })
    send({ seq: 7, source: "four", dir: dir, chrome: chrome, ink: ink, head: 96 })
    send({ seq: 7, cancel: true })
    check("a cancel drops the held parse", send({ seq: 7, cont: true }).length, 0)
    stubBlocks.blockJob = function () { throw new Error("probe parse fault") }
    var thrown = send({ seq: 8, source: "five", dir: dir, chrome: chrome, ink: ink, head: 96 })
    check("a job that throws on construction answers one error reply after the ack",
        thrown.length === 2 && thrown[0].ack === true && thrown[1].seq === 8 && thrown[1].blocks.length === 0 && /probe parse fault/.test(thrown[1].error), true)
    check("a continue after a construction error is ignored", send({ seq: 8, cont: true }).length, 0)
    // The real slice test on a stepped clock: it asks the clock only every CLOCK_EVENTS calls, and answers true once SLICE_MS has also passed.
    var now = 0
    var tickMs = 0
    MdBlocks.useClock(function () { now += tickMs; return now })
    try {
        tickMs = MdBlocks.SLICE_MS
        var due = MdBlocks.sliceDue(MdBlocks.SLICE_MS)
        var early = false
        for (var k = 1; k < MdBlocks.CLOCK_EVENTS; k++)
            early = early || due()
        check("a slice is never due before CLOCK_EVENTS calls, whatever the clock says", early, false)
        check("a slice is due at CLOCK_EVENTS calls once the clock passed SLICE_MS", due(), true)
        tickMs = 0
        var idle = MdBlocks.sliceDue(MdBlocks.SLICE_MS)
        var late = false
        for (var m = 0; m < 3 * MdBlocks.CLOCK_EVENTS; m++)
            late = late || idle()
        check("a slice is not due while the clock stands still", late, false)
        tickMs = MdBlocks.SLICE_MS
        var stopped = 0
        var resumed = MdBlocks.blockJob(source, dir, chrome, ink, 0, undefined, undefined)
        var finished = null
        while (finished === null && stopped < 10000) {
            finished = resumed.run(MdBlocks.sliceDue(MdBlocks.SLICE_MS))
            if (finished === null)
                stopped++
        }
        check("a job on the real slice test stops more than once and resumes to the whole parse", stopped > 1 && JSON.stringify(finished) === whole, true)
    } finally {
        MdBlocks.useClock(Date.now)
    }
}
