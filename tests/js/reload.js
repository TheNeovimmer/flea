.import "../../ui/js/Reload.js" as Reload

// F5 and Ctrl+R re-read the folder through the listing swap, and the notice names
// how many rows changed, said only when rows changed.

function pane() {
    return {
        listInFlight: false,
        searchMode: "",
        total: 10,
        held: 0,
        windowSize: 40,
        path: "/home/gm/Work",
        cursorIndex: 3,
        filterQuery: "",
        reloadFrom: -1,
        said: [],
        listed: [],
        windowed: [],
        rowFor: function () { return { n: "notes.txt" } },
        message: function (text) { this.said.push(text) },
        openWithoutHistory: function (path, options) { this.listed.push(path) },
        backend: { window: function (start, count) { } }
    }
}

function wire() {
    return { anchor: "kept" }
}

function run(check) {
    check("slow decisions live in their own module", typeof Reload.line, "function")
    if (typeof Reload.line !== "function" || typeof Reload.begin !== "function" || typeof Reload.landed !== "function")
        return

    check("a reload names two changed rows", Reload.line(2), "Reloaded · 2 rows changed")
    check("and one changed row reads singular", Reload.line(1), "Reloaded · 1 row changed")
    check("and a thousand groups the count the way every other count does", Reload.line(1246), "Reloaded · 1,246 rows changed")

    var busy = pane()
    busy.listInFlight = true
    check("a reload refused while a listing is out lists nothing", Reload.begin(busy, wire()), false)
    check("and says why with the sentence every refused navigation gives",
          busy.said.join("|") + "|" + busy.listed.length, "A directory is already loading.|0")

    var searching = pane()
    searching.searchMode = "results"
    check("a reload over search results asks for no listing", Reload.begin(searching, wire()), false)
    check("and says nothing, the way the sort keys go quiet there", searching.said.length + "|" + searching.listed.length, "0|0")

    var plain = pane()
    var w = wire()
    check("a reload of the open folder re-lists it", Reload.begin(plain, w), true)
    check("through the same anchored re-read a watched change takes", plain.listed.join(","), "/home/gm/Work")
    check("and remembers the count it is answering against", plain.reloadFrom, 10)
    check("and holds the cursor anchor for the rows reply", w.anchor !== "kept" && w.anchor !== undefined, true)

    var grown = pane()
    grown.said = []
    grown.reloadFrom = 10
    grown.total = 12
    Reload.landed(grown)
    check("two rows gained say so", grown.said.join("|"), "Reloaded · 2 rows changed")
    check("and spend the reload, so the next listing says nothing", grown.reloadFrom, -1)
    var shrunk = pane()
    shrunk.reloadFrom = 10
    shrunk.total = 9
    Reload.landed(shrunk)
    check("one row lost reads singular", shrunk.said.join("|"), "Reloaded · 1 row changed")
    var same = pane()
    same.reloadFrom = 10
    same.total = 10
    Reload.landed(same)
    check("an unchanged folder says nothing at all", same.said.length, 0)
    var idle = pane()
    Reload.landed(idle)
    check("an ordinary navigation owes no notice", idle.said.length + "|" + idle.reloadFrom, "0|-1")
}
