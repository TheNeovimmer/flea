.pragma library

// MdInline: single-pass scanners that never restart, so hostile input stays linear and no unresolved "![", "[" or "<" escapes.
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml
.import "MdEscape.js" as Esc

var TARGET_SCAN_LIMIT = 8192
var LABEL_SCAN_LIMIT = 1000
var MIN_BARELINK_LENGTH = 9
var MAX_MATH_RUN_LENGTH = 2
var HTTP_PREFIX_LENGTH = 7
var HTTPS_PREFIX_LENGTH = 8
var WWW_PREFIX_LENGTH = 4

function isSpace(c) {
    return c === " " || c === "\t" || c === "\n" || c === "\r"
}

function isPunct(c) {
    return Esc.isAsciiPunct(c.charCodeAt(0))
}

// Interval tuple: [from, to, run length, kind].
var INTERVAL_STRIDE = 4

// Sample input: `` ` `` and `x`, or $x+1$ and $$x^2$$; code (kind 0) pairs before math (kind 1), never across it.
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
            out.push(open, j, len, 0)
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

// Sample input: costs $5 and $10 stays prose; $x+1$ pairs. GitHub flanking: no space after the opener,
// none before the closer, no digit after it; an odd backslash run escapes the dollar.
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
                out.push(open, j, openLen, 1)
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

// An inline code span as styled HTML, content escaped; math keeps its kind tag for the later figure unit.
function codeHtml(content, chrome, kind) {    if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(chrome || "")))
        return null
    var tag = kind === "math" ? '<code data-math="inline" style="background-color:' + chrome + '">'
        : '<code style="background-color:' + chrome + '">'
    return tag + escapeHtmlText(content) + "</code>"
}

function escapeHtmlText(content) {
    return Esc.escapeText(content)
}

// A link as a font-wrapped anchor: the importer hardcodes its link blue, but a font tag survives it.
function linkHtml(label, url, ink) {
    if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(ink || "")))
        return null
    var safe = String(url).replace(/&/g, "&#38;").replace(/"/g, "&#34;")
    return '<a href="' + safe + '"><font color="' + ink + '">' + escapeHtmlText(label) + "</font></a>"
}

// Sample input: (b "t") after a label's "]"; answers {url, end} past ")", or null. Same line, balanced parens.
function readInlineTarget(text, i) {
    if (text.charAt(i) !== "(")
        return null
    // Targets past the scan limit read as literal text: no real target runs that long, and an unbounded walk is quadratic.
    var cap = i + TARGET_SCAN_LIMIT
    var j = i + 1
    while (j < text.length && j < cap && (text.charAt(j) === " " || text.charAt(j) === "\t"))
        j++
    if (text.charAt(j) === "\n" || text.charAt(j) === "\r")
        return null
    var url = ""
    if (text.charAt(j) === "<") {
        j++
        var start = j
        while (j < text.length && j < cap) {
            var angleChar = text.charAt(j)
            if (angleChar === ">" || angleChar === "\n" || angleChar === "\r")
                break
            j++
        }
        if (j >= text.length || j >= cap || text.charAt(j) !== ">")
            return null
        url = text.slice(start, j)
        j++
    } else {
        var depth = 0
        var begin = j
        while (j < text.length && j < cap) {
            var c = text.charAt(j)
            if (c === "\n" || c === "\r" || ((c === " " || c === "\t") && depth === 0))
                break
            if (c === "\\") {
                if (text.charAt(j + 1) === "\n" || text.charAt(j + 1) === "\r")
                    return null
                j += 2
                continue
            }
            if (c === "(")
                depth++
            else if (c === ")") {
                if (depth === 0)
                    break
                depth--
            }
            j++
        }
        if (j >= cap)
            return null
        url = text.slice(begin, j)
    }
    while (j < text.length && j < cap && (text.charAt(j) === " " || text.charAt(j) === "\t"))
        j++
    if (text.charAt(j) === '"' || text.charAt(j) === "'" || text.charAt(j) === "(") {
        var q = text.charAt(j)
        var qclose = q === "(" ? ")" : q
        j++
        while (j < text.length && j < cap) {
            var titleChar = text.charAt(j)
            if (titleChar === qclose || titleChar === "\n" || titleChar === "\r")
                break
            if (titleChar === "\\") {
                if (text.charAt(j + 1) === "\n" || text.charAt(j + 1) === "\r")
                    return null
                j++
            }
            j++
        }
        if (j >= text.length || j >= cap || text.charAt(j) !== qclose)
            return null
        j++
        while (j < text.length && j < cap && (text.charAt(j) === " " || text.charAt(j) === "\t"))
            j++
    }
    if (j >= cap || text.charAt(j) !== ")")
        return null
    return { url: url, end: j + 1 }
}

// A [label] or collapsed [label][] after labelEnd; answers {label, end} or null.
function readLabelRef(text, i) {
    if (text.charAt(i) !== "[")
        return null
    var j = i + 1
    var depth = 0
    while (j < text.length && j - i < LABEL_SCAN_LIMIT) {
        var c = text.charAt(j)
        if (c === "\n")
            return null
        if (c === "\\") {
            j += 2
            continue
        }
        if (c === "[")
            depth++
        else if (c === "]") {
            if (depth === 0)
                break
            depth--
        }
        j++
    }
    if (j >= text.length || j - i >= LABEL_SCAN_LIMIT)
        return null
    return { label: text.slice(i + 1, j), end: j + 1 }
}

// Sample input: "  My\tLabel  " normalizes to "my label" for reference lookup.
function normalizeLabel(label) {
    return String(label).replace(/[\t\n ]+/g, " ").replace(/^ | $/g, "").toLowerCase()
}

// A <scheme:...> or <mail> autolink at text[i] === "<"; answers {url, end} or null.
function readAutolink(text, i) {
    var j = i + 1
    while (j < text.length && j - i < TARGET_SCAN_LIMIT && text.charAt(j) !== ">" && !isSpace(text.charAt(j)))
        j++
    if (j >= text.length || j - i >= TARGET_SCAN_LIMIT || text.charAt(j) !== ">")
        return null
    var inner = text.slice(i + 1, j)
    if (/^[a-zA-Z][a-zA-Z0-9+.-]{1,31}:[^<>]*$/.test(inner)
            || /^[^<>\s@]+@[^<>\s@]+\.[^<>\s@]+$/.test(inner))
        return { url: inner, end: j + 1 }
    return null
}

// Sample input: see https://a.example/x. here; answers {url, end} or null, GFM's trailing-punctuation strip.
function readBarelink(text, i) {
    var http = text.slice(i, i + HTTP_PREFIX_LENGTH) === "http://" || text.slice(i, i + HTTPS_PREFIX_LENGTH) === "https://"
    if (!http) {
        if (text.slice(i, i + WWW_PREFIX_LENGTH) !== "www.")
            return null
        var before = i > 0 ? text.charAt(i - 1) : " "
        if (/[A-Za-z0-9_\/@]/.test(before))
            return null
    }
    var j = i
    while (j < text.length && !isSpace(text.charAt(j)) && text.charAt(j) !== "<")
        j++
    var parens = 0
    for (var at = i; at < j; at++)
        parens += text.charAt(at) === "(" ? 1 : text.charAt(at) === ")" ? -1 : 0
    while (j > i) {
        var tail = text.charAt(j - 1)
        if ("?!.,;:".indexOf(tail) < 0 && !(tail === ")" && parens < 0))
            break
        parens += tail === ")" ? 1 : 0
        j--
    }
    var url = text.slice(i, j)
    return url.length < MIN_BARELINK_LENGTH ? null : { url: url, end: j }
}
