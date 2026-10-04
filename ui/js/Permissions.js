.pragma library

// Keeps the one-shot Make executable id clear of the dialog's own batch ids; both QML readers add their pending id to it.
var MAKE_EXEC_ID = 1000000

// Only the newest id on the asked path lands, so a late answer never arms a later file.
function landsShebang(path, id, asked, currentId) {
    return path === asked && id === currentId
}

// Sample input: "644" or "0644"; invalid text remains in the input until corrected.
function parse(text) {
    return /^(0?[0-7]{3})$/.test(String(text)) ? parseInt(text, 8) : -1
}
function octal(value) { return ("0000" + value.toString(8)).slice(-4) }
function toggle(text, bit) {
    var value = parse(text)
    return value < 0 ? text : octal(value ^ bit)
}

// Sample input: (["0644", "4644"], ["", "Read-only: setuid bit is present."]); one row per permission bit, in grid order.
// A file the card skips (a mode parse refuses, or a reason) neither sets nor mixes a bit.
function summarize(modes, reasons) {
    var values = []
    for (var i = 0; i < modes.length; i++) {
        var value = parse(modes[i])
        if (value >= 0 && !(reasons && reasons[i]))
            values.push(value)
    }
    var bits = []
    var anyMixed = false
    for (var b = 0; b < 9; b++) {
        var mask = 1 << (8 - b)
        var on = true
        var off = true
        for (var j = 0; j < values.length; j++) {
            if (!(values[j] & mask))
                on = false
            else
                off = false
        }
        var mixed = !on && !off
        if (mixed)
            anyMixed = true
        bits.push({ mask: mask, on: values.length > 0 && on, mixed: mixed })
    }
    return { bits: bits, mixed: anyMixed }
}

function mixedNote() { return "Mixed boxes keep each file's own bit unless you change them." }

// A mode with special bits is named in the backend's own words, never dropped on parse -1.
function specialReason(text) {
    var digits = String(text || "")
    if (!/^[1-7][0-7]{3}$/.test(digits))
        return ""
    var special = parseInt(digits.charAt(0), 8)
    var label = (special & 4) !== 0 ? "setuid" : (special & 2) !== 0 ? "setgid" : "sticky"
    return "Read-only: " + label + " bit is present."
}

function leafOf(path) {
    var text = String(path || "")
    var cut = text.lastIndexOf("/")
    return cut < 0 ? text : text.substring(cut + 1)
}

// Modes land in arrival order in place; this answers true once per selection, on the last reply.
function noteMode(store, at, path, message) {
    if (message.ok === true) {
        store.modes[at] = message.mode
        store.reasons[at] = message.reason || ""
    } else {
        // A refused inspect rides the reasons once, in the backend's own words.
        var why = message.error || "Could not change permissions."
        store.modes[at] = ""
        store.reasons[at] = why
        store.skipped.push({ path: path, why: why })
    }
    store.pending -= 1
    return store.pending <= 0
}

// One note names every row the grid cannot change, reasoned and refused together.
function inspectNote(store, paths) {
    var list = []
    var reasons = (store && store.reasons) || []
    for (var i = 0; i < paths.length; i++) {
        var why = reasons[i] || ""
        if (why.length > 0) list.push({ path: paths[i], why: why })
    }
    return list.length === 0 ? "" : skipNote(list)
}

// Most names a skip line lists before it counts the rest.
var SKIP_NAMES_SHOWN = 3

// Sample input: "Read-only: setgid bit is present." answers "setgid"; any other reason answers "".
function specialLabel(why) {
    var found = /^Read-only: (setuid|setgid|sticky) bit is present\.$/.exec(String(why))
    return found ? found[1] : ""
}

function skipKind(why) {
    if (specialLabel(why) !== "")
        return "special"
    return why === "Read-only: you are not the owner." ? "owner" : "other"
}

// Sample input: "Read-only: mount is read-only." answers "Read-only, mount is read-only.", so a reason never adds a colon of its own.
function oneClause(why) {
    return String(why).replace(/:\s*/g, ", ")
}

// One sentence per skip line with at most one colon: "special.txt keeps its mode because its setuid bit is set."
// or "2 items keep their modes because a special bit is set: a, b".
function skipNote(skipped) {
    var list = skipped || []
    if (list.length === 0)
        return ""
    var kinds = list.map(function (item) { return skipKind(item.why) })
    var same = kinds.every(function (kind) { return kind === kinds[0] })
    if (list.length === 1) {
        var leaf = leafOf(list[0].path)
        if (kinds[0] === "special")
            return leaf + " keeps its mode because its " + specialLabel(list[0].why) + " bit is set."
        if (kinds[0] === "owner")
            return leaf + " keeps its mode because you do not own it."
        return leaf + " keeps its mode: " + oneClause(list[0].why)
    }
    var names = []
    for (var i = 0; i < list.length && i < SKIP_NAMES_SHOWN; i++)
        names.push(leafOf(list[i].path))
    var tail = list.length > SKIP_NAMES_SHOWN ? " and " + (list.length - SKIP_NAMES_SHOWN) + " more" : ""
    var cause = same && kinds[0] === "special" ? "a special bit is set"
        : same && kinds[0] === "owner" ? "you do not own them" : "they cannot be changed"
    return list.length + " items keep their modes because " + cause + ": " + names.join(", ") + tail
}

// A batch with a skip names every count and reason, never a plain success.
function multiResult(changed, total, skipped) {
    var list = skipped || []
    if (list.length === 0)
        return "Permissions changed."
    var shown = []
    for (var i = 0; i < list.length && i < 3; i++)
        shown.push(leafOf(list[i].path) + ": " + list[i].why)
    var tail = list.length > 3 ? "; and " + (list.length - 3) + " more" : ""
    var left = list.length === 1 ? "1 left alone: " : list.length + " left alone: "
    return "Permissions changed for " + changed + " of " + total + "; " + left + shown.join("; ") + tail
}
