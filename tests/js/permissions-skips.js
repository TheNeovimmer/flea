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
    check("a selection of only skipped files shows every box off",
        Permissions.summarize(["4644", "2755"]).bits.every(function (b) { return !b.on && !b.mixed }), true)
    // The skipped-item line is one sentence with at most one colon, composed here and never from the backend's own colons.
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
    check("a backend reason's own colon reads as a comma",
        Permissions.skipNote([{ path: "/d/a.txt", why: "Read-only: mount is read-only." }]), "a.txt keeps its mode: Read-only, mount is read-only.")
    check("several special-bit skips share one cause and list the names",
        Permissions.skipNote([{ path: "/d/a", why: setuid }, { path: "/d/b", why: "Read-only: sticky bit is present." }]),
        "2 items keep their modes because a special bit is set: a, b")
    check("several foreign files share one cause",
        Permissions.skipNote([{ path: "/d/a", why: owner }, { path: "/d/b", why: owner }]),
        "2 items keep their modes because you do not own them: a, b")
    check("mixed causes fall back to the plain cause",
        Permissions.skipNote([{ path: "/d/a", why: setuid }, { path: "/d/b", why: "Gone." }]),
        "2 items keep their modes because they cannot be changed: a, b")
    check("four skips show three names and an and-1-more tail",
        Permissions.skipNote([{ path: "/d/a.txt", why: setuid }, { path: "/d/b.txt", why: setuid },
                              { path: "/d/c.txt", why: setuid }, { path: "/d/d.txt", why: setuid }]),
        "4 items keep their modes because a special bit is set: a.txt, b.txt, c.txt and 1 more")
    var lines = [Permissions.skipNote([{ path: "/d/a", why: setuid }]),
                 Permissions.skipNote([{ path: "/d/a", why: owner }, { path: "/d/b", why: setuid }]),
                 Permissions.skipNote([{ path: "/d/a", why: "Gone." }])]
    check("every skip line holds at most one colon and one sentence",
        lines.every(function (line) { return line.split(":").length - 1 <= 1 && line.split(". ").length === 1 }), true)
}
