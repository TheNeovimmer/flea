.import "../../ui/js/SheetQuery.js" as SheetQuery
.import "../../ui/js/Swap.js" as Swap
.import "sourcefixture.js" as Source

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
    // An exact label outranks a substring match even when the substring stands first in section order.
    var exactRows = [candidate("menu bar", "", 0), candidate("menu", "m", 0)]
    check("an exact label outranks a substring match ahead of it",
          SheetQuery.rank(exactRows, "menu").map(function (row) { return row.label }).join("|"), "menu|menu bar")
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

    // A sheet menu row closes then snapshots and activates, but refuses while a listing is out.
    var calls = []
    var holder = { listInFlight: false,
        message: function (text, sticky) { calls.push("message:" + text + ":" + sticky) },
        menuActions: {
            snapshot: function () { calls.push("snapshot") },
            activate: function (action, selected) { calls.push("activate:" + action + ":" + selected) }
        } }
    SheetQuery.runMenu(holder, "trash", function () { calls.push("close") })
    check("the sheet closes before it snapshots", calls.join(","), "close,snapshot,activate:trash:true")
    var blocked = []
    var busy = { listInFlight: true,
        message: function (text, sticky) { blocked.push("message:" + text + ":" + sticky) },
        menuActions: {
            snapshot: function () { blocked.push("snapshot") },
            activate: function (action, selected) { blocked.push("activate:" + action + ":" + selected) }
        } }
    SheetQuery.runMenu(busy, "trash", function () { blocked.push("close") })
    check("a menu row refuses while a listing is out", blocked.join(","), "message:A directory is already loading.:false")

    // A printable key types into the query; DEL never does, so Delete types nothing invisible.
    check("a letter is printable", SheetQuery.isPrintable("c"), true)
    check("a space is printable", SheetQuery.isPrintable(" "), true)
    check("DEL is not printable", SheetQuery.isPrintable("\u007f"), false)
    check("empty is not printable", SheetQuery.isPrintable(""), false)
    check("two chars are not printable", SheetQuery.isPrintable("ab"), false)
    // A bare modifier press is no query edit and never closes the sheet, so a shifted letter types.
    check("Shift alone is a bare modifier", SheetQuery.isBareModifier(Qt.Key_Shift), true)
    check("Control alone is a bare modifier", SheetQuery.isBareModifier(Qt.Key_Control), true)
    check("Alt alone is a bare modifier", SheetQuery.isBareModifier(Qt.Key_Alt), true)
    check("AltGr alone is a bare modifier", SheetQuery.isBareModifier(Qt.Key_AltGr), true)
    check("Meta alone is a bare modifier", SheetQuery.isBareModifier(Qt.Key_Meta), true)
    check("CapsLock alone is a bare modifier", SheetQuery.isBareModifier(Qt.Key_CapsLock), true)
    check("Delete is no bare modifier", SheetQuery.isBareModifier(Qt.Key_Delete), false)
    check("Escape is no bare modifier", SheetQuery.isBareModifier(Qt.Key_Escape), false)
    // The key decision the sheet's Keys.onPressed runs: Esc clears a standing query before it closes.
    check("Esc clears a standing query", SheetQuery.sheetKey("co", 2, 0, Qt.Key_Escape, ""), "clear")
    check("Esc with none closes", SheetQuery.sheetKey("", 0, 0, Qt.Key_Escape, ""), "close")
    check("Up moves the cursor", SheetQuery.sheetKey("c", 3, 1, Qt.Key_Up, ""), "up")
    check("Down moves the cursor", SheetQuery.sheetKey("c", 3, 1, Qt.Key_Down, ""), "down")
    check("Return runs the row", SheetQuery.sheetKey("c", 3, 0, Qt.Key_Return, ""), "activate")
    check("Enter runs the row too", SheetQuery.sheetKey("c", 3, 0, Qt.Key_Enter, ""), "activate")
    check("Backspace shortens a query", SheetQuery.sheetKey("c", 1, 0, Qt.Key_Backspace, ""), "backspace")
    check("Backspace with none closes", SheetQuery.sheetKey("", 0, 0, Qt.Key_Backspace, ""), "close")
    check("a letter types", SheetQuery.sheetKey("", 0, 0, Qt.Key_C, "c"), "type")
    check("Shift alone is ignored", SheetQuery.sheetKey("co", 2, 0, Qt.Key_Shift, ""), "ignore")
    check("Shift first is ignored too", SheetQuery.sheetKey("", 0, 0, Qt.Key_Shift, ""), "ignore")
    check("Delete never types DEL", SheetQuery.sheetKey("co", 2, 0, Qt.Key_Delete, "\u007f"), "ignore")
    check("an unbound key closes", SheetQuery.sheetKey("co", 2, 0, Qt.Key_F1, ""), "close")
    // The cursor wraps at both ends, the way the sheet's arrows move.
    check("Up at the top wraps to the last", SheetQuery.stepCursor(0, -1, 3), 2)
    check("Down at the end wraps to the first", SheetQuery.stepCursor(2, 1, 3), 0)
    check("a middle step does not wrap", SheetQuery.stepCursor(1, -1, 3), 0)
    check("no rows parks the cursor", SheetQuery.stepCursor(0, 1, 0), 0)
    // The place lookup answers the rail's own index, never the first label match.
    var dupes = [
        { label: "src", group: "favourite", kind: "favourite", path: "/a/src", original: { label: "src", path: "/a/src" } },
        { label: "src", group: "favourite", kind: "favourite", path: "/b/src", original: { label: "src", path: "/b/src" } }
    ]
    var second = SheetQuery.placeCandidates(dupes).filter(function (row) { return row.railIndex === 1 })[0]
    check("the second src is offered", second.label, "Open src")
    check("the second src opens rail row 1", SheetQuery.placeIndex(dupes, SheetQuery.dispatch(second)), 1)
    var first = SheetQuery.placeCandidates(dupes).filter(function (row) { return row.railIndex === 0 })[0]
    check("the first src still opens rail row 0", SheetQuery.placeIndex(dupes, SheetQuery.dispatch(first)), 0)
    check("a gone row answers -1", SheetQuery.placeIndex([], SheetQuery.dispatch(second)), -1)
    // The listing gate the sheet's action branch owes: a row action refuses while a listing is out.
    check("trash refuses while a listing is out", SheetQuery.listingRefusal(true, "trash"), "A directory is already loading.")
    check("open still answers while a listing is out", SheetQuery.listingRefusal(true, "open"), "")
    check("at rest nothing refuses", SheetQuery.listingRefusal(false, "trash"), "")
    // A sheet menu row snapshots first, so the activate meets the selection.
    var calls2 = []
    var holder2 = { menuActions: {
        snapshot: function () { calls2.push("snapshot") },
        activate: function (action, selected) { calls2.push("activate:" + action + ":" + selected) }
    } }
    SheetQuery.runMenu(holder2, "trash")
    check("the sheet snapshots before it activates", calls2.join(","), "snapshot,activate:trash:true")
    // The sheet action arm lives in SheetQuery.runAction, so a swapped gate stays red.
    function stubHolder(inFlight) {
        var calls = []
        var holder = { listInFlight: inFlight, message: function (text, shown) { calls.push("message:" + text + ":" + shown) }, act: function (action) { calls.push("act:" + action) } }
        function close() { calls.push("close") }
        return { holder: holder, calls: calls, close: close }
    }
    check("SheetQuery.runAction exists", typeof SheetQuery.runAction, "function")
    var swallowed = stubHolder(true)
    if (typeof SheetQuery.runAction === "function") {
        SheetQuery.runAction(swallowed.holder, "trash", swallowed.close)
    }
    check("a swallowed action says loading with no close and no act", swallowed.calls.join(",") || "missing", "message:" + Swap.LOADING + ":false")
    var idle = stubHolder(false)
    if (typeof SheetQuery.runAction === "function") {
        SheetQuery.runAction(idle.holder, "trash", idle.close)
    }
    check("an idle action closes then acts", idle.calls.join(",") || "missing", "close,act:trash")
    var letThrough = stubHolder(true)
    if (typeof SheetQuery.runAction === "function") {
        SheetQuery.runAction(letThrough.holder, "open", letThrough.close)
    }
    check("an action the gate lets through acts while in flight", letThrough.calls.join(",") || "missing", "close,act:open")
    var sheetAction = Source.source("ui/KeymapSheet.qml")
    check("activateResult runs through SheetQuery.runAction", Source.slice(sheetAction, "function activateResult()", "// Directive 18").indexOf("SheetQuery.runAction") >= 0, true)
}
