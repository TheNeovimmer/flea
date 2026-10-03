.import "../../ui/js/Clipboard.js" as Clipboard
.import "../../ui/js/Ops.js" as Ops

function acknowledge(p, token) { Clipboard.receive(p, {op: "set", ok: true, token: token}) }
function pasted(p) {
    var request = p.asked[p.asked.length - 1]
    return request ? request[0].op + ":" + request[0].paths.join(",") : "nothing"
}
function mirror(first, second) {
    var shared = {clip: first.clipboard}
    function property(p) {
        Object.defineProperty(p, "clipboard", {
            get: function () { return shared.clip },
            set: function (clip) { shared.clip = clip }
        })
    }
    property(first)
    property(second)
    second.clipboardState = first.clipboardState
}

function run(check, pane, changed, watchError) {
    var p = pane()
    Ops.clip(p, false, ["/missing-paths/local"])
    var selectionError = ""
    try {
        Clipboard.receive(p, {op: "changed", clip: "none", token: "foreign-text"})
    } catch (error) {
        selectionError = String(error)
    }
    check("token-without-paths: pending copy accepts text selection", selectionError, "")
    check("token-without-paths: text selection clears local files", p.clipboard.paths.length, 0)
    acknowledge(p, "local-files")
    check("token-without-paths: acknowledgement cannot revive files", p.clipboard.paths.length, 0)

    p = pane()
    Ops.clip(p, false, ["/delayed/a"])
    acknowledge(p, "owned-a")
    Ops.clip(p, true, ["/delayed/b"])
    acknowledge(p, "owned-b")
    var local = p.clipboard
    changed(p, "copy", ["/delayed/a"], "owned-a")
    changed(p, "cut", ["/delayed/b"], "owned-b")
    check("delayed-owned-echo: latest local object survives", p.clipboard === local, true)
    Ops.paste(p)
    check("delayed-owned-echo: paste uses latest cut", pasted(p), "move:/delayed/b")
    changed(p, "copy", ["/foreign/c"], "foreign-c")
    check("delayed-owned-echo: foreign token replaces", p.clipboard.token, "foreign-c")

    p = pane()
    var other = pane()
    mirror(p, other)
    Ops.clip(p, false, ["/dual/a"])
    acknowledge(p, "dual-a")
    Ops.clip(other, true, ["/dual/b"])
    acknowledge(other, "dual-b")
    local = p.clipboard
    changed(other, "copy", ["/dual/a"], "dual-a")
    changed(p, "cut", ["/dual/b"], "dual-b")
    changed(p, "copy", ["/dual/a"], "dual-a")
    changed(other, "cut", ["/dual/b"], "dual-b")
    check("dual-delayed-owned-echo: both panes retain latest object", p.clipboard === local && other.clipboard === local, true)
    Ops.paste(other)
    check("dual-delayed-owned-echo: secondary paste uses latest cut", pasted(other), "move:/dual/b")
    changed(other, "copy", ["/foreign/dual"], "foreign-dual")
    check("dual-delayed-owned-echo: foreign selection reaches both panes", p.clipboard === other.clipboard && p.clipboard.token === "foreign-dual", true)

    p = pane()
    Ops.clip(p, false, ["/deferred/a"])
    changed(p, "copy", ["/deferred/a"], "foreign-a")
    Ops.clip(p, true, ["/deferred/b"])
    local = p.clipboard
    acknowledge(p, "local-a")
    check("deferred-selection-race: old acknowledgement retains newer object", p.clipboard === local, true)
    acknowledge(p, "local-b")
    changed(p, "cut", ["/deferred/b"], "local-b")
    Ops.paste(p)
    check("deferred-selection-race: paste uses latest cut", pasted(p), "move:/deferred/b")

    for (var moving = 0; moving <= 1; moving++) {
        p = pane()
        Ops.clip(p, false, ["/get/a"])
        acknowledge(p, "get-a")
        watchError(p)
        Ops.paste(p)
        check("fallback-get-race: paste waits for fallback read", p.asked.length, 0)
        Ops.clip(p, moving === 1, ["/get/b"])
        local = p.clipboard
        Clipboard.receive(p, {op: "get", ok: true, clip: "copy", paths: ["/get/a"], token: "get-a"})
        check("fallback-get-race: newer local object survives", p.clipboard === local, true)
        check("fallback-get-race: pending paste uses newer selection", pasted(p), (moving ? "move" : "copy") + ":/get/b")
        acknowledge(p, "get-b")
        changed(p, moving ? "cut" : "copy", ["/get/b"], "get-b")
        var pastes = p.asked.length
        var sends = p.sent.length
        Ops.paste(p)
        check("fallback-get-race: recovery starts a new paste", p.asked.length, pastes + 1)
        check("fallback-get-race: recovery starts no fallback read", p.sent.length, sends)
        check("fallback-get-race: paste after recovery uses newer selection", pasted(p), (moving ? "move" : "copy") + ":/get/b")
    }

    p = pane()
    other = pane()
    mirror(p, other)
    watchError(other)
    Ops.paste(other)
    Ops.clip(p, true, ["/get/dual"])
    Clipboard.receive(other, {op: "get", ok: true, clip: "copy", paths: ["/get/stale"], token: "foreign-old"})
    check("fallback-get-race: shared generation preserves other pane's cut", pasted(other), "move:/get/dual")

    p = pane()
    other = pane()
    mirror(p, other)
    changed(p, "copy", ["/foreign/a"], "foreign-a")
    watchError(p)
    Ops.paste(p)
    check("foreign-before-get: paste waits for read", p.asked.length, 0)
    var generation = p.clipboardState.generation
    changed(other, "cut", ["/foreign/b"], "foreign-b")
    local = p.clipboard
    check("foreign-before-get: accepted watcher advances generation", p.clipboardState.generation, generation + 1)
    Clipboard.receive(p, {op: "get", ok: true, clip: "copy", paths: ["/foreign/a"], token: "foreign-a"})
    check("foreign-before-get: newer selection survives", p.clipboard === local && other.clipboard === local, true)
    check("foreign-before-get: waiting paste uses newer cut", pasted(p), "move:/foreign/b")
    Ops.paste(other)
    check("foreign-before-get: later paste uses newer cut", pasted(other), "move:/foreign/b")

    p = pane()
    other = pane()
    mirror(p, other)
    watchError(p)
    watchError(other)
    Ops.paste(p)
    Ops.paste(other)
    check("get-before-get older-first: both pastes wait for reads", p.asked.length + other.asked.length, 0)
    check("get-before-get older-first: both backends issue reads", p.sent[0].c + "," + other.sent[0].c, "clipGet,clipGet")
    Clipboard.receive(p, {op: "get", ok: true, clip: "copy", paths: ["/read/a"], token: "read-a"})
    check("get-before-get older-first: first waiting paste uses A", pasted(p), "copy:/read/a")
    Clipboard.receive(other, {op: "get", ok: true, clip: "cut", paths: ["/read/b"], token: "read-b"})
    check("get-before-get older-first: newer waiting paste uses B", pasted(other), "move:/read/b")
    check("get-before-get older-first: both panes cache B", p.clipboard === other.clipboard && p.clipboard.token === "read-b", true)
    check("get-before-get older-first: both reads finish", p.clipboardState.gets.length, 0)
    // A completed paste cannot change; a subsequent paste in the first pane must use B.
    Ops.paste(p)
    Clipboard.receive(p, {op: "get", ok: true, clip: "cut", paths: ["/read/b"], token: "read-b"})
    check("get-before-get older-first: both panes now paste B", pasted(p) + "," + pasted(other), "move:/read/b,move:/read/b")

    p = pane()
    other = pane()
    mirror(p, other)
    watchError(p)
    watchError(other)
    Ops.paste(p)
    Ops.paste(other)
    check("get-before-get newer-first: both pastes wait for reads", p.asked.length + other.asked.length, 0)
    Clipboard.receive(other, {op: "get", ok: true, clip: "cut", paths: ["/read/b"], token: "read-b"})
    local = p.clipboard
    Clipboard.receive(p, {op: "get", ok: true, clip: "copy", paths: ["/read/a"], token: "read-a"})
    check("get-before-get newer-first: older read retains B", p.clipboard === local && other.clipboard === local, true)
    check("get-before-get newer-first: both waiting pastes use B", pasted(p) + "," + pasted(other), "move:/read/b,move:/read/b")
    check("get-before-get newer-first: both panes cache B", p.clipboard.token, "read-b")
    check("get-before-get newer-first: both reads finish", p.clipboardState.gets.length, 0)

    p = pane()
    other = pane()
    mirror(p, other)
    changed(p, "copy", ["/pending/a"], "pending-a")
    watchError(other)
    Ops.clip(p, true, ["/pending/b"])
    local = p.clipboard
    sends = other.sent.length
    Ops.paste(other)
    check("get-during-set: pending set starts no get", other.sent.length, sends)
    check("get-during-set: pending paste moves local cut", pasted(other), "move:/pending/b")
    Clipboard.receive(other, {op: "get", ok: true, clip: "copy", paths: ["/pending/a"], token: "pending-a"})
    check("get-during-set: old reply retains local cut", p.clipboard === local && other.clipboard === local, true)
    check("get-during-set: old reply never pastes old copy", pasted(other), "move:/pending/b")
    acknowledge(p, "pending-b")
    changed(p, "cut", ["/pending/b"], "pending-b")
    changed(other, "cut", ["/pending/b"], "pending-b")
    Ops.paste(other)
    check("get-during-set: recovery starts a second paste", other.asked.length, 2)
    check("get-during-set: acknowledged paste keeps cut", pasted(other), "move:/pending/b")
    check("get-during-set: acknowledged selection retains token", p.clipboard.token, "pending-b")
}
