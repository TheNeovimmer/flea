// Drive the persistent figure cache's routing through the production handlers: the disk answers first, and a miss reaches the helper whole.
function run(check, service) {
    var fake = service()
    fake.disk.available = true
    var remembered = fake.ask("remembered", true)
    check("an ask with the cache available asks the disk first", fake.disk.gets.length === 1 && fake.root.pending.length === 0 && !fake.root.starting, true)
    fake.root.storeAnswered(remembered, "disk svg")
    check("a disk hit answers the figure with no helper", fake.answers[fake.answers.length - 1].svg === "disk svg" && fake.writes.length === 0 && !fake.root.starting, true)
    var unseen = fake.ask("unseen", true)
    fake.root.storeAnswered(unseen, "")
    check("a disk miss starts the helper", fake.root.starting, true)
    fake.start()
    fake.reply(unseen, "drawn svg")
    check("the helper's answer is written to the disk cache", fake.disk.puts.length === 1 && fake.disk.puts[0].svg === "drawn svg", true)
}
