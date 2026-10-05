.import "sourcefixture.js" as Source
.import "figureserviceexit.js" as ExitSuite
.import "figureservicedisk.js" as DiskSuite

function block(source, marker, file) {
    return Source.block(source, marker, file)
}

function service() {
    var source = Source.source("ui/FigureService.qml")
    var fake = { now: 0, deferred: [], answers: [], writes: [], sent: [], kills: [], starts: 0 }
    var root = { available: true, starting: false, stopping: false, generation: 0,
        helperExits: 0, deadlineExpirations: 0,
        seq: 0, sends: 0, workerAnswers: 0, cacheMax: 64, renderMs: 1000,
        waiting: {}, answerCache: {}, answerOrder: [], pending: [], written: [], killSignal: 9 }
    root.done = function (id, svg, error) { fake.answers.push({ id: id, svg: svg, error: error }) }
    root.sent = function (id, source) { fake.sent.push({ id: id, source: source }) }
    var helper = { running: false,
        signal: function (signal) { fake.kills.push({ signal: signal, generation: root.generation }) },
        write: function (line) { fake.writes.push(JSON.parse(line)) } }
    function timer() {
        return { running: false, start: function () { this.running = true },
            restart: function () { this.running = true }, stop: function () { this.running = false } }
    }
    var deadlineTimer = timer()
    var idleTimer = timer()
    // The persistent cache stands off by default, so every case below meets the helper alone.
    var disk = { available: false, active: false, stopping: false, refuse: false, gets: [], puts: [], asks: [], stops: 0,
        stop: function () { this.stops++; if (this.refuse) return false; this.stopping = true; return true },
        get: function (id, key) { this.gets.push({ id: id, key: key }) }, put: function (key, svg) { this.puts.push({ key: key, svg: svg }) },
        ask: function (id, keys) { this.asks.push({ id: id, keys: keys }) } }
    fake.disk = disk
    fake.idleTimer = idleTimer
    var Qt = { callLater: function (callback) { fake.deferred.push(callback) } }
    var Date = { now: function () { return fake.now } }
    // Sample input: readonly property int killSignal: 9.
    var constants = /readonly property int (\w+): (\d+)/g
    var constant
    while ((constant = constants.exec(source)) !== null)
        root[constant[1]] = Number(constant[2])
    function compile(args, body) {
        return new Function("root", "helper", "deadlineTimer", "idleTimer", "Qt", "Date", "disk",
            "return function (" + args + ") {" + body + "}")(root, helper, deadlineTimer, idleTimer, Qt, Date, disk)
    }
    // Sample input: function cacheKeyOf(kind, source, t, display) {
    var functions = /\bfunction (\w+)\(([^)]*)\)\s*\{/g
    var match
    while ((match = functions.exec(source)) !== null)
        root[match[1]] = compile(match[2], block(source, match[0].slice(0, -1), "ui/FigureService.qml"))
    fake.tick = compile("", block(source.substring(source.indexOf("id: deadlineTimer")), "onTriggered:", "ui/FigureService.qml"))
    fake.idle = compile("", block(source.substring(source.indexOf("id: idleTimer")), "onTriggered:", "ui/FigureService.qml"))
    var started = compile("", block(source, "onStarted:", "ui/FigureService.qml"))
    var runningChanged = compile("", block(source, "onRunningChanged:", "ui/FigureService.qml"))
    var exited = compile("exitCode, exitStatus", block(source, "onExited:", "ui/FigureService.qml"))
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
    var harness = Source.source("tests/markdown-figures.qml")
    function idleProbe(running, exits) {
        var shell = { awaitSource: "fresh", afterAwait: 5, step: 4, helperExitsMark: 0,
            idleExitWaitStart: 0, idleExitBoundMs: 5000, awaitTimerStop: false,
            idleExitWait: { stop: function () {} },
            results: [], asked: [], finished: [],
            check: function (passed) { this.results.push(passed) },
            askFresh: function (source) { this.asked.push(source) },
            finish: function (status) { this.finished.push(status) } }
        var Flea = { FigureService: { helperRunning: running, helperExits: exits } }
        var Date = { now: function () { return 0 } }
        new Function("shell", "Flea", "Date", block(harness, "function drive()", "tests/markdown-figures.qml"))(shell, Flea, Date)
        return shell
    }
    var idle = idleProbe(false, 1)
    check("idle harness observes the helper exit event", idle.results[0], true)
    check("observed idle exit allows the next ask", idle.asked.length, 1)
    idle = idleProbe(false, 0)
    check("running false without an exit event does not advance the idle phase", idle.asked.length, 0)
    var hasWaitEvent = harness.indexOf("function idleWaitExpired()") >= 0
    check("idle wait failure is driven by its timer event", hasWaitEvent, true)
    if (hasWaitEvent) {
        idle = idleProbe(true, 0)
        var Flea = { FigureService: { helperRunning: true, helperExits: 0 } }
        new Function("shell", "Flea", block(harness, "function idleWaitExpired()", "tests/markdown-figures.qml"))(idle, Flea)
        check("idle wait event fails a helper with no observed exit", idle.results[0], false)
        check("idle wait failure ends the harness immediately", idle.finished.length, 1)
        check("idle wait failure sends no new request", idle.asked.length, 0)
    }
    function exitProbe(deadlines, exits) {
        var shell = { ticket: 1, step: 14, renderDeadlineMark: 0, helperExitsMark: 0,
            crashingHelperExitCount: 2,
            exitAskedAt: 0, exitAnswerBoundMs: 2000, results: [],
            check: function (passed) { this.results.push(passed) },
            writePhase: function () {} }
        var Flea = { FigureService: { available: true, deadlineExpirations: deadlines, helperExits: exits } }
        var Date = { now: function () { return 0 } }
        new Function("shell", "Flea", "Date", "ticket", "svg", "error", block(harness, "else if (shell.step === 14)", "tests/markdown-figures.qml"))(
            shell, Flea, Date, 1, "", "figure engine exited 42 (status 0)")
        return shell.results
    }
    var exitChecks = exitProbe(1, 0)
    check("exit harness rejects a deadline event even when the clock reads zero", exitChecks[1], false)
    check("exit harness rejects an answer without the helper exit event", exitChecks[2], false)
    exitChecks = exitProbe(0, 2)
    check("exit harness accepts an answer before the deadline event", exitChecks[1], true)
    check("exit harness accepts the observed helper exit", exitChecks[2], true)
    check("exit harness rejects one exit before the failed head's answer", exitProbe(0, 1)[2], false)
    check("exit harness rejects a third exit before the failed head's answer", exitProbe(0, 3)[2], false)

    var deadlineMs = 1000
    var staggerMs = 100
    var afterDeadlineMs = 1
    var fake = service()
    var absent = fake.ask("answered outside written", true)
    fake.start()
    fake.root.written = []
    var lastWritten = fake.ask("last written still waiting", true)
    fake.reply(absent, "absent svg")
    check("an answer absent from written keeps the last written ticket", fake.root.written[0], lastWritten)
    check("the absent written ticket still answers its own request", fake.answers[0].id, absent)
    fake.now = deadlineMs + afterDeadlineMs
    fake.tick()
    check("the last written ticket keeps its deadline turn", fake.answers.some(function (answer) {
        return answer.id === lastWritten && answer.error === "render timed out"
    }), true)

    fake = service()
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

    fake = service()
    fake.root.store("math", "hot A", theme(), true, "A svg")
    for (var i = 0; i < fake.root.cacheMax; i++) {
        fake.ask("hot A", true)
        fake.flush()
        fake.root.store("math", "cold " + i, theme(), true, "cold svg")
    }
    var writesBeforeRevisit = fake.writes.length
    var revisit = fake.ask("hot A", true)
    fake.start()
    fake.flush()
    check("LRU keeps A hit before each of 64 other stores", fake.answers.some(function (answer) {
        return answer.id === revisit && answer.svg === "A svg"
    }), true)
    check("LRU revisit writes no helper line", fake.writes.length - writesBeforeRevisit, 0)

    ExitSuite.run(check, service)
    DiskSuite.run(check, service)

    fake = service()
    var a = fake.ask("A", true)
    fake.start()
    fake.now = staggerMs
    var b = fake.ask("B", true)
    fake.now = deadlineMs + afterDeadlineMs
    fake.tick()
    check("A deadline fails only A", fake.answers.length, 1)
    check("A deadline keeps B waiting for resend", fake.root.waiting[b] !== undefined, true)
    check("A deadline names timeout", fake.answers[0].error, "render timed out")
    fake.tick()
    check("repeated deadline ticks kill the helper only once", fake.kills.length, 1)
    fake.reply(a, "late A")
    check("a killed generation cannot cache a late answer", fake.root.cached("math", "A", theme(), true), undefined)
    fake.exit(9)
    fake.start()
    check("B is resent once after A's kill", fake.writes.filter(function (line) { return line.id === b }).length, 2)
    check("poison A is never resent", fake.writes.filter(function (line) { return line.id === a }).length, 1)
    fake.now = deadlineMs + staggerMs + afterDeadlineMs
    fake.tick()
    check("B gets a fresh turn after resend", fake.kills.length, 1)
    fake.reply(b, "B svg")
    check("B answers after A times out", fake.answers[fake.answers.length - 1].svg, "B svg")

    fake = service()
    var slow = fake.ask("slow figure", true)
    fake.now = deadlineMs + afterDeadlineMs
    fake.tick()
    check("waiting for helper start spends no render deadline", fake.answers.length, 0)
    fake.start()
    var queuedCount = 10
    var formulas = []
    for (var i = 0; i < queuedCount; i++)
        formulas.push(fake.ask("formula " + i, true))
    check("queued formulas have no running deadlines", formulas.every(function (id) { return fake.root.waiting[id].deadline === 0 }), true)
    fake.now += deadlineMs + afterDeadlineMs
    fake.tick()
    check("one slow figure fails only itself ahead of ten formulas", fake.answers.length, 1)
    fake.exit(9)
    fake.start()
    for (var i = 0; i < formulas.length; i++) {
        fake.now += deadlineMs - staggerMs
        fake.tick()
        fake.reply(formulas[i], "formula svg " + i)
    }
    check("all ten queued formulas answer on their own turns", fake.answers.filter(function (answer) { return answer.svg !== "" }).length, queuedCount)
    check("each queued formula is resent exactly once per kill", formulas.every(function (id) {
        return fake.writes.filter(function (line) { return line.id === id }).length === 2
    }), true)
    check("ten queued turns cause no extra timeout", fake.kills.length, 1)

    fake = service()
    var firstSlow = fake.ask("first slow", true)
    fake.start()
    var secondSlow = fake.ask("second slow", true)
    var healthy = fake.ask("healthy", true)
    fake.now += deadlineMs + afterDeadlineMs
    fake.tick()
    fake.exit(9)
    fake.start()
    fake.now += deadlineMs + afterDeadlineMs
    fake.tick()
    check("a second slow figure fails only itself", fake.answers.length, 2)
    check("second timeout names its own ticket", fake.answers[fake.answers.length - 1].id, secondSlow)
    fake.exit(9)
    fake.start()
    fake.reply(healthy, "healthy svg")
    check("healthy ticket survives both slow figures", fake.answers[fake.answers.length - 1].svg, "healthy svg")
    check("healthy ticket is resent once for each kill", fake.writes.filter(function (line) { return line.id === healthy }).length, 3)
    check("first poison is never resent", fake.writes.filter(function (line) { return line.id === firstSlow }).length, 1)
    check("second poison stops after its own timeout", fake.writes.filter(function (line) { return line.id === secondSlow }).length, 2)

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
