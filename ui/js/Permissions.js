.pragma library

// Sample input: "644" or "0644"; invalid text remains in the input until corrected.
function parse(text) {
    return /^(0?[0-7]{3})$/.test(String(text)) ? parseInt(text, 8) : -1
}
function octal(value) { return ("0000" + value.toString(8)).slice(-4) }
function toggle(text, bit) {
    var value = parse(text)
    return value < 0 ? text : octal(value ^ bit)
}

// Sample input: ["0644", "0755"]; one row per permission bit, in grid order.
function summarize(modes) {
    var bits = []
    var anyMixed = false
    for (var b = 0; b < 9; b++) {
        var mask = 1 << (8 - b)
        var on = true
        var off = true
        for (var i = 0; i < modes.length; i++) {
            var value = parse(modes[i])
            if (value < 0 || !(value & mask))
                on = false
            if (value >= 0 && (value & mask))
                off = false
        }
        var mixed = modes.length > 1 && !on && !off
        if (mixed)
            anyMixed = true
        bits.push({ mask: mask, on: modes.length > 0 && on, mixed: mixed })
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

// Every skip is named with its reason, capped so a whole drive stays one line.
function skipNote(skipped) {
    var list = skipped || []
    var shown = []
    for (var i = 0; i < list.length && i < 3; i++)
        shown.push(leafOf(list[i].path) + ": " + list[i].why)
    var tail = list.length > 3 ? "; and " + (list.length - 3) + " more" : ""
    return (list.length === 1 ? "1 item cannot be changed: " : list.length + " items cannot be changed: ")
        + shown.join("; ") + tail
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
