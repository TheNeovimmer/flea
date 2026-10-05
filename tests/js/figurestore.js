.import "sourcefixture.js" as Source

// The persistent cache's own handlers on a fake process and a fake clock, so no Quickshell and no wait.
function store() {
    var source = Source.source("ui/FigureStore.qml")
    var fake = { now: 0, signals: [], writes: [], answers: [], knowns: [], starts: 0 }
    var root = { available: true, replyMs: 2000, hits: 0, misses: 0, puts: 0, exits: 0, starting: false, stopping: false,
        queued: [], outstanding: {}, owed: 0 }
    root.answered = function (id, svg) { fake.answers.push({ id: id, svg: svg }) }
    root.known = function (id, all) { fake.knowns.push({ id: id, all: all }) }
    var process = { running: false, stdinEnabled: true,
        signal: function (signal) { fake.signals.push(signal) },
        write: function (line) { fake.writes.push(JSON.parse(line)) } }
    var Date = { now: function () { return fake.now } }
    var Qt = { callLater: function () {} }
    // Sample input: readonly property int killSignal: 9.
    var constants = /readonly property int (\w+): (\d+)/g
    var constant
    while ((constant = constants.exec(source)) !== null)
        root[constant[1]] = Number(constant[2])
    function compile(args, body) {
        return new Function("root", "process", "Date", "Qt", "return function (" + args + ") {" + body + "}")(root, process, Date, Qt)
    }
    // Sample input: function ask(id, figures) {
    var functions = /\bfunction (\w+)\(([^)]*)\)\s*\{/g
    var match
    while ((match = functions.exec(source)) !== null)
        root[match[1]] = compile(match[2], Source.block(source, match[0].slice(0, -1)))
    var started = compile("", Source.block(source, "onStarted:"))
    var runningChanged = compile("", Source.block(source, "onRunningChanged:"))
    var exited = compile("", Source.block(source, "onExited:"))
    fake.tick = compile("", Source.block(source.substring(source.indexOf("Timer {")), "onTriggered:"))
    fake.start = function () {
        process.running = true
        fake.starts++
        started()
    }
    fake.exit = function () {
        process.running = false
        runningChanged()
        exited()
    }
    fake.reply = function (message) { root.receive(JSON.stringify(message)) }
    fake.root = root
    fake.process = process
    return fake
}

function run(check) {
    var key = "math\n#101315|#c0caf5|||||||monospace|14|7|0|0\ntrue\nx^2"
    var fake = store()
    fake.root.ask(7, [key])
    fake.start()
    check("a known query is owed a reply, counted by a property the reply timer can bind", fake.root.owed, 1)
    check("an idle stop is refused while a reply is owed", fake.root.stop(), false)
    check("the refused stop neither kills the store nor closes its stdin", fake.signals.length === 0 && fake.process.running && fake.process.stdinEnabled && !fake.root.stopping, true)
    fake.reply({ id: 7, known: true })
    check("the owed reply still lands after the refused stop", fake.knowns.length === 1 && fake.knowns[0].all === true && fake.root.owed === 0 && fake.root.available, true)

    check("with nothing owed the stop is accepted", fake.root.stop(), true)
    check("it closes stdin and leaves the store running to drain, never a kill", fake.process.stdinEnabled === false && fake.process.running && fake.signals.length === 0, true)
    fake.exit()
    check("the exit at EOF after a stop is no failure", fake.root.available && fake.root.exits === 1 && !fake.root.stopping, true)

    fake = store()
    fake.root.put(key, "<svg/>")
    fake.start()
    check("a put is written to the store", fake.writes.length === 1 && fake.writes[0].op === "put" && fake.root.puts === 1, true)
    check("a put has no reply, so a stop right after it is accepted", fake.root.stop(), true)
    check("the stop drains the put by closing stdin instead of killing the store", fake.process.running && fake.process.stdinEnabled === false && fake.signals.length === 0, true)
    fake.root.get(8, key)
    check("a line sent while the store drains waits for the next store", fake.writes.length === 1 && fake.root.queued.length === 1 && fake.root.owed === 1, true)
    fake.exit()
    check("the exit starts the store again for the queued line, with stdin open", fake.root.starting && fake.process.running && fake.process.stdinEnabled, true)
    fake.start()
    check("the queued get reaches the new store", fake.writes.length === 2 && fake.writes[1].op === "get" && fake.root.available, true)

    fake = store()
    fake.root.get(9, key)
    fake.start()
    fake.now = fake.root.replyMs + 1
    fake.tick()
    check("a reply later than replyMs ends the store and falls to the helper as a miss", fake.root.available === false && fake.answers.length === 1 && fake.answers[0].svg === "" && fake.root.owed === 0, true)
    check("the late store is killed", fake.signals.length === 1 && fake.signals[0] === fake.root.killSignal, true)
    fake = store()
    fake.root.get(10, key)
    fake.start()
    fake.now = fake.root.replyMs - 1
    fake.tick()
    check("a reply inside replyMs is waited for", fake.root.available === true && fake.answers.length === 0, true)

    fake = store()
    fake.root.ask(11, [key])
    fake.start()
    var threw = false
    try {
        fake.root.receive("null")
        fake.root.receive("not json")
    } catch (e) {
        threw = true
    }
    check("a null or garbled line from the store is ignored", threw === false && fake.root.owed === 1 && fake.root.available, true)
}
