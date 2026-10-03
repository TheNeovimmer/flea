.pragma library

// Prefix readers use byte offsets and absolute tab columns, without copying the remaining line.
var CODE_INDENT = 4
var MAX_MARKER_INDENT = 3
var MAX_MARKER_DIGITS = 9
var DECIMAL_RADIX = 10
var MAX_GAP_SCAN = CODE_INDENT + 1

// Sample: a tab after two spaces advances to column four.
function indentationAt(line, view, limit) {
    var stop = limit === undefined ? CODE_INDENT : limit
    var at = view.at
    var width = view.padding
    while (at < line.length && width < stop) {
        var c = line.charAt(at)
        if (c !== " " && c !== "\t")
            break
        width += c === "\t" ? CODE_INDENT - (view.column + width) % CODE_INDENT : 1
        at++
    }
    return { end: at, width: width }
}

function takeIndent(line, view, wanted) {
    var width = Math.min(view.padding, wanted)
    view.padding -= width
    while (view.at < line.length && width < wanted) {
        var c = line.charAt(view.at)
        if (c !== " " && c !== "\t")
            break
        var step = c === "\t" ? CODE_INDENT - (view.column + width) % CODE_INDENT : 1
        view.at++
        width += step
    }
    view.padding += Math.max(0, width - wanted)
    view.column += Math.min(width, wanted)
}

// Sample: ">\ttext" consumes one column after > and retains the tab's remaining columns.
function quoteAt(line, view) {
    var at = view.at
    var indent = view.padding
    while (indent <= MAX_MARKER_INDENT && line.charAt(at) === " ") {
        indent++
        at++
    }
    return indent <= MAX_MARKER_INDENT && line.charAt(at) === ">" ? indent : -1
}

function takeQuote(line, view, indent) {
    takeIndent(line, view, indent)
    view.at++
    view.column++
    if (line.charAt(view.at) === " " || line.charAt(view.at) === "\t")
        takeIndent(line, view, 1)
}

// Sample: "10.\ttext" starts content at column four, and five gap columns leave indented code.
function listAt(line, view) {
    var at = view.at
    var indent = view.padding
    while (indent <= MAX_MARKER_INDENT && line.charAt(at) === " ") {
        indent++
        at++
    }
    if (indent > MAX_MARKER_INDENT)
        return null
    var start = at
    var c = line.charAt(at)
    var ordered = c >= "0" && c <= "9"
    if (ordered) {
        while (at - start < MAX_MARKER_DIGITS && line.charAt(at) >= "0" && line.charAt(at) <= "9")
            at++
        if (line.charAt(at) !== "." && line.charAt(at) !== ")")
            return null
    } else if (c !== "-" && c !== "*" && c !== "+") {
        return null
    }
    at++
    if (line.charAt(at) !== " " && line.charAt(at) !== "\t")
        return null
    var markerWidth = at - start
    var gapView = { at: at, padding: 0, column: view.column + indent + markerWidth }
    var gap = indentationAt(line, gapView, MAX_GAP_SCAN).width
    var consumedGap = gap > CODE_INDENT ? 1 : gap
    return { indent: indent, ordered: ordered,
        start: ordered ? parseInt(line.slice(start, at - 1), DECIMAL_RADIX) : 0,
        contentCol: indent + markerWidth + consumedGap, markerEnd: at,
        markerColumn: gapView.column, gap: consumedGap }
}

function takeList(line, view, marker) {
    view.at = marker.markerEnd
    view.padding = 0
    view.column = marker.markerColumn
    takeIndent(line, view, marker.gap)
}

function textAt(line, view) {
    return " ".repeat(view.padding) + line.slice(view.at)
}

function readListMarker(line) {
    var view = { at: 0, padding: 0, column: 0 }
    var marker = listAt(String(line), view)
    if (marker === null)
        return null
    takeList(line, view, marker)
    return { indent: marker.indent, ordered: marker.ordered, start: marker.start,
        contentCol: marker.contentCol, text: textAt(line, view) }
}
