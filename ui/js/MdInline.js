.pragma library

// MdInline: single-pass scanners that never restart, so hostile input stays linear and no unresolved "![", "[" or "<" escapes.
.import "MdEscape.js" as Esc

var MAX_MATH_RUN_LENGTH = 2

function isSpace(c) {
    return c === " " || c === "\t" || c === "\n" || c === "\r"
}

function isPunct(c) {
    return Esc.isAsciiPunct(c.charCodeAt(0))
}

// Interval tuple: [from, to, run length, kind]; the kind is CODE_SPAN or MATH_SPAN.
var INTERVAL_STRIDE = 4
var CODE_SPAN = 0
var MATH_SPAN = 1

// Sample input: `` ` `` and `x`, or $x+1$ and $$x^2$$; code pairs before math, never across it.
function spanIntervals(text) {
    var hasCode = text.indexOf("`") >= 0
    if (!hasCode && text.indexOf("$") < 0)
        return []
    var code = hasCode ? codeIntervals(text) : []
    return text.indexOf("$") >= 0 ? mergeIntervals(code, mathIntervals(text, code)) : code
}

// Sample input: ``a ` b`` and `c`; a closing run drops the openers and spans inside it, which are literal.
function codeIntervals(text) {
    var out = []
    var openByLen = {}
    var openers = []
    var i = text.indexOf("`")
    while (i >= 0) {
        var j = i + 1
        while (text.charAt(j) === "`")
            j++
        var len = j - i
        var open = openByLen[len]
        if (open !== undefined && open !== null) {
            while (out.length > 0 && out[out.length - INTERVAL_STRIDE] > open)
                out.length -= INTERVAL_STRIDE
            out.push(open, j, len, CODE_SPAN)
            var covered = 0
            do {
                covered = openers.pop()
                openByLen[covered] = null
            } while (covered !== len)
        } else {
            openByLen[len] = i
            openers.push(len)
        }
        i = text.indexOf("`", j)
    }
    return out
}

// Sample input: costs $5 and $10 stays prose; $x+1$ pairs; no space inside an edge, no digit after the closer, no odd backslash run before.
function mathIntervals(text, code) {
    var out = []
    var codeAt = 0
    var i = text.indexOf("$")
    var open = -1
    var openLen = 0
    while (i >= 0) {
        while (codeAt < code.length && code[codeAt + 1] <= i) {
            open = code[codeAt] > open ? -1 : open
            codeAt += INTERVAL_STRIDE
        }
        if (codeAt < code.length && code[codeAt] < i) {
            open = -1
            i = text.indexOf("$", code[codeAt + 1])
            continue
        }
        var j = i + 1
        while (text.charAt(j) === "$")
            j++
        var len = j - i
        var back = 0
        for (var b = i - 1; b >= 0 && text.charAt(b) === "\\"; b--)
            back++
        if (len <= MAX_MATH_RUN_LENGTH && back % 2 === 0) {
            var after = text.charAt(j)
            var canClose = i > 0 && !isSpace(text.charAt(i - 1)) && !(after >= "0" && after <= "9")
            if (open >= 0 && len === openLen && canClose) {
                out.push(open, j, openLen, MATH_SPAN)
                open = -1
            } else if (j < text.length && !isSpace(text.charAt(j))) {
                open = i
                openLen = len
            }
        }
        i = text.indexOf("$", j)
    }
    return out
}

// Merge two from-ordered tuple lists in one pass; code and math never share a start.
function mergeIntervals(a, b) {
    var out = []
    var ai = 0
    var bi = 0
    while (ai < a.length || bi < b.length) {
        var fromA = bi >= b.length || (ai < a.length && a[ai] < b[bi])
        var src = fromA ? a : b
        var at = fromA ? ai : bi
        out.push(src[at], src[at + 1], src[at + 2], src[at + 3])
        ai += fromA ? INTERVAL_STRIDE : 0
        bi += fromA ? 0 : INTERVAL_STRIDE
    }
    return out
}

// U+202F narrow no-break space, about 4 px at body 14, pads the chip inside its background.
var CHIP_PAD = "\u202F"
// An inline code span as styled HTML, content escaped; math keeps its kind tag for the later figure unit.
function codeHtml(content, chrome, kind) {
    if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(chrome || "")))
        return null
    var tag = kind === "math" ? '<code data-math="inline" style="background-color:' + chrome + '">'
        : '<code style="background-color:' + chrome + '">'
    return tag + CHIP_PAD + escapeHtmlText(content) + CHIP_PAD + "</code>"
}

function escapeHtmlText(content) {
    return Esc.escapeText(content)
}

// Sample input: "1. ol" answers "&#49;&#46; ol", so a decoded "&#49;. ol" never reaches Qt as an ordered list marker; "a<b" answers "a&#60;b".
var ASCII_DIGIT_SPLIT = /([0-9])/

// Text a character reference decoded to: punctuation and digits as numeric entities, so no marker, fence or rule forms at a line start.
function escapeDecodedText(content) {
    var parts = String(content).split(ASCII_DIGIT_SPLIT)
    for (var i = 0; i < parts.length; i++)
        parts[i] = i % 2 === 1 ? "&#" + parts[i].charCodeAt(0) + ";" : escapeHtmlText(parts[i])
    return parts.join("")
}

// A link as a font-wrapped anchor: the importer hardcodes its link blue, but a font tag survives it.
function linkHtml(label, url, ink, markup) {
    if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(ink || "")))
        return null
    var safe = String(url).replace(/&/g, "&#38;").replace(/"/g, "&#34;")
    return '<a href="' + safe + '"><font color="' + ink + '">' + (markup === true ? label : escapeHtmlText(label)) + "</font></a>"
}
