.import "../../ui/js/Messages.js" as Messages
.import "../../ui/js/SlowOp.js" as SlowOp

function run(check) {
    var calls = []
    var root = { slowOp: function(op, path, msg) { calls.push([op, path, msg]) },
        renamed: function() {}, made: function() {}, linked: function() {} }
    Messages.route(root, {t: "slow", op: "rename", path: "/hung/a.txt", msg: "/hung is slow. The rename continues and will finish on its own."})
    check("a slow line reaches the slow handler with its op, path and sentence",
          JSON.stringify(calls),
          JSON.stringify([["rename", "/hung/a.txt", "/hung is slow. The rename continues and will finish on its own."]]))
    calls = []
    Messages.route(root, {t: "slow"})
    check("a slow line with no fields still reaches the handler rather than throwing",
          JSON.stringify(calls), JSON.stringify([["", "", ""]]))
    var renamed = [], made = [], linked = []
    root.renamed = function(ok, path) { renamed.push([ok, path]) }
    root.made = function(ok, path) { made.push([ok, path]) }
    root.linked = function(ok, failed, skipped) { linked.push([ok, failed, skipped]) }
    Messages.route(root, {t: "renamed", ok: true, path: "/hung/b.txt"})
    Messages.route(root, {t: "made", ok: true, path: "/hung/New Folder"})
    Messages.route(root, {t: "linked", ok: 2, failed: 0, skipped: 0})
    check("the late replies still reach their own handlers after the slow branch lands",
          JSON.stringify([renamed, made, linked]),
          JSON.stringify([[[true, "/hung/b.txt"]], [[true, "/hung/New Folder"]], [[2, 0, 0]]]))

    // The request the slow line left open is the one the late reply closes.
    var messages = []
    var request = {source: "/hung/a.txt", destination: "/hung/b.txt", folder: "/hung"}
    var pane = {renameRequest: request, message: function(text, failed) { messages.push([text, failed]) }}
    SlowOp.show(pane, "/hung is slow. The rename continues and will finish on its own.")
    check("the slow line shows its sentence as information, never as an error",
          JSON.stringify(messages),
          JSON.stringify([["/hung is slow. The rename continues and will finish on its own.", false]]))
    check("and it leaves the rename request open for the late reply",
          pane.renameRequest === request, true)
    check("a renamed line for that destination closes it",
          SlowOp.closesRename(request, "/hung/b.txt"), true)
    check("and any other path leaves it open",
          SlowOp.closesRename(request, "/hung/c.txt"), false)
    check("with no request open nothing closes",
          SlowOp.closesRename(null, "/hung/b.txt"), false)
}
