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
        Ops.paste(p)
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
}
