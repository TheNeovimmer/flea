.pragma library

// Shared list columns and continuation rules for block rendering and reference collection.
var CODE_INDENT = 4
var MAX_MARKER_INDENT = 3

function listIndentOf(line) {
    var n = 0
    while (n < line.length && line.charAt(n) === " ")
        n++
    return n
}

// Sample: "  1. item" has contentCol 5; tab gaps advance to the next four-column stop.
function readListMarker(line) {
    var m = String(line).match(/^(\s*)(\d+[.)]|[-*+])(\s+)(.*)$/)
    if (!m)
        return null
    var indent = 0
    for (var i = 0; i < m[1].length; i++)
        indent += m[1].charAt(i) === "\t" ? CODE_INDENT - (indent % CODE_INDENT) : 1
    if (indent > MAX_MARKER_INDENT || m[4].length === 0)
        return null
    var gap = 0
    for (var g = 0; g < m[3].length; g++)
        gap += m[3].charAt(g) === "\t"
            ? CODE_INDENT - ((indent + m[2].length + gap) % CODE_INDENT) : 1
    var ordered = /^\d/.test(m[2])
    return { indent: indent, ordered: ordered, start: ordered ? parseInt(m[2], 10) : 0,
        text: m[4], contentCol: indent + m[2].length + gap }
}

function continuesItem(line, contentCol) {
    return listIndentOf(line) >= contentCol
}

function blankKeepsList(next, contentCol) {
    return next !== null && (readListMarker(next) !== null || continuesItem(next, contentCol))
}
