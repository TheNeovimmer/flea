.pragma library

.import "Recent.js" as Recent

// The keymap sheet's query filter: the field appears on the first typed key, so the sheet
// at rest stays the generated sheet. Candidates arrive in section order, actions (0), the
// cursor row's menu rows and leaves hidden rows included (1), places (2) and recent files
// (3), each place and file reading "Open <name>" with muted "in <where>". A destructive row
// keeps its confirm, because the query only finds rows. Imports no QML, so tests drive it.

// Sample candidates: [{ label: "trash", keys: "dd", section: 0 },
//                      { label: "Open Downloads", keys: "", section: 2, where: "Places" }]
// Sample query: "down" matches "Open Downloads" but not "trash".
var RESULT_LIMIT = 50

// A key that works in one place only says where, as the tag digits do in Tags, from the key
// table's own context. Listing is the sheet's own place and multi-context works in several.
function whereForContext(context) {
    var text = String(context || "")
    if (text.length === 0 || text === "listing" || text.indexOf(",") >= 0) {
        return ""
    }
    return text
}

// Section 0 from the generated sheet. Imports no Keymap: the caller hands in sheetFor rows.
function actionCandidates(sheetRows) {
    var out = []
    var rows = sheetRows || []
    for (var i = 0; i < rows.length; i++) {
        out.push({ label: String(rows[i].label || ""), keys: String(rows[i].keys || ""),
            section: 0, where: whereForContext(rows[i].context),
            action: String(rows[i].action || ""), disabled: false, danger: false })
    }
    return out
}

// Section 1 from the menu's own model, hidden rows included. Tops keep a cap when the
// hint names one, leaves read "<leaf> in <flyout>" with no cap, disabled rows never run.
function menuCandidates(entries, hintFor) {
    var out = []
    var rows = entries || []
    var hint = typeof hintFor === "function" ? hintFor : function () { return "" }
    for (var i = 0; i < rows.length; i++) {
        var entry = rows[i]
        if (!entry || entry.separator === true) {
            continue
        }
        var action = String(entry.action || entry.id || "")
        out.push({ label: String(entry.label || ""), keys: String(hint(action) || ""),
            section: 1, where: "", menuAction: actionWithSub(action, ""),
            disabled: entry.disabled === true, danger: entry.danger === true })
        var sub = entry.submenu || []
        for (var j = 0; j < sub.length; j++) {
            if (!sub[j] || sub[j].separator === true) {
                continue
            }
            var leafId = String(sub[j].id || "")
            out.push({ label: String(sub[j].label || ""), keys: "",
                section: 1, where: String(entry.label || ""),
                menuAction: actionWithSub(action, leafId),
                disabled: entry.disabled === true || sub[j].disabled === true,
                danger: entry.danger === true })
        }
    }
    return out
}

function actionWithSub(action, leafId) {
    return leafId.length > 0 ? action + ":" + leafId : action
}

// The group name the rail shows: Favorites, Places, or the network/device group.
function placeWhere(entry) {
    var group = String((entry && entry.group) || "")
    if (group === "favourite" || group === "favorite") {
        return "Favorites"
    }
    if (group === "network") {
        return "Network"
    }
    if (group === "device") {
        return "Devices"
    }
    return "Places"
}

// Section 2 from the rail's entries. NAME rides beside "Open <name>", because an exact
// place match compares the name and not the label, so "? trash Enter" opens Trash first.
function placeCandidates(railEntries) {
    var out = []
    var rows = railEntries || []
    for (var i = 0; i < rows.length; i++) {
        var entry = rows[i]
        if (!entry || String(entry.label || "").length === 0) {
            continue
        }
        if (String(entry.kind || "") === "recent") {
            continue
        }
        out.push({ label: "Open " + entry.label, name: String(entry.label),
            keys: "", section: 2, where: placeWhere(entry), railIndex: i, entry: entry })
    }
    return out
}

function abbrevParent(parent, home) {
    var text = String(parent || "")
    var root = String(home || "")
    if (root.length > 0 && (text === root || text.indexOf(root + "/") === 0)) {
        return "~" + text.substring(root.length)
    }
    return text
}

// Section 3 from the xbel source the Recent place uses, read once per query line, bounded
// by Recent.LIMIT with no per-entry stat.
function recentCandidates(recentPaths, home) {
    var out = []
    var rows = recentPaths || []
    var bound = Math.min(rows.length, Recent.LIMIT)
    for (var i = 0; i < bound; i++) {
        var path = String(rows[i] || "")
        if (path.length === 0) {
            continue
        }
        var leaf = Recent.nameOf(path)
        var parent = abbrevParent(Recent.locationOf(path), home)
        out.push({ label: "Open " + leaf, keys: "", section: 3,
            where: parent, path: path })
    }
    return out
}

// The matched run the specimen washes. Case-insensitive substring, null when none.
function matchOf(label, query) {
    var text = String(label || "").toLowerCase()
    var needle = String(query || "").trim().toLowerCase()
    if (needle.length === 0) {
        return null
    }
    var at = text.indexOf(needle)
    if (at < 0) {
        return null
    }
    return { start: at, length: needle.length }
}

function rank(candidates, query) {
    var needle = String(query || "").trim().toLowerCase()
    var list = candidates || []
    if (needle.length === 0) {
        return list.slice(0, RESULT_LIMIT)
    }
    var exactPlace = []
    var exact = []
    var matched = []
    var keyed = []
    for (var i = 0; i < list.length; i++) {
        var label = String(list[i].label || "").toLowerCase()
        var keys = String(list[i].keys || "").toLowerCase()
        var name = String(list[i].name || "").toLowerCase()
        // An exact NAME match ranks first, so "? trash Enter" opens Trash.
        if (name.length > 0 && name === needle) {
            exactPlace.push(list[i])
        } else if (label === needle) {
            exact.push(list[i])
        } else if (label.indexOf(needle) >= 0) {
            matched.push(list[i])
        } else if (keys.length > 0 && keys.indexOf(needle) >= 0) {
            keyed.push(list[i])
        }
    }
    return exactPlace.concat(exact, matched, keyed).slice(0, RESULT_LIMIT)
}

// Enter runs the highlighted row: an action as its key, a menu row as the menu, a place
// like a rail click, a recent file like Enter on its row, a destructive row via its confirm.
function dispatch(candidate) {
    var row = candidate || {}
    if (row.disabled === true) {
        return { kind: "disabled" }
    }
    if (row.section === 0 && String(row.action || "").length > 0) {
        return { kind: "action", action: String(row.action) }
    }
    if (row.section === 1 && String(row.menuAction || "").length > 0) {
        if (row.danger === true) {
            return { kind: "confirm", menuAction: String(row.menuAction) }
        }
        return { kind: "menu", menuAction: String(row.menuAction) }
    }
    if (row.section === 2 && row.entry) {
        return { kind: "place", railIndex: row.railIndex, entry: row.entry }
    }
    if (row.section === 3 && String(row.path || "").length > 0) {
        return { kind: "recent", path: String(row.path) }
    }
    return { kind: "none" }
}

// A sheet menu row snapshots first for the current selection, then activates.
function runMenu(holder, menuAction) {
    holder.menuActions.snapshot()
    holder.menuActions.activate(menuAction, true)
}
