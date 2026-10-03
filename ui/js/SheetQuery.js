.pragma library
.import "Input.js" as Input

.import "Recent.js" as Recent
.import "Swap.js" as Swap
.import "Places.js" as Places
.import "Focus.js" as Focus

// The sheet's four-section query filter; imports no QML, so tests drive it.

// Sample query: "down" matches "Open Downloads" but not "trash".
var RESULT_LIMIT = 50

// A key that works in one place only says where, from the key table's own context.
function whereForContext(context) {
    var text = String(context || "")
    if (text.length === 0 || text === "listing" || text.indexOf(",") >= 0) {
        return ""
    }
    return text
}

// Section 0 from the generated sheet; the caller hands in sheetFor rows.
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

// Section 1 from the menu's own model, hidden rows included; disabled rows never run.
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

// Section 2 from the rail's entries; an exact NAME match ranks first.
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

// Section 3 from the xbel source, read once per query line and bounded by Recent.LIMIT.
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

// Sample input: a key row {action: "trash"} then a menu row {menuAction: "trash"} keeps the key row only.
// One action, one row: the key row stays, and a disabled menu row's verdict rides on it, so a folder that refuses Rename refuses it here.
function unique(candidates) {
    var at = {}
    var out = []
    var list = candidates || []
    for (var i = 0; i < list.length; i++) {
        var run = String(list[i].action || list[i].menuAction || "")
        if (run.length === 0) {
            out.push(list[i])
        } else if (at[run] === undefined) {
            at[run] = out.length
            out.push(list[i])
        } else if (list[i].disabled === true && out[at[run]].section === 0 && out[at[run]].disabled !== true) {
            var held = {}
            for (var field in out[at[run]]) {
                held[field] = out[at[run]][field]
            }
            held.disabled = true
            held.menuAction = list[i].menuAction
            out[at[run]] = held
        }
    }
    return out
}

function rank(candidates, query) {
    var needle = String(query || "").trim().toLowerCase()
    var list = unique(candidates)
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

// Enter runs the highlighted row as its own surface would.
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

// Enter skips the key gate, so Swap.swallows refuses listing actions here while allowing navigation.
function runAction(holder, action, close) {
    if (Swap.swallows(holder.listInFlight, action)) {
        holder.message(Swap.LOADING, false)
        return
    }
    close()
    if (holder.sheetAction) holder.sheetAction(action)
    else Focus.dispatchAction(action, holder)
}

// Every menu row resolves its rows through the snapshot, so it refuses while a listing is out, unlike navigations.
function runMenu(holder, menuAction, close) {
    if (holder.listInFlight === true) {
        holder.message(Swap.LOADING, false)
        return
    }
    if (typeof close === "function")
        close()
    if (holder.sheetMenuAction) { holder.sheetMenuAction(menuAction); return }
    holder.menuActions.snapshot()
    holder.menuActions.activate(menuAction, true)
}

// Sample input: isPrintable("c") is true, isPrintable("\u007f") is false.
// The Delete keysym carries DEL as its text through libxkbcommon, so the bare range test would type it.
function isPrintable(text) {
    return Input.isPrintable(text)
}

// Sample input: isBareModifier(Qt.Key_Shift) is true, isBareModifier(Qt.Key_A) is false.
// A bare modifier carries no text, so without this the sheet would close under a shifted letter.
function isBareModifier(key) {
    return key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Alt
        || key === Qt.Key_AltGr || key === Qt.Key_Meta || key === Qt.Key_CapsLock
}

// Sample input: sheetKey("co", 2, 0, Qt.Key_Shift, "") is "ignore".
// The one decision the sheet's Keys.onPressed runs, so the handler owns no key meaning of its own.
function sheetKey(query, resultCount, cursor, key, text) {
    if (key === Qt.Key_Escape)
        return "close"
    if (String(query).length > 0) {
        if (key === Qt.Key_Up)
            return "up"
        if (key === Qt.Key_Down)
            return "down"
        if (key === Qt.Key_Return || key === Qt.Key_Enter)
            return "activate"
    }
    if (key === Qt.Key_Backspace)
        return String(query).length > 0 ? "backspace" : "close"
    if (isPrintable(text))
        return "type"
    // Delete edits nothing forward, so it is ignored rather than typed or closed on.
    if (key === Qt.Key_Delete || isBareModifier(key))
        return "ignore"
    return "close"
}

// Sample input: stepCursor(0, -1, 3) is 2, stepCursor(2, 1, 3) is 0.
// The cursor wraps at both ends; with no rows it parks at the first.
function stepCursor(cursor, delta, count) {
    if (!(count > 0))
        return 0
    return (((cursor + delta) % count) + count) % count
}

// Sample input: entries two favourites both labelled "src", decided with railIndex 1 answers 1.
// The rail rebuilds on its poll, so the row is resolved by the rail's own identity, never by label.
function placeIndex(entries, decided) {
    var list = entries || []
    var row = decided || {}
    var want = Places.railIdentity(row.entry)
    if (want.length === 0)
        return -1
    var at = Number(row.railIndex)
    if (at >= 0 && at < list.length && Places.railIdentity(list[at]) === want)
        return at
    for (var i = 0; i < list.length; i++) {
        if (Places.railIdentity(list[i]) === want)
            return i
    }
    return -1
}
