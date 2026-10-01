.pragma library

// The keymap sheet's query filter: the field appears on the first typed key rather than as a
// permanent field, so the sheet at rest stays the generated sheet it always was. Candidates
// arrive in section order, the keymap's actions (section 0), then the cursor row's menu rows
// and flyout leaves (section 1, hidden rows included), then the rail's places and the recent
// files (sections 2 and 3), each place and file reading "Open <name>" with its muted
// "in <where>". A destructive row keeps its confirm, because the query only finds rows.
// Imports no QML, so tests/js/sheetquery.js drives it with no window.

// Sample candidates: [{ label: "trash", keys: "dd", section: 0 },
//                      { label: "Open Downloads", keys: "", section: 2, where: "Places" }]
// Sample query: "down" matches "Open Downloads" but not "trash".
function rank(candidates, query) {
    var needle = String(query || "").trim().toLowerCase()
    var list = candidates || []
    if (needle.length === 0) {
        return list.slice()
    }
    var exact = []
    var matched = []
    var keyed = []
    for (var i = 0; i < list.length; i++) {
        var label = String(list[i].label || "").toLowerCase()
        var keys = String(list[i].keys || "").toLowerCase()
        // A place whose name the query matches exactly ranks first, whatever section holds it.
        if (label === needle) {
            exact.push(list[i])
        } else if (label.indexOf(needle) >= 0) {
            matched.push(list[i])
        } else if (keys.length > 0 && keys.indexOf(needle) >= 0) {
            keyed.push(list[i])
        }
    }
    return exact.concat(matched, keyed)
}
