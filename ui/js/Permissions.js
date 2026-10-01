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
