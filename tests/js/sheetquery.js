.import "../../ui/js/SheetQuery.js" as SheetQuery

function run(check) {
    // Candidates arrive in section order: the keymap's actions, then the rail's places and
    // the recent files, each reading "Open <name>" with its "in <where>". Menu rows join
    // section 1 once their provider plumbing exists; the rank already holds their place.
    function candidate(label, keys, section, where) {
        return { label: label, keys: keys, section: section, where: where || "" }
    }
    var rows = [
        candidate("move", "j k", 0),
        candidate("trash", "dd", 0),
        candidate("menu", "m", 0),
        candidate("Open Downloads", "", 1, "Places"),
        candidate("Open Documents", "", 1, "Places"),
        candidate("Open receipt.pdf", "", 2, "Downloads")
    ]
    // At rest the sheet draws whole: an empty query filters nothing.
    check("an empty query keeps every row", SheetQuery.rank(rows, "").length, 6)
    check("and keeps their order", SheetQuery.rank(rows, "  ")[0].label, "move")
    // A label match is case-insensitive and keeps section order among its own.
    var open = SheetQuery.rank(rows, "open")
    check("a label substring matches", open.length, 3)
    check("section order holds among matches", open.map(function (row) { return row.label }).join("|"),
          "Open Downloads|Open Documents|Open receipt.pdf")
    check("upper case matches too", SheetQuery.rank(rows, "OPEN").length, 3)
    // A place whose name the query matches exactly ranks first, whatever section it is in.
    var exact = SheetQuery.rank(rows, "menu")
    check("an exact label match ranks first", exact[0].label, "menu")
    var place = SheetQuery.rank(rows, "Open Documents")
    check("an exact place name ranks first", place[0].label, "Open Documents")
    // Keys match when no label does: the cap is what half the sheet is read by.
    var keys = SheetQuery.rank(rows, "dd")
    check("a keys match answers", keys.length, 1)
    check("with the row it names", keys[0].label, "trash")
    // A query matching nothing lists nothing rather than the whole sheet.
    check("no match is an empty sheet", SheetQuery.rank(rows, "zzz").length, 0)
    check("a keys-only miss is empty too", SheetQuery.rank(rows, "Open ^z").length, 0)
}
