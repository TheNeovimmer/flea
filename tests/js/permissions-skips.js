.import "../../ui/js/Permissions.js" as Permissions

// What the several-items card counts and says about the files it will not change, split out of permissions.js at its cap.
function run(check) {
    // A file the card skips neither sets nor mixes a bit: a.txt 0644 beside special.txt 4644 reads Owner R/W, Group R, Everyone R, and no bar.
    var skipping = Permissions.summarize(["0644", "4644"], ["", "Read-only: setuid bit is present."])
    check("a setuid file mixes no bit and the grid shows a.txt's bits",
        skipping.bits.map(function (b) { return b.on ? "on" : b.mixed ? "some" : "off" }).join(","),
        "on,on,off,on,off,off,on,off,off")
    check("and the summary reports no mixed bit", skipping.mixed, false)
    check("a setuid mode alone counts without its reason too",
        Permissions.summarize(["0644", "4644"]).bits.map(function (b) { return b.on ? "on" : b.mixed ? "some" : "off" }).join(","),
        "on,on,off,on,off,off,on,off,off")
    check("a setgid or sticky mode is skipped the same way",
        Permissions.summarize(["0644", "2755", "1755"]).mixed, false)
    check("a refused inspect (an empty mode) is skipped too",
        Permissions.summarize(["0644", ""]).bits[0].on, true)
    check("a reasoned row (not the owner) neither sets nor mixes a bit",
        Permissions.summarize(["0644", "0755"], ["", "Read-only: you are not the owner."]).mixed, false)
    check("a reasoned row leaves the other file's bits as they are",
        Permissions.summarize(["0644", "0755"], ["", "Read-only: you are not the owner."]).bits[2].on, false)
    // Permissions040: when no selected file can change, the boxes show the files' own bits and the card is not editable.
    var allSkipped = Permissions.summarize(["4644", "4644"], ["Read-only: setuid bit is present.", "Read-only: setuid bit is present."])
    check("two setuid files both 4644 read rw-r--r-- and change nothing",
        allSkipped.bits.map(function (b) { return b.on ? "on" : b.mixed ? "some" : "off" }).join(",") + "|" + allSkipped.changeable,
        "on,on,off,on,off,off,on,off,off|false")
    var mixedSkipped = Permissions.summarize(["4644", "2755"])
    check("skipped files that differ show a bar where they differ",
        mixedSkipped.bits.map(function (b) { return b.on ? "on" : b.mixed ? "some" : "off" }).join(",") + "|" + mixedSkipped.mixed + "|" + mixedSkipped.changeable,
        "on,on,some,on,off,some,on,off,some|true|false")
    check("a refused inspect shows no bit and changes nothing",
        Permissions.summarize(["", ""]).bits.every(function (b) { return !b.on && !b.mixed }) + "|" + Permissions.summarize(["", ""]).changeable, "true|false")
    check("one changeable file keeps the card editable and shows only its bits",
        Permissions.summarize(["0644", "4755"]).changeable + "|" + Permissions.summarize(["0644", "4755"]).bits[2].on, "true|false")
    // The words a skip line composes hold at most one colon; a lone other reason is quoted after it as the backend wrote it.
    var setuid = "Read-only: setuid bit is present."
    var owner = "Read-only: you are not the owner."
    check("one special-bit skip reads as one sentence",
        Permissions.skipNote([{ path: "/d/special.txt", why: setuid }]),
        "special.txt keeps its mode because its setuid bit is set.")
    check("a setgid and a sticky skip name their own bit",
        Permissions.skipNote([{ path: "/d/a", why: "Read-only: setgid bit is present." }]) + "|"
        + Permissions.skipNote([{ path: "/d/b", why: "Read-only: sticky bit is present." }]),
        "a keeps its mode because its setgid bit is set.|b keeps its mode because its sticky bit is set.")
    check("a foreign file reads as one sentence",
        Permissions.skipNote([{ path: "/d/a.txt", why: owner }]), "a.txt keeps its mode because you do not own it.")
    check("an unnamed reason keeps its one colon",
        Permissions.skipNote([{ path: "/d/a.txt", why: "Gone." }]), "a.txt keeps its mode: Gone.")
    check("any other reason is quoted as the backend wrote it, path colons included",
        Permissions.skipNote([{ path: "/d/a.txt", why: "Could not read /mnt/c:d." }]), "a.txt keeps its mode: Could not read /mnt/c:d.")
    check("several special-bit skips share one cause and list the names",
        Permissions.skipNote([{ path: "/d/a", why: setuid }, { path: "/d/b", why: "Read-only: sticky bit is present." }]),
        "2 items keep their modes because a special bit is set: a, b.")
    check("several foreign files share one cause",
        Permissions.skipNote([{ path: "/d/a", why: owner }, { path: "/d/b", why: owner }]),
        "2 items keep their modes because you do not own them: a, b.")
    check("mixed causes fall back to the plain cause",
        Permissions.skipNote([{ path: "/d/a", why: setuid }, { path: "/d/b", why: "Gone." }]),
        "2 items keep their modes because they cannot be changed: a, b.")
    check("four skips show three names and an and-1-more tail",
        Permissions.skipNote([{ path: "/d/a.txt", why: setuid }, { path: "/d/b.txt", why: setuid },
                              { path: "/d/c.txt", why: setuid }, { path: "/d/d.txt", why: setuid }]),
        "4 items keep their modes because a special bit is set: a.txt, b.txt, c.txt and 1 more.")
    var lines = [Permissions.skipNote([{ path: "/d/a", why: setuid }]),
                 Permissions.skipNote([{ path: "/d/a", why: owner }, { path: "/d/b", why: setuid }]),
                 Permissions.skipNote([{ path: "/d/a", why: "Gone." }]),
                 Permissions.skipNote([{ path: "/d/a", why: "Gone" }]),
                 Permissions.multiResult([{ path: "/d/special.txt", why: setuid }]),
                 Permissions.multiResult([{ path: "/d/a", why: setuid }, { path: "/d/b", why: setuid }, { path: "/d/c", why: setuid }, { path: "/d/d", why: setuid }])]
    check("every skip line holds at most one colon and ends in one period",
        lines.every(function (line) { return line.split(":").length - 1 <= 1 && line.split(". ").length === 1 && /[^.]\.$/.test(line) }), true)
    // The post-Apply line names what was kept and never why or how many changed: the card's note said the reason before Apply, and the status bar cuts a long line in the middle.
    check("a lone special-bit skip after Apply names the file kept",
        Permissions.multiResult([{ path: "/d/special.txt", why: setuid }]),
        "special.txt kept its mode.")
    check("a lone foreign file after Apply names the file kept",
        Permissions.multiResult([{ path: "/d/a.txt", why: owner }]),
        "a.txt kept its mode.")
    check("several skips after Apply count the items kept",
        Permissions.multiResult([{ path: "/d/a", why: setuid }, { path: "/d/b", why: setuid }, { path: "/d/c", why: setuid }]),
        "3 items kept their modes.")
    check("a backend reason is never quoted after Apply, so no colon of its own rides the line",
        Permissions.multiResult([{ path: "/d/a.txt", why: "Could not read /mnt/c:d." }]),
        "a.txt kept its mode.")
    check("a line never carries a changed-for clause, even when nothing changed",
        Permissions.multiResult([{ path: "/d/a.txt", why: "Gone" }]) + "|"
        + Permissions.multiResult([{ path: "/d/special.txt", why: setuid }, { path: "/d/x-special.txt", why: setuid }]),
        "a.txt kept its mode.|2 items kept their modes.")
    check("an untouched batch is still the plain success", Permissions.multiResult([]), "Permissions changed.")
}
