.import "../../ui/js/Recent.js" as Recent
.import "sourcefixture.js" as Source

function run(check) {
    // Where the history lives, which is XDG_DATA_HOME's own file and never a Flea-owned one.
    check("the session's data home is honoured",
          Recent.historyPath("/run/user/1000/data", "/home/gm"), "/run/user/1000/data/recently-used.xbel")
    check("an unset data home falls back to the default",
          Recent.historyPath("", "/home/gm"), "/home/gm/.local/share/recently-used.xbel")
    check("a data home that is not a path is not a data home",
          Recent.historyPath("relative/share", "/home/gm"), "/home/gm/.local/share/recently-used.xbel")
    check("a trailing slash does not double up",
          Recent.historyPath("/home/gm/.local/share/", "/home/gm"), "/home/gm/.local/share/recently-used.xbel")

    // Every bookmark is untrusted text until read as one real local file URI.
    check("a plain local file", Recent.pathOf("file:///home/gm/a.png"), "/home/gm/a.png")
    check("a percent-encoded name decodes", Recent.pathOf("file:///home/gm/a%20b%23c.png"), "/home/gm/a b#c.png")
    check("a non-ASCII name decodes", Recent.pathOf("file:///home/gm/caf%C3%A9.txt"), "/home/gm/café.txt")
    check("the localhost authority is this machine", Recent.pathOf("file://localhost/etc/hostname"), "/etc/hostname")
    check("the scheme is case-insensitive", Recent.pathOf("FILE:///etc/hostname"), "/etc/hostname")

    check("another machine is refused", Recent.pathOf("file://nas.local/share/x.txt"), "")
    check("a share is not a local file", Recent.pathOf("smb://nas/share/x.txt"), "")
    check("sftp is not a local file", Recent.pathOf("sftp://host/home/gm/x.txt"), "")
    check("trash is not a local file", Recent.pathOf("trash:///x.txt"), "")
    check("a bare path is not a URI at all", Recent.pathOf("/home/gm/a.png"), "")
    check("free text is not a URI", Recent.pathOf("rm -rf /home/gm"), "")
    check("an empty bookmark is refused", Recent.pathOf(""), "")
    check("a file URI with no path is refused", Recent.pathOf("file://"), "")
    check("the root itself is not a recent file", Recent.pathOf("file:///"), "")
    check("an embedded NUL is refused", Recent.pathOf("file:///home/gm/a%00b"), "")
    check("an embedded newline is refused", Recent.pathOf("file:///home/gm/a%0Ab"), "")
    check("a percent sequence that cannot decode is refused", Recent.pathOf("file:///home/gm/%zz"), "")

    // The rail's order is the history's own, newest first, and one file appears once.
    var read = Recent.paths([
        { href: "file:///home/gm/old.txt", stamp: "2026-08-01T09:00:00Z" },
        { href: "file:///home/gm/new.png", stamp: "2026-08-30T11:32:04Z" },
        { href: "smb://nas/share/skip.txt", stamp: "2026-08-31T11:32:04Z" },
        { href: "file:///home/gm/mid.md", stamp: "2026-08-15T10:00:00Z" }
    ])
    check("only the local files are kept", read.length, 3)
    check("newest first", read[0], "/home/gm/new.png")
    check("then the one below it", read[1], "/home/gm/mid.md")
    check("then the oldest", read[2], "/home/gm/old.txt")

    var twice = Recent.paths([
        { href: "file:///home/gm/a.png", stamp: "2026-08-30T11:32:04Z" },
        { href: "file:///home/gm/a.png", stamp: "2026-08-01T09:00:00Z" }
    ])
    check("a file listed twice keeps one row", twice.length, 1)
    check("and keeps its newest position", twice[0], "/home/gm/a.png")

    // Two bookmarks sharing a stamp must not swap between reads, or the rail reorders on a refresh.
    var tied = Recent.paths([
        { href: "file:///home/gm/first.txt", stamp: "2026-08-30T11:32:04Z" },
        { href: "file:///home/gm/second.txt", stamp: "2026-08-30T11:32:04Z" }
    ])
    check("a tie keeps the file's own order", tied[0], "/home/gm/first.txt")
    check("and the one after it", tied[1], "/home/gm/second.txt")

    // A bookmark whose writer left every stamp out still lists, it just sorts last.
    var stampless = Recent.paths([
        { href: "file:///home/gm/none.txt", stamp: "" },
        { href: "file:///home/gm/dated.txt", stamp: "2026-08-30T11:32:04Z" }
    ])
    check("a stampless bookmark still lists", stampless.length, 2)
    check("and sorts below a dated one", stampless[1], "/home/gm/none.txt")

    check("an empty history is an empty rail", Recent.paths([]).length, 0)
    check("a history of nothing but remote bookmarks is empty too",
          Recent.paths([{ href: "smb://nas/x", stamp: "2026-08-30T11:32:04Z" }]).length, 0)

    // A hostile history is still a listing this window has to build, so the read stops at the cap.
    var many = []
    for (var i = 0; i < Recent.LIMIT + 50; i++) {
        many.push({ href: "file:///home/gm/f" + i + ".txt", stamp: "2026-08-30T11:32:04Z" })
    }
    check("an enormous history stops at the cap", Recent.paths(many).length, Recent.LIMIT)

    // The cap keeps the newest LIMIT, so an oldest-first history still answers newest.
    var oldestFirst = []
    for (var k = 0; k < Recent.LIMIT + 50; k++) {
        var minute = 32 + Math.floor(k / 60)
        var second = k % 60
        oldestFirst.push({ href: "file:///home/gm/g" + k + ".txt",
                           stamp: "2026-08-30T11:" + minute + ":" + (second < 10 ? "0" + second : second) + "Z" })
    }
    var newest = Recent.paths(oldestFirst)
    check("an oldest-first history still stops at the cap", newest.length, Recent.LIMIT)
    check("and the row at the top is the newest bookmark in the file", newest[0], "/home/gm/g549.txt")
    check("and the last row kept is the oldest of the newest LIMIT", newest[Recent.LIMIT - 1], "/home/gm/g50.txt")

    // entries() is paths() with the stamps kept, so the Used column draws the visit.
    var kept = Recent.entries([
        { href: "file:///home/gm/old.txt", stamp: "2026-08-01T09:00:00Z" },
        { href: "file:///home/gm/new.png", stamp: "2026-08-30T11:32:04Z" },
        { href: "smb://nas/share/skip.txt", stamp: "2026-08-31T11:32:04Z" }
    ])
    check("entries keeps only the local files", kept.length, 2)
    check("entries lists newest first", kept[0].path, "/home/gm/new.png")
    check("entries keeps the stamp the Used column draws", kept[0].stamp, "2026-08-30T11:32:04Z")
    check("and the older row keeps its own stamp", kept[1].stamp, "2026-08-01T09:00:00Z")
    var keptTwice = Recent.entries([
        { href: "file:///home/gm/a.png", stamp: "2026-08-01T09:00:00Z" },
        { href: "file:///home/gm/a.png", stamp: "2026-08-30T11:32:04Z" }
    ])
    check("entries lists a file seen twice once", keptTwice.length, 1)
    check("and keeps the newest stamp for it", keptTwice[0].stamp, "2026-08-30T11:32:04Z")
    // A missing history and an unreadable one both list nothing.
    check("a missing history lists nothing", Recent.entries([]).length, 0)
    check("bookmarks with no readable path list nothing",
          Recent.entries([{ href: "", stamp: "2026-08-30T11:32:04Z" },
                          { href: "not a uri", stamp: "2026-08-30T11:32:04Z" }]).length, 0)
    var manyEntries = []
    for (var e = 0; e < Recent.LIMIT + 10; e++) {
        manyEntries.push({ href: "file:///home/gm/h" + e + ".txt", stamp: "2026-08-30T11:32:04Z" })
    }
    check("entries stops at the same cap as paths", Recent.entries(manyEntries).length, Recent.LIMIT)

    // The leaf draws as the name and its parent as the caption beside it.
    check("the leaf is the name", Recent.nameOf("/home/gm/a.txt"), "a.txt")
    check("the parent is the location", Recent.locationOf("/home/gm/a.txt"), "/home/gm")
    check("a listpaths row names the same leaf", Recent.nameOf("home/gm/a.txt"), "a.txt")
    check("and the same absolute parent", Recent.locationOf("home/gm/a.txt"), "/home/gm")
    check("a bare name sits in the root", Recent.locationOf("a.txt"), "/")
    check("a root-level file sits in the root", Recent.locationOf("/a.txt"), "/")

    // The rail joins every asker waiting on one history read, null naming the rail pane itself.
    check("the asker join lives in Recent", typeof Recent.joinRequesters, "function")
    if (typeof Recent.joinRequesters === "function") {
        var paneA = { name: "paneA" }
        var paneB = { name: "paneB" }
        var askers = Recent.joinRequesters([], paneA)
        check("one asker waits", askers.length, 1)
        askers = Recent.joinRequesters(askers, paneB)
        check("two panes both wait", askers.length, 2)
        check("the first pane still waits", askers[0] === paneA, true)
        check("and the second waits behind it", askers[1] === paneB, true)
        check("a repeat asks nothing twice", Recent.joinRequesters(askers, paneA).length, 2)
        var railAsk = Recent.joinRequesters([], null)
        check("the rail pane itself joins as null", railAsk.length === 1 && railAsk[0] === null, true)
        check("and a null repeat joins once", Recent.joinRequesters(railAsk, null).length, 1)
        check("a pane joins beside the rail pane", Recent.joinRequesters(railAsk, paneA).length, 2)
    }
    // The rail joins through the helper at both ends, so one requester at either end turns red.
    var sidebar = Source.source("ui/Sidebar.qml")
    var reading = Source.slice(sidebar, "function readRecent(", "if (root.recentKept")
    check("readRecent joins its asker while a read is in flight",
        reading.indexOf("recentReader.item.joinRequesters(root.recentRequesters, requester)") >= 0
            && Source.source("ui/PickerRecent.qml").indexOf("return Recent.joinRequesters(current, requester)") >= 0, true)
    var refreshed = Source.slice(sidebar, "function onRefreshed()", "readonly property bool dropboxReady")
    check("onRefreshed answers every asker",
        refreshed.indexOf("root.recentRequested(root.recentPaths, askers[i], root.recentVisits)") >= 0, true)
}
