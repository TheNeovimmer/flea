.import "sourcefixture.js" as Source

// Sample input: function ask(kind, source, display, theme) { ... } or onExited: function (...) { ... }.
function block(source, marker) {
    var at = source.indexOf(marker)
    if (at < 0)
        throw new Error("figureservice: missing " + marker)
    var begin = source.indexOf("{", at + marker.length)
    var depth = 1
    var quote = ""
    var comment = false
    var i = begin + 1
    for (; i < source.length && depth > 0; i++) {
        var ch = source.charAt(i)
        if (comment) {
            if (ch === "\n")
                comment = false
        } else if (quote !== "") {
            if (ch === "\\")
                i++
            else if (ch === quote)
                quote = ""
        } else if (ch === "/" && source.charAt(i + 1) === "/") {
            comment = true
        } else if (ch === '"' || ch === "'") {
            quote = ch
        } else if (ch === "{") {
            depth++
        } else if (ch === "}") {
            depth--
        }
    }
    if (begin < 0 || depth !== 0)
        throw new Error("figureservice: unterminated " + marker)
    return source.substring(begin + 1, i - 1)
}

function service() {
    var source = Source.source("ui/FigureService.qml")
    var fake = { now: 0, deferred: [], answers: [], writes: [], kills: [], starts: 0 }
    var root = { available: true, starting: false, stopping: false, generation: 0,
        seq: 0, sends: 0, workerAnswers: 0, cacheMax: 64, renderMs: 1000,
        waiting: {}, answerCache: {}, answerOrder: [], pending: [] }
    root.done = function (id, svg, error) { fake.answers.push({ id: id, svg: svg, error: error }) }
    var helper = { running: false,
        signal: function (signal) { fake.kills.push({ signal: signal, generation: root.generation }) },
        write: function (line) { fake.writes.push(JSON.parse(line)) } }
    function timer() {
        return { running: false, start: function () { this.running = true },
            restart: function () { this.running = true }, stop: function () { this.running = false } }
    }
    var deadlineTimer = timer()
    var idleTimer = timer()
    var Qt = { callLater: function (callback) { fake.deferred.push(callback) } }
    var Date = { now: function () { return fake.now } }
    function compile(args, body) {
        return new Function("root", "helper", "deadlineTimer", "idleTimer", "Qt", "Date",
            "return function (" + args + ") {" + body + "}")(root, helper, deadlineTimer, idleTimer, Qt, Date)
    }
    var functions = /\bfunction (\w+)\(([^)]*)\)\s*\{/g
    var match
    while ((match = functions.exec(source)) !== null)
        root[match[1]] = compile(match[2], block(source, match[0].slice(0, -1)))
    fake.tick = compile("", block(source.substring(source.indexOf("id: deadlineTimer")), "onTriggered:"))
    var started = compile("", block(source, "onStarted:"))
    var runningChanged = compile("", block(source, "onRunningChanged:"))
    var exited = compile("exitCode, exitStatus", block(source, "onExited:"))
    fake.start = function () {
        helper.running = true
        fake.starts++
        started()
    }
    fake.exit = function (code) {
        helper.running = false
        runningChanged()
        exited(code, 0)
    }
    fake.flush = function () {
        while (fake.deferred.length > 0)
            fake.deferred.shift()()
    }
    fake.ask = function (source, display) { return root.ask("math", source, !!display, theme()) }
    fake.reply = function (id, svg) { root.receive(JSON.stringify({ id: id, svg: svg })) }
    fake.root = root
    fake.helper = helper
    return fake
}

function theme() {
    return { bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 14 }
}

function run(check) {
    var deadlineMs = 1000
    var staggerMs = 100
    var afterDeadlineMs = 1
    var fake = service()
    var inline = fake.ask("\\sum_{n=1}^3 n", false)
    fake.start()
    fake.reply(inline, "inline svg")
    var display = fake.ask("\\sum_{n=1}^3 n", true)
    fake.flush()
    check("display of the same source reaches the helper separately", fake.writes.length, 2)
    fake.reply(display, "display svg")
    fake.ask("\\sum_{n=1}^3 n", false)
    fake.flush()
    check("inline revisit keeps its inline answer", fake.answers[fake.answers.length - 1].svg, "inline svg")
    fake.ask("\\sum_{n=1}^3 n", true)
    fake.flush()
    check("display revisit keeps its display answer", fake.answers[fake.answers.length - 1].svg, "display svg")
    check("both cache hits write no helper line", fake.writes.length, 2)

    var exitCodes = [0, 1, 42, 127]
    for (var i = 0; i < exitCodes.length; i++) {
        fake = service()
        fake.ask("exit first", true)
        fake.start()
        fake.ask("exit second", true)
        fake.exit(exitCodes[i])
        check("exit " + exitCodes[i] + " fails every ticket immediately", fake.answers.length, 2)
        check("exit " + exitCodes[i] + " clears waiting", Object.keys(fake.root.waiting).length, 0)
        check("exit " + exitCodes[i] + " names its status", fake.answers.length > 0
            && fake.answers[0].error.indexOf(String(exitCodes[i])) >= 0, true)
        check("only 127 latches unavailable", fake.root.available, exitCodes[i] !== 127)
    }

    fake = service()
    var a = fake.ask("A", true)
    fake.start()
    fake.now = staggerMs
    var b = fake.ask("B", true)
    fake.now = deadlineMs + afterDeadlineMs
    fake.tick()
    check("A deadline fails A and B together", fake.answers.length, 2)
    check("A deadline removes B immediately", fake.root.waiting[b] === undefined, true)
    check("A deadline names timeout", fake.answers[0].error, "render timed out")
    fake.reply(a, "late A")
    check("a killed generation cannot cache a late answer", fake.root.cached("math", "A", theme(), true), undefined)
    fake.exit(9)
    var c = fake.ask("C", true)
    fake.start()
    fake.now = deadlineMs + staggerMs + afterDeadlineMs
    fake.tick()
    check("B's former deadline cannot kill C", fake.kills.length, 1)
    check("C remains waiting on its fresh generation", fake.root.waiting[c] !== undefined, true)
    check("C records the generation it was sent to", fake.root.waiting[c].generation, fake.root.generation)
    fake.reply(c, "C svg")
    check("C answers normally after B's former deadline", fake.answers[fake.answers.length - 1].svg, "C svg")

    fake = service()
    fake.ask("old helper", true)
    fake.start()
    fake.now = deadlineMs + afterDeadlineMs
    fake.tick()
    var next = fake.ask("during stopping", true)
    check("a kill leaves the helper marked stopping", fake.root.stopping, true)
    check("an ask during stopping never writes to the dying process", fake.writes.length, 1)
    fake.exit(9)
    check("the exit starts a helper for the queued ask", fake.root.starting, true)
    fake.start()
    check("the fresh helper gets the queued request exactly once", fake.writes.length, 2)
    check("the fresh helper gets the new ticket", fake.writes[fake.writes.length - 1].id, next)
    fake.reply(next, "fresh svg")
    check("the queued ask answers from the fresh helper", fake.answers[fake.answers.length - 1].svg, "fresh svg")
}
