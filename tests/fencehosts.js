.pragma library

// Object keys in sorted order, because a block that crossed the worker's boundary comes back with its keys sorted.
function canon(v) {
    if (v === null || typeof v !== "object") return JSON.stringify(v)
    if (Array.isArray(v)) return "[" + v.map(canon).join(",") + "]"
    return "{" + Object.keys(v).sort().filter(function (k) { return v[k] !== undefined }).map(function (k) { return JSON.stringify(k) + ":" + canon(v[k]) }).join(",") + "}"
}

// The two hosts parse under their own code surface, so the chip background (the one input that differs) is read as one word.
// Sample input: '<code style="background-color:#181825">x</code>' answers '<code style="background-color:CHROME">x</code>'.
function neutral(blocks) {
    return canon(blocks).replace(/background-color:#[0-9a-fA-F]{6}/g, "background-color:CHROME")
}

// A fence line as a rendered run would draw it: a run of 3 or more backticks or tildes opening a line, after at most a quote mark or an indent.
var FENCE_LINE = /(^|\n)[ \t>]{0,8}(`{3,}|~{3,})/

// Every string the document draws as text, a fence or a figure excluded: those hold their source verbatim, markers inside it are content.
function drawnStrings(value, out) {
    if (typeof value === "string") out.push(value)
    else if (Array.isArray(value)) value.forEach(function (one) { drawnStrings(one, out) })
    else if (value !== null && typeof value === "object" && value.type !== "fence" && value.type !== "figure")
        Object.keys(value).forEach(function (key) { drawnStrings(value[key], out) })
    return out
}

// How many drawn strings still hold a fence line, which is a fence the parser did not open.
function leaks(blocks) {
    return drawnStrings(blocks, []).filter(function (text) { return FENCE_LINE.test(text) }).length
}

function kinds(blocks) {
    return blocks.map(function (b) { return b.type }).join(",")
}

// How many top-level blocks are of one type.
function count(blocks, type) {
    return blocks.filter(function (b) { return b.type === type }).length
}
