// Drive unexpected exits through the production handlers without a running helper or a clock wait.
function run(check, service) {
    var cumulativeCpuExit = 137
    var crashExit = 42
    var refusalExit = 127
    var fake = service()
    var first = fake.ask("innocent first", true)
    fake.start()
    var second = fake.ask("innocent second", true)
    fake.exit(cumulativeCpuExit)
    check("one CPU-cap exit fails no innocent written ticket", fake.answers.length, 0)
    fake.start()
    fake.reply(first, "first svg")
    fake.reply(second, "second svg")
    check("both innocent written tickets render after exit 137", fake.answers.filter(function (a) {
        return a.svg !== ""
    }).length, 2)
    check("one unexpected exit resends each innocent ticket once", fake.writes.length, 4)

    fake = service()
    var poison = fake.ask("crashes the helper", true)
    fake.start()
    var neighbour = fake.ask("innocent neighbour", true)
    var tail = fake.ask("innocent tail", true)
    fake.exit(crashExit)
    check("the first head strike answers no ticket", fake.answers.length, 0)
    fake.start()
    fake.exit(crashExit)
    check("two head strikes fail only the crashing ticket", fake.answers.length, 1)
    check("the second strike names the poison ticket and exit", fake.answers.length === 1
        && fake.answers[0].id === poison && fake.answers[0].error.indexOf("exited 42") >= 0, true)
    fake.start()
    fake.reply(neighbour, "neighbour svg")
    fake.reply(tail, "tail svg")
    check("both neighbours render after the poison fails", fake.answers.filter(function (a) {
        return a.svg !== ""
    }).length, 2)
    check("the failed poison never returns", fake.writes.filter(function (w) {
        return w.id === poison
    }).length, 2)
    check("an unexpected exit keeps the service available", fake.root.available, true)

    fake = service()
    fake.ask("refused first", true)
    fake.start()
    fake.ask("refused second", true)
    fake.exit(refusalExit)
    check("127 still fails every written ticket", fake.answers.length, 2)
    check("127 still clears waiting", Object.keys(fake.root.waiting).length, 0)
    check("127 still latches unavailable", fake.root.available, false)

    var pastDeadlineMs = 1
    fake = service()
    var overdue = fake.ask("overdue head", true)
    fake.start()
    var survivor = fake.ask("survivor of the kill", true)
    fake.now = fake.root.renderMs + pastDeadlineMs
    fake.tick()
    check("the service's own kill charges its neighbour no strike", fake.root.waiting[survivor].strikes, 0)
    fake.exit(cumulativeCpuExit)
    fake.start()
    fake.exit(crashExit)
    check("a neighbour of a timed-out head survives its first crash", fake.answers.length, 1)
    check("only the overdue head answered, by its deadline", fake.answers[0].id === overdue
        && fake.answers[0].error === "render timed out", true)
    fake.start()
    fake.reply(survivor, "survivor svg")
    check("the survivor renders after the kill and one crash", fake.answers[fake.answers.length - 1].svg, "survivor svg")
}
