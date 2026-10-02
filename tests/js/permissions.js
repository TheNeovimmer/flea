.import "../../ui/js/Permissions.js" as Permissions
.import "../../ui/js/Ops.js" as Ops
.import "../../ui/js/Menu.js" as Menu
.import "sourcefixture.js" as Source
function run(check) {
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
    check("one skip reads singular",
        Permissions.skipNote([{ path: "/d/a.txt", why: "Gone." }]),
        "1 item cannot be changed: a.txt: Gone.")
    check("four skips show three with an and-1-more tail",
        Permissions.skipNote([{ path: "/d/a.txt", why: "r1" }, { path: "/d/b.txt", why: "r2" },
                              { path: "/d/c.txt", why: "r3" }, { path: "/d/d.txt", why: "r4" }]),
        "4 items cannot be changed: a.txt: r1; b.txt: r2; c.txt: r3; and 1 more")
    check("four skips ride multiResult with the same tail",
        Permissions.multiResult(1, 5, [{ path: "/d/a.txt", why: "r1" }, { path: "/d/b.txt", why: "r2" },
                                       { path: "/d/c.txt", why: "r3" }, { path: "/d/d.txt", why: "r4" }]),
        "Permissions changed for 1 of 5; 4 left alone: a.txt: r1; b.txt: r2; c.txt: r3; and 1 more")

    // noteMode answers done once in 5000 replies, on the last one.
    var store = { modes: [], reasons: [], skipped: [], pending: 5000 }
    var done = false
    var early = false
    for (var i = 0; i < 5000; i++) {
        done = Permissions.noteMode(store, i, "/f" + i, { ok: true, mode: "0644", reason: "" })
        if (done && i + 1 < 5000) early = true
    }
    check("noteMode answers done once across 5000 replies", done + "|" + store.modes.length, "true|5000")
    check("and done answers only on the last reply", early + "|" + done, "false|true")
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
        "2 items cannot be changed: b.txt: Read-only: you are not the owner.; c.txt: Gone.")
    check("and an applicable selection names nothing",
        Permissions.inspectNote({ modes: ["0644"], reasons: [""], skipped: [], pending: 0 }, ["/d/a.txt"]), "")
}
