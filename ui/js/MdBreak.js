.pragma library

// MdBreak: the line-level readers of the inline scan, hard breaks and thematic break lines.
.import "MdEmph.js" as Emph

var HARD_BREAK_SPACES = 2
var MAX_MARKER_LENGTH = 10

// Sample input: "foo  \nbar" and "foo\\\nbar" break the line; "foo \nbar" and a paragraph's last newline do not.
function lineBreak(body, i, out, delims, endParagraph) {
    var slash = body.charAt(i) === "\\"
    var next = slash ? i + 2 : i + 1
    var spaces = 0
    while (!slash && out.length > 0 && out[out.length - 1] === " ") {
        out.pop()
        spaces++
    }
    while (next < body.length && (body.charAt(next) === " " || body.charAt(next) === "\t"))
        next++
    // A blank line ends the paragraph, and no emphasis mark pairs and no bracket pair closes across it.
    if (next < body.length && body.charAt(next) === "\n") {
        Emph.process(delims, delims.bottom)
        delims.bottom = delims.length
        endParagraph()
    }
    if (next < body.length && body.charAt(next) !== "\n" && (slash || spaces >= HARD_BREAK_SPACES)) {
        out.push("<br />")
        return next
    }
    if (slash)
        out.push("\\")
    out.push("\n")
    return slash ? i + 2 : i + 1
}

var RULE_LINE = /^ {0,3}([*_])(?:[ \t]*\1){2,}[ \t]*$/
var RULE_LINE_INDENT = 3

// Sample input: "a\n  * * *\nb" at the second star is a thematic break line, which the renderer draws as a rule.
function isRuleLine(body, at) {
    var from = at
    while (from > 0 && at - from < RULE_LINE_INDENT && body.charAt(from - 1) === " ")
        from--
    if (from > 0 && body.charAt(from - 1) !== "\n")
        return false
    var end = body.indexOf("\n", at)
    return RULE_LINE.test(body.slice(from, end < 0 ? body.length : end))
}

var LIST_MARK = /^(?:[-+*]|\d{1,9}[.)])$/

function skipBlanksBack(body, at) {
    var p = at
    while (p >= 0 && (body.charAt(p) === " " || body.charAt(p) === "\t"))
        p--
    return p
}

// Sample input: "- > q" at the ">" is a quote mark inside an item; "a > b" is not. last is the previous mark's index.
function quoteMarkAt(body, at, last) {
    var p = skipBlanksBack(body, at - 1)
    if (p < 0 || body.charAt(p) === "\n" || p === last)
        return true
    var from = p
    while (from > 0 && /\S/.test(body.charAt(from - 1)))
        from--
    if (p - from >= MAX_MARKER_LENGTH || p === at - 1 || !LIST_MARK.test(body.slice(from, p + 1)))
        return false
    var before = skipBlanksBack(body, from - 1)
    return before < 0 || body.charAt(before) === "\n" || before === last
}
