.import "../../ui/js/Permissions.js" as Permissions
.import "../../ui/js/Ops.js" as Ops
.import "../../ui/js/Menu.js" as Menu
.import "sourcefixture.js" as Source
.import "permissions-refresh.js" as RefreshSuite
.import "permissions-skips.js" as SkipsSuite
// Sample input: blockAfter("function f() { if (x) { y = 1 } }", "function f") answers the outer braces.
function blockAfter(src, marker) {
    var at = src.indexOf(marker)
    if (at < 0) {
        return ""
    }
    var open = src.indexOf("{", at + marker.length)
    if (open < 0) {
        return ""
    }
    var depth = 0
    for (var i = open; i < src.length; i++) {
        if (src[i] === "{") {
            depth += 1
        }
        if (src[i] === "}") {
            depth -= 1
        }
        if (depth === 0) {
            return src.substring(open, i + 1)
        }
    }
    return ""
}
// Sample input: ".pragma library\nfunction summarize(modes) { ... }"; wrapping its shared binding counts internal calls too.
function countedPermissions(counter) {
    var source = Source.source("ui/js/Permissions.js").replace(".pragma library", "")
    var load = new Function("counter", source
        + "\nvar realSummarize = summarize;"
        + "\nsummarize = function (modes) { counter.calls += 1; return realSummarize(modes); };"
        + "\nreturn { noteMode: noteMode, summarize: summarize };")
    return load(counter)
}
// Sample input: "Rectangle {\n id: card\n x: 1 // {\n Text { text: \"}\" }\n anchors { centerIn: parent }\n}" keeps "id: card x: 1 anchors { centerIn: parent }" and drops the Text child.
function cardOwnBindings(src, cardId) {
    // Comments and string literals go first, so a brace inside either never moves the depth.
    var clean = ""
    for (var i = 0; i < src.length; i++) {
        var ch = src[i]
        if (ch === "/" && src[i + 1] === "/") {
            while (i < src.length && src[i] !== "\n") {
                i += 1
            }
            clean += "\n"
        } else if (ch === "/" && src[i + 1] === "*") {
            i = src.indexOf("*/", i + 2)
            i = i < 0 ? src.length : i + 1
        } else if (ch === '"' || ch === "'") {
            var quote = ch
            i += 1
            while (i < src.length && src[i] !== quote) {
                i += src[i] === "\\" ? 2 : 1
            }
            clean += '""'
        } else {
            clean += ch
        }
    }
    var at = clean.search(new RegExp("\\bid:\\s*" + cardId + "\\b"))
    if (at < 0) {
        return ""
    }
    // The card object opens at the nearest unmatched brace before its id.
    var open = at
    for (var back = 0; open >= 0; open--) {
        if (clean[open] === "}") {
            back += 1
        } else if (clean[open] === "{") {
            if (back === 0) {
                break
            }
            back -= 1
        }
    }
    if (open < 0) {
        return ""
    }
    var own = ""
    var depth = 0
    var skipFrom = -1
    for (var j = open + 1; j < clean.length; j++) {
        if (clean[j] === "{") {
            if (depth === 0) {
                // A child object is a type name before its brace; a group such as anchors or font is the card's own.
                var header = own.substring(Math.max(own.lastIndexOf("\n"), own.lastIndexOf(";")) + 1)
                if (/^\s*[A-Z][\w.]*(\s+on\s+[\w.]+)?\s*$/.test(header)) {
                    skipFrom = j
                }
            }
            depth += 1
            if (skipFrom < 0) {
                own += clean[j]
            }
        } else if (clean[j] === "}") {
            if (depth === 0) {
                return own
            }
            depth -= 1
            if (skipFrom >= 0) {
                if (depth === 0) {
                    skipFrom = -1
                }
            } else {
                own += clean[j]
            }
        } else if (skipFrom < 0) {
            own += clean[j]
        }
    }
    return own
}
function run(check) {
    RefreshSuite.run(check)
    SkipsSuite.run(check)
    check("ordinary mode", Permissions.parse("644"), 420)
    check("leading zero", Permissions.parse("0644"), 420)
    check("invalid remains rejected", Permissions.parse("0688"), -1)
    check("special bits unavailable", Permissions.parse("4755"), -1)
    check("empty is not mode zero", Permissions.parse(""), -1)
    check("whitespace not accepted", Permissions.parse("644 "), -1)
    check("owner execute toggle", Permissions.toggle("0644", 64), "0744")
    check("octal and grid one value", Permissions.toggle("0744", 64), "0644")
    check("invalid text preserved", Permissions.toggle("0688", 64), "0688")
    check("identical modes show no mixed bit",
        Permissions.summarize(["0644", "0644"]).mixed, false)
    check("a differing owner-execute bit shows mixed",
        Permissions.summarize(["0644", "0755"]).bits[2].mixed, true)
    check("a bit set everywhere reads on",
        Permissions.summarize(["0644", "0755"]).bits[0].on, true)
    check("a bit set nowhere reads off",
        Permissions.summarize(["0644", "0644"]).bits[2].on, false)
    check("mixed boxes keep each file's own bit note",
        Permissions.mixedNote(), "Mixed boxes keep each file's own bit unless you change them.")

    // Special bits are named in the dialog's own words, never dropped on parse -1.
    check("setgid is named in the dialog's own words",
        Permissions.specialReason("2775"), "Read-only: setgid bit is present.")
    check("and so are setuid and sticky",
        Permissions.specialReason("4755") + "|" + Permissions.specialReason("1755"),
        "Read-only: setuid bit is present.|Read-only: sticky bit is present.")
    check("while an ordinary mode names nothing", Permissions.specialReason("0644"), "")
    check("and neither does an unparseable one", Permissions.specialReason("0688"), "")

    // A batch with a skip names every count and reason, never a plain success.
    check("an untouched batch reports the plain success",
        Permissions.multiResult(2, 2, []), "Permissions changed.")
    check("a batch with skips names every count and reason",
        Permissions.multiResult(1, 3, [{ path: "/d/secret.txt", why: "Read-only: setgid bit is present." },
                                       { path: "/d/gone.txt", why: "Could not change permissions." }]),
        "Permissions changed for 1 of 3; 2 left alone: secret.txt: Read-only: setgid bit is present.; gone.txt: Could not change permissions.")
    check("a batch with nothing applicable still answers every item",
        Permissions.multiResult(0, 1, [{ path: "/d/secret.txt", why: "Read-only: setgid bit is present." }]),
        "Permissions changed for 0 of 1; 1 left alone: secret.txt: Read-only: setgid bit is present.")

    // One skip reads singular, and four show three with an and-1-more tail.
    check("four skips ride multiResult with the same tail",
        Permissions.multiResult(1, 5, [{ path: "/d/a.txt", why: "r1" }, { path: "/d/b.txt", why: "r2" },
                                       { path: "/d/c.txt", why: "r3" }, { path: "/d/d.txt", why: "r4" }]),
        "Permissions changed for 1 of 5; 4 left alone: a.txt: r1; b.txt: r2; c.txt: r3; and 1 more")

    // noteMode answers done once, on the last reply, and calls summarize never.
    var REPLY_COUNT = 5000
    var counter = { calls: 0 }
    var batch = countedPermissions(counter)
    var store = { modes: [], reasons: [], skipped: [], pending: REPLY_COUNT }
    var completions = 0
    var done = false
    var early = false
    for (var i = 0; i < REPLY_COUNT; i++) {
        done = batch.noteMode(store, i, "/f" + i, { ok: true, mode: "0644", reason: "" })
        if (done && i + 1 < REPLY_COUNT) early = true
        if (done) completions += 1
        // Stop at the first early done or stray summarize before a per-reply regression grows quadratic.
        if (early || counter.calls > 0) break
    }
    check("5000 replies land every mode", done + "|" + store.modes.length, "true|" + REPLY_COUNT)
    check("and done answers only on the last reply", early + "|" + done, "false|true")
    check("and noteMode reports done exactly once", completions, 1)
    check("and noteMode makes no summarize call", counter.calls, 0)
    // receiveMany's last-reply write stays inside noteMode-true; a failed batch resets modes so the grid and retry start from disk.
    var dialog = Source.source("ui/PermissionsDialog.qml")
    var received = blockAfter(dialog, "function receiveMany")
    var noteBlock = blockAfter(received, "if (Permissions.noteMode(")
    var failedBlock = blockAfter(received, "if (message.op === \"applyMany\")")
    check("receiveMany writes multiModes exactly twice", received.split("multiModes =").length - 1, 2)
    check("one write sits inside the noteMode-true branch", noteBlock.indexOf("multiModes =") >= 0, true)
    check("and the other resets the failed batch", failedBlock.indexOf("multiModes =") >= 0, true)
    // The multiSummary binding reruns on a multiModes write, so a summarize call anywhere else is a per-reply cost.
    var summaryBinding = "readonly property var multiSummary: isMulti ? Permissions.summarize(multiModes, multiStore.reasons) : null"
    var summarizeCalls = dialog.split("Permissions.summarize(").length - 1
    var allowedCalls = noteBlock.split("Permissions.summarize(").length - 1 + (dialog.indexOf(summaryBinding) >= 0 ? 1 : 0)
    check("the only summarize caller is the multiSummary binding or the noteMode-true branch",
          summarizeCalls + "|" + allowedCalls, "1|1")
    var refused = { modes: [], reasons: [], skipped: [], pending: 3 }
    Permissions.noteMode(refused, 0, "/d/a.txt", { ok: true, mode: "2755", reason: "Read-only: setgid bit is present." })
    Permissions.noteMode(refused, 1, "/d/b.txt", { ok: false, error: "Gone." })
    var last = Permissions.noteMode(refused, 2, "/d/c.txt", { ok: true, mode: "0644", reason: "" })
    check("a refused inspect lands as a named skip", last + "|" + refused.skipped.length + "|" + refused.skipped[0].why,
          "true|1|Gone.")
    check("and rides the reasons once, beside its row",
          refused.reasons.join("|"), "Read-only: setgid bit is present.|Gone.|")

    // The single-path Permissions branch vets the target row, never the cursor row.
    var single = {
        cursorIndex: 5,
        selectedIndices: function () { return [3] },
        rowFor: function (i) { return i === 3 ? { p: 33188 } : { p: 41471 } }
    }
    check("the target is the selection, not the cursor", Ops.targetIndices(single).join(","), "3")
    check("the regular target opens Permissions", Menu.permissionsEntry(single.rowFor(3).p, 1).disabled, false)
    check("while the cursor row alone would refuse", Menu.permissionsEntry(single.rowFor(5).p, 1).disabled, true)
    var branch = Source.slice(Source.source("ui/Pane.qml"), "function openPermissionsWith(paths)", "function openCopyAs()")
    check("the branch vets the target row", branch.indexOf("permissionSelection()") >= 0, true)
    check("and never the cursor row", branch.indexOf("rowFor(root.cursorIndex)") < 0, true)

    // The one-shot Make executable id offset lives once in Permissions, and both QML readers add to it.
    check("the offset is named once", Permissions.MAKE_EXEC_ID, 1000000)
    check("Pane.qml reads the named offset",
          Source.source("ui/Pane.qml").indexOf("Permissions.MAKE_EXEC_ID + root.makeExecPendingId") >= 0, true)
    check("PaneWire.qml reads the named offset",
          Source.source("ui/PaneWire.qml").indexOf("Permissions.MAKE_EXEC_ID + pane.makeExecPendingId") >= 0, true)
    check("no bare offset math remains in Pane.qml",
          Source.source("ui/Pane.qml").indexOf("1000000 + root.makeExecPendingId") < 0, true)
    check("no bare offset math remains in PaneWire.qml",
          Source.source("ui/PaneWire.qml").indexOf("1000000 + pane.makeExecPendingId") < 0, true)

    // The two-byte shebang read left QML for the backend: no Process runs head from the UI.
    check("no shebang Process remains in Pane.qml", Source.source("ui/Pane.qml").indexOf("shebangProc") < 0, true)
    check("the check asks the backend instead", Source.source("ui/Pane.qml").indexOf('c: "shebang"') >= 0, true)

    // Only the newest id on the asked path lands, so a late answer never arms a later file.
    check("an older id on the asked path is refused", Permissions.landsShebang("/d/a.sh", 1, "/d/a.sh", 2), false)
    check("and the newest id on it lands", Permissions.landsShebang("/d/a.sh", 2, "/d/a.sh", 2), true)
    check("and the newest id on another path is refused", Permissions.landsShebang("/d/b.sh", 2, "/d/a.sh", 2), false)
    check("Pane.qml lands through the helper", Source.source("ui/Pane.qml").indexOf("Permissions.landsShebang") >= 0, true)
    // One note names reasoned and refused rows together, and nothing when all apply.
    var noted = { modes: ["0644", "0644", ""], reasons: ["", "Read-only: you are not the owner.", "Gone."], skipped: [], pending: 0 }
    check("reasoned and refused rows share one note",
        Permissions.inspectNote(noted, ["/d/a.txt", "/d/b.txt", "/d/c.txt"]),
        "2 items keep their modes because they cannot be changed: b.txt, c.txt")
    check("and an applicable selection names nothing",
        Permissions.inspectNote({ modes: ["0644"], reasons: [""], skipped: [], pending: 0 }, ["/d/a.txt"]), "")
    // Every card that centres itself takes a whole size and origin from Theme, so none sits on a half pixel in an odd or an even window.
    var cards = [["MenuActionDialog", "card"], ["ConvertDialog", "card"], ["NetworkDialog", "card"], ["OpenWithDialog", "card"], ["TrashConfirm", "card"],
                 ["CollideConfirm", "card"], ["KeymapSheet", "card"], ["SettingsPanel", "card"], ["PermissionsDialog", "card"], ["Preview", "surface"]]
    for (var c = 0; c < cards.length; c++) {
        var cardName = cards[c][0]
        // The card object's own bindings, up to its matching brace and without its child objects.
        var cardBlock = cardOwnBindings(Source.source("ui/" + cardName + ".qml"), cards[c][1])
        check(cardName + " sizes its card through Theme.cardSpan", cardBlock.indexOf("Theme.cardSpan(") >= 0, true)
        check(cardName + " places its card through Theme.cardOrigin", cardBlock.indexOf("Theme.cardOrigin(") >= 0, true)
        check(cardName + " leaves no centred anchor on its card", cardBlock.indexOf("centerIn") < 0, true)
    }
    // The scan itself: a grouped anchor, a centring after a child and a lookalike inside a child are told apart.
    var grouped = "Rectangle {\n id: card\n x: Theme.cardOrigin(1, 2)\n anchors { centerIn: parent }\n}"
    var afterChild = "Rectangle {\n id: card\n Text { text: \"a\" }\n anchors.centerIn: parent\n}"
    var inChild = "Rectangle {\n id: card\n x: 1 // {\n Text { text: \"}\"; anchors.centerIn: parent }\n Item { anchors { centerIn: parent } }\n}"
    check("a grouped centerIn is the card's own", cardOwnBindings(grouped, "card").indexOf("centerIn") >= 0, true)
    check("a centerIn after a child is the card's own", cardOwnBindings(afterChild, "card").indexOf("centerIn") >= 0, true)
    check("a centerIn inside a child is not the card's", cardOwnBindings(inChild, "card").indexOf("centerIn"), -1)
    // Unstripped, the comment's brace would end the card before y and the string's brace before width.
    var braces = "Rectangle {\n id: card\n x: 1 // }\n y: 2\n property string s: \"}\"\n width: 3\n}"
    var braceOwn = cardOwnBindings(braces, "card")
    check("a brace in a comment moves nothing", braceOwn.indexOf("y: 2") >= 0, true)
    check("a brace in a string moves nothing", braceOwn.indexOf("width: 3") >= 0, true)
}
