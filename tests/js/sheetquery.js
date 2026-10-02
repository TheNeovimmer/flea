.import "../../ui/js/SheetQuery.js" as SheetQuery

function run(check) {
    // Candidates arrive in section order, each place and file reading "Open <name>".
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
    // An exact NAME match ranks first, above an exact action label.
    var trashRows = [
        { label: "trash", keys: "dd", section: 0, where: "", action: "trash" },
        { label: "Open Trash", name: "Trash", keys: "", section: 2, where: "Places",
          railIndex: 0, entry: { label: "Trash" } }
    ]
    check("an exact place name beats an exact action label",
          SheetQuery.rank(trashRows, "trash")[0].label, "Open Trash")
    // Sections hold their order inside each bucket: actions, menu rows, places, recents.
    var sections = [
        candidate("open sesame", "", 0),
        candidate("Open Sesame", "", 1),
        candidate("Open Sesame", "", 2),
        candidate("Open Sesame", "", 3)
    ]
    check("section order holds across all four sections",
          SheetQuery.rank(sections, "sesame").map(function (row) { return row.section }).join("|"), "0|1|2|3")
    // The result list stays bounded and the cursor starts on the first row, the menu lift.
    var many = []
    for (var i = 0; i < 80; i++) {
        many.push(candidate("open " + i, "", i % 4))
    }
    check("the list is bounded", SheetQuery.rank(many, "open").length <= SheetQuery.RESULT_LIMIT, true)
    // The matched run is what the sheet washes.
    var at = SheetQuery.matchOf("Compress to .zip", "comp")
    check("a match names its run start", at && at.start, 0)
    check("and its run length", at && at.length, 4)
    check("a miss washes nothing", SheetQuery.matchOf("trash", "zzz"), null)
    // A key that works in one place only says where, from the key table's own context.
    check("listing names no place", SheetQuery.whereForContext("listing"), "")
    check("a multi-context key names none either", SheetQuery.whereForContext("rail,menu"), "")
    check("a single place is named", SheetQuery.whereForContext("media"), "media")

    // A sheet menu row snapshots first, so the activate meets the selection.
    var calls = []
    var holder = { menuActions: {
        snapshot: function () { calls.push("snapshot") },
        activate: function (action, selected) { calls.push("activate:" + action + ":" + selected) }
    } }
    SheetQuery.runMenu(holder, "trash")
    check("the sheet snapshots before it activates", calls.join(","), "snapshot,activate:trash:true")
}
