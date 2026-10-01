.import "../../ui/js/Permissions.js" as Permissions
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
}
