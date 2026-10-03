.import "../../ui/js/Clipboard.js" as Clipboard
.import "../../ui/js/ClipMarks.js" as ClipMarks
.import "../../ui/js/Ops.js" as Ops
.import "../../ui/js/Focus.js" as Focus
.import "../../ui/js/Menu.js" as Menu
.import "collidefixture.js" as Fixture
.import "sourcefixture.js" as Source
.import "clipboardraces.js" as Races

function pane() {
    var p = { path: "/dest", clipboard: Clipboard.empty(), clipboardState: Clipboard.state(),
        clipboardWatchFailed: false, clipPending: null, sent: [], said: [], asked: [], listInFlight: false, recentMode: "" }
    p.backend = { send: function (m) {
        p.sent.push(m)
        p.localAtSend = p.clipboard
    } }
    p.message = function (s, error) { p.said.push(s) }
    p.collide = { ask: function (r, probe, cut) { p.asked.push([r, cut]); return true } }
    return p
}
function changed(p, kind, paths, token) {
    Clipboard.receive(p, { op: "changed", clip: kind, paths: paths || [], token: token || "" })
}
function watchError(p) { Clipboard.receive(p, { op: "changed", clip: "none", error: "no data-control" }) }
function run(check) {
    var p = pane()
    Ops.clip(p, false, ["/a/f1"])
    var local = p.clipboard
    check("copy marks locally before clipSet", p.localAtSend === local, true)
    check("copy offers the system selection", JSON.stringify(p.sent[0]),
          JSON.stringify({ c: "clipSet", op: "copy", paths: ["/a/f1"] }))
    check("copy status is immediate", p.said[0], "Copied 1 item · p pastes")
    Clipboard.receive(p, { op: "set", ok: true, token: "own" })
    check("copy retains its token", p.clipboard.token, "own")
    local = p.clipboard
    changed(p, "copy", ["/a/f1"], "own")
    check("own watcher token changes no object", p.clipboard === local, true)
    changed(p, "copy", ["/other/copy"], "foreign")
    check("foreign copy replaces paths and token", JSON.stringify(p.clipboard),
          JSON.stringify({paths: ["/other/copy"], moving: false, token: "foreign"}))
    check("foreign copy updates marks", ClipMarks.markFor("/other/copy", p.clipboard), "copy")
    changed(p, "cut", ["/other/cut"])
    check("foreign cut changes direction", p.clipboard.moving, true)
    check("foreign cut updates marks", ClipMarks.markFor("/other/cut", p.clipboard), "scissors")
    changed(p, "none")
    check("none empties files and token", JSON.stringify(p.clipboard), JSON.stringify(Clipboard.empty()))
    var emptyRows = Menu.listingEntries({hasRow: true, hiddenActions: [], clipboardAvailable: false})
        .filter(function (r) { return r.action === "paste" || r.action === "pasteAs" })
    check("empty clipboard retains both disabled paste rows", emptyRows.length === 2 && emptyRows.every(function (r) { return r.disabled === true }), true)
    check("empty Paste as has no chevron", emptyRows.some(function (r) { return r.action === "pasteAs" && Menu.hasSubmenu(r) }), false)
    check("file clipboard offers both paste rows", Menu.listingEntries({hasRow: true, hiddenActions: [], clipboardAvailable: true})
          .filter(function (r) { return r.action === "paste" || r.action === "pasteAs" }).length, 2)
    check("none releases marks", ClipMarks.markFor("/other/cut", p.clipboard), "")
    check("empty clipboard releases lookup", ClipMarks._cached, null)
    Ops.paste(p)
    check("text-only clipboard pastes nothing", p.asked.length, 0)
    Ops.pasteLink(p, "relative", ["/selected/row"])
    check("selected row cannot turn plain text into a link paste", p.asked.length, 0)

    p = pane()
    watchError(p)
    check("failed watcher publishes menu state", p.clipboardWatchFailed, true)
    var failedRows = Menu.listingEntries({hasRow: false, hiddenActions: [], clipboardAvailable: false, clipboardWatchFailed: true})
        .filter(function (r) { return r.action === "paste" || r.action === "pasteAs" })
    check("failed watcher keeps fallback Paste live", failedRows.some(function (r) { return r.action === "paste" && r.disabled === false }), true)
    check("failed watcher keeps empty Paste as disabled without chevron", failedRows.some(function (r) { return r.action === "pasteAs" && r.disabled === true && !Menu.hasSubmenu(r) }), true)
    Ops.paste(p)
    check("empty failed cache activates system read", p.sent[0].c, "clipGet")
    check("empty failed cache waits before transfer", p.asked.length, 0)
    Clipboard.receive(p, {op: "get", ok: true, clip: "copy", paths: ["/fallback/file"]})
    check("fallback Paste uses foreign files", p.asked[0][0].paths.join(","), "/fallback/file")
    changed(p, "none")
    check("watch recovery clears menu failure state", p.clipboardWatchFailed, false)
    var readOnlyRows = Menu.listingEntries({hasRow: false, clipboardAvailable: false, clipboardWatchFailed: true, dirWritable: false})
    check("failed watcher cannot enable Paste into read-only folder", readOnlyRows.some(function (r) { return r.action === "paste" && r.disabled === true }), true)

    p = pane()
    p.clipPending = true
    Ops.clipResolved(p, ["/a/f2"])
    check("resolved cut lands locally", p.localAtSend.moving, true)
    check("resolved cut sends clipSet", p.sent[0].op, "cut")
    check("paths claim ends", p.clipPending, null)
    local = p.clipboard
    Clipboard.receive(p, { op: "set", ok: false, error: "no compositor" })
    check("failed set retains local object", p.clipboard === local, true)
    check("failed set reports honest scope", p.said[1], "Copied in this window only: no compositor")
    Clipboard.receive(p, { op: "set", ok: false, error: "no compositor" })
    check("failure reports once per pending set", p.said.length, 2)
    watchError(p)
    check("watch failure keeps local copy", p.clipboard === local, true)
    Ops.paste(p)
    check("watch failure reads before paste", p.sent[1].c, "clipGet")
    check("paste waits for read", p.asked.length, 0)
    Ops.paste(p)
    check("repeated paste sends one read", p.sent.length, 2)
    Clipboard.receive(p, { op: "get", ok: false, error: "no compositor" })
    check("failed read still pastes local cut", p.asked[0][0].op, "move")
    check("failed read retains paths", p.asked[0][0].paths.join(","), "/a/f2")
    Ops.paste(p)
    Clipboard.receive(p, { op: "get", ok: true, clip: "copy", paths: ["/foreign/f"], token: "" })
    check("successful fallback pastes current system copy", p.asked[1][0].paths[0], "/foreign/f")
    check("fallback replaces moving flag", p.asked[1][0].op, "copy")
    Ops.pasteLink(p, "absolute", ["/selected/row"])
    check("link paste also reads after watch failure", p.sent[p.sent.length - 1].c, "clipGet")
    Clipboard.receive(p, { op: "get", ok: true, clip: "cut", paths: ["/foreign/link"], token: "" })
    check("link paste uses refreshed paths", p.asked[2][0].paths[0], "/foreign/link")
    check("link paste never spends cut", p.asked[2][1], false)
    Focus.act("movePaste", p)
    check("movePaste also reads first", p.sent[p.sent.length - 1].c, "clipGet")
    Clipboard.receive(p, { op: "get", ok: true, clip: "copy", paths: ["/foreign/move"], token: "" })
    check("forced move preserves copy clipboard", p.asked[3][0].op + "/" + p.asked[3][1], "move/false")
    Ops.paste(p)
    Clipboard.receive(p, { op: "get", ok: true, clip: "none", paths: [], token: "" })
    check("fallback plain text pastes no files", p.asked.length, 4)
    changed(p, "copy", ["/recovered/f"], "new")
    var sent = p.sent.length
    Ops.paste(p)
    check("watch recovery stops fallback reads", p.sent.length, sent)

    p = pane()
    changed(p, "cut", ["/a/f2"], "cut-token")
    Clipboard.spent(p, p.clipboard, true)
    check("spent cut clears by token", JSON.stringify(p.sent[0]), JSON.stringify({c: "clipClear", token: "cut-token"}))
    check("spent cut empties local marks", p.clipboard.paths.length, 0)
    changed(p, "cut", ["/foreign/f2"])
    Clipboard.spent(p, p.clipboard, true)
    check("foreign spent cut clears by path list", JSON.stringify(p.sent[1]), JSON.stringify({c: "clipClear", cut: ["/foreign/f2"]}))
    changed(p, "copy", ["/a/f1"], "copy-token")
    local = p.clipboard
    Clipboard.spent(p, p.clipboard, true)
    check("copy never sends clear", p.sent.length, 2)
    check("copy retains local object", p.clipboard === local, true)
    changed(p, "cut", ["/old/f"], "old")
    local = p.clipboard
    changed(p, "cut", ["/new/f"], "new")
    Clipboard.spent(p, local, true)
    check("card clears its captured cut", p.sent[2].token, "old")
    check("card preserves newer cut", p.clipboard.token, "new")

    var scene = Fixture.scene(1)
    p = scene.pane
    p.clipboard = {paths: ["/a/f2"], moving: true, token: "sent-cut"}
    p.collide.pane = p
    Ops.paste(p)
    check("captured token in card", p.collide.cutClipboard.token, "sent-cut")
    check("pending collision retains cut", p.clipboard.paths.length, 1)
    p.collide.decide("replace")
    check("real card sends transfer before clear", Fixture.verbs(scene.backend), "collisions,transfer,clipClear")
    check("real card clears captured token", scene.backend.sent[2].token, "sent-cut")
    check("real card clears local selection", p.clipboard.paths.length, 0)
    check("real card releases captured cut paths", p.collide.cutClipboard, null)
    p.clipboard = {paths: ["/a/f2"], moving: true, token: "cancel-cut"}
    p.collide.pane = p
    Ops.paste(p)
    p.collide.decide("cancel")
    check("cancel never sends clear", Fixture.verbs(scene.backend), "collisions,transfer,clipClear,collisions")
    check("cancel keeps cut", p.clipboard.token, "cancel-cut")
    check("cancel releases its captured snapshot", p.collide.cutClipboard, null)
    scene.parent.destroy()

    p = pane()
    watchError(p)
    Ops.paste(p)
    p.path = "/elsewhere"
    Clipboard.receive(p, {op: "get", ok: true, clip: "copy", paths: ["/a/f1"]})
    check("navigation while reading cannot redirect paste", p.asked.length, 0)
    var backend = Source.source("ui/Backend.qml")
    check("each writable backend watches once at start", backend.indexOf('if (!root.pickerOnly) root.send({ c: "clipWatch" })') >= 0, true)
    check("PaneWire routes clipboard replies", Source.source("ui/PaneWire.qml").indexOf("Clipboard.receive(pane, message)") >= 0, true)
    check("dual panes share clipboard session", Source.source("ui/WindowBody.qml").indexOf("clipboardState: primaryPane.clipboardState") >= 0, true)
    var paneSource = Source.source("ui/Pane.qml")
    check("Pane declares reactive watcher failure", paneSource.indexOf("property bool clipboardWatchFailed: false") >= 0, true)
    check("Pane passes its watcher failure to menu", paneSource.indexOf("clipboardWatchFailed: root.clipboardWatchFailed") >= 0, true)
    check("ContextMenu passes watcher failure to entries", Source.source("ui/ContextMenu.qml").indexOf("clipboardWatchFailed: root.clipboardWatchFailed") >= 0, true)
    var rowSource = Source.source("ui/MenuRow.qml")
    check("disabled menu rows retain board opacity", rowSource.indexOf("opacity: root.available ? 1 : 0.55") >= 0, true)
    check("submenu presence controls chevron visibility", rowSource.indexOf("visible: root.isSubmenu") >= 0, true)

    p = pane()
    var other = pane()
    other.clipboardState = p.clipboardState
    Ops.clip(p, true, ["/dual/cut"])
    other.clipboard = p.clipboard
    Clipboard.receive(p, {op: "set", ok: true, token: "dual-token"})
    other.clipboard = p.clipboard
    local = other.clipboard
    changed(other, "cut", ["/dual/cut"], "dual-token")
    check("second backend ignores this window's own token", other.clipboard === local, true)
    watchError(other)
    var n = p.sent.length
    Ops.paste(p)
    check("one failed watcher leaves healthy pane's watch usable", p.sent.length, n)
    Ops.paste(other)
    check("failed secondary watcher reads from its own backend", other.sent[0].c, "clipGet")
    Clipboard.receive(other, {op: "get", ok: false, error: "no data-control"})
    check("secondary fallback retains shared cut", other.asked[0][0].paths[0], "/dual/cut")

    p = pane()
    Ops.clip(p, false, ["/early/first"])
    Ops.clip(p, true, ["/early/second"])
    local = p.clipboard
    changed(p, "copy", ["/early/first"], "first-token")
    check("early owner echo cannot roll back a newer local cut", p.clipboard === local, true)
    Clipboard.receive(p, {op: "set", ok: true, token: "first-token"})
    check("earlier set reply cannot roll back a newer local cut", p.clipboard === local, true)
    changed(p, "cut", ["/early/second"], "second-token")
    Clipboard.receive(p, {op: "set", ok: true, token: "second-token"})
    check("early own echo retains latest cut and returned token", p.clipboard.token, "second-token")
    Ops.clip(p, false, ["/shared/f"])
    changed(p, "copy", ["/shared/f"], "foreign-token")
    Clipboard.receive(p, {op: "set", ok: true, token: "local-token"})
    check("equal-path foreign copy remains authoritative after token resolves", p.clipboard.token, "foreign-token")
    Ops.clip(p, true, ["/shared/new"])
    changed(p, "cut", ["/shared/new"], "deferred-foreign")
    changed(p, "none")
    Clipboard.receive(p, {op: "set", ok: true, token: "new-local"})
    check("later none retires an earlier deferred selection", p.clipboard.paths.length, 0)
    Ops.clip(p, true, ["/shared/error"])
    changed(p, "cut", ["/shared/error"], "deferred-own")
    watchError(p)
    Clipboard.receive(p, {op: "set", ok: true, token: "deferred-own"})
    Ops.paste(p)
    check("replaying an early echo cannot revive a failed watcher", p.sent[p.sent.length - 1].c, "clipGet")
    Races.run(check, pane, changed, watchError)
}
