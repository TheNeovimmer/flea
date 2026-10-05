// A source slice between two markers, so a renamed or reordered function fails loudly.
// Sample input: slice("ab function f() {} function g() {}", "function f", "function g").
function slice(src, fromMarker, toMarker) {
    // indexOf coerces undefined to "undefined", so guard before any search.
    if (typeof fromMarker !== "string" || fromMarker.length === 0 || typeof toMarker !== "string" || toMarker.length === 0)
        throw new Error("sourcefixture: slice needs non-empty fromMarker and toMarker")
    var text = String(src)
    var from = text.indexOf(fromMarker)
    if (from < 0)
        throw new Error("sourcefixture: missing marker " + fromMarker)
    var end = text.indexOf(toMarker, from + fromMarker.length)
    if (end < 0 && text.indexOf(toMarker) >= 0)
        throw new Error("sourcefixture: out-of-order markers " + fromMarker + " before " + toMarker)
    if (end < 0)
        throw new Error("sourcefixture: missing marker " + toMarker)
    return text.substring(from, end)
}
// One file reader for every suite that greps this tree, so a renamed file fails loudly.
// Sample input: Source.source("ui/Backend.qml") answers that file's text.
function source(path) {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("../../" + path), false)
    request.send()
    var body = String(request.responseText || "")
    if (body.length === 0)
        throw new Error("sourcefixture: cannot read " + path)
    return body
}
// Sample input: function ask(kind, source, display, theme) { ... } or onExited: function (...) { ... }.
function block(source, marker) {
    var at = source.indexOf(marker)
    if (at < 0)
        throw new Error("figureservice: missing " + marker)
    var begin = source.indexOf("{", at + marker.length)
    var depth = 1
    var quote = ""
    var comment = false
    var i = begin + 1
    for (; i < source.length && depth > 0; i++) {
        var ch = source.charAt(i)
        if (comment) {
            if (ch === "\n")
                comment = false
        } else if (quote !== "") {
            if (ch === "\\")
                i++
            else if (ch === quote)
                quote = ""
        } else if (ch === "/" && source.charAt(i + 1) === "/") {
            comment = true
        } else if (ch === '"' || ch === "'") {
            quote = ch
        } else if (ch === "{") {
            depth++
        } else if (ch === "}") {
            depth--
        }
    }
    if (begin < 0 || depth !== 0)
        throw new Error("figureservice: unterminated " + marker)
    return source.substring(begin + 1, i - 1)
}
