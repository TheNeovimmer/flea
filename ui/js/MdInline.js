.pragma library

// MdInline: single-pass inline scanners. Every scan advances and never
// restarts, so hostile inputs stay linear; the output holds no "![", "[" or
// raw "<" except spans this parser resolved itself.
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml

function isSpace(c) {
    return c === " " || c === "\t" || c === "\n" || c === "\r"
}

function isPunct(c) {
    var code = c.charCodeAt(0)
    return (code >= 33 && code <= 47) || (code >= 58 && code <= 64)
        || (code >= 91 && code <= 96) || (code >= 123 && code <= 126)
}

function spanIntervals(text) {
    var out = []
    // Native presence checks: inputs without spans skip both scans entirely.
    if (text.indexOf("`") < 0 && text.indexOf("$") < 0)
        return out
    // Runs are paired as they close, straight into from order: one pass, no
    // run table, no pair table, no sort. Closer order is from order except for
    // nested spans, which the bounded walk slots in behind the append.
    if (text.indexOf("`") >= 0) {
        var openByLen = {}
        var i = 0
        while (i < text.length) {
            if (text.charAt(i) !== "`") {
                i++
                continue
            }
            var j = i
            while (j < text.length && text.charAt(j) === "`")
                j++
            var len = j - i
            var open = openByLen[len]
            if (open !== undefined && open !== null) {
                appendSpan(out, open, j, len, 0)
                openByLen[len] = null
            } else {
                openByLen[len] = i
            }
            i = j
        }
    }
    // Math per GitHub's rules, kept as code-styled literal text with a kind tag
    // a later unit swaps for a figure. Same run pairing over $ runs of length 1-2.
    if (text.indexOf("$") >= 0) {
    var i = 0
    var mopen = -1
    var mlen = 0
    while (i < text.length) {
        if (text.charAt(i) !== "$") {
            i++
            continue
        }
        var j = i
        while (j < text.length && text.charAt(j) === "$")
            j++
        var len = j - i
        if (len > 2) {
            i = j
            continue
        }
        if (mopen < 0) {
            mopen = i
            mlen = len
        } else if (len === mlen) {
            appendSpan(out, mopen, j, mlen, 1)
            mopen = -1
        }
        i = j
    }
    }
    return out
}

// Append one tuple in from order; nested spans walk back their shallow depth.
function appendSpan(out, from, to, len, kind) {
    if (out.length === 0 || out[out.length - 4] <= from) {
        out.push(from, to, len, kind)
        return
    }
    insertOrdered4(out, from, to, len, kind)
}

// Insert one [from, to, len, kind] tuple keeping from order. Appends in the
// common case; nested spans walk back over their (shallow) depth only.
function insertOrdered4(out, from, to, len, kind) {
    var k = out.length
    while (k > 0 && out[k - 4] > from)
        k -= 4
    out.push(from, to, len, kind)
    if (k === out.length - 4)
        return
    for (var m = out.length - 1; m > k + 3; m--)
        out[m] = out[m - 4]
    out[k] = from
    out[k + 1] = to
    out[k + 2] = len
    out[k + 3] = kind
}

// Escape one text character for md4c: brackets and angle brackets can never
// reach it raw, so no image, link, definition or tag forms there.
function escapeChar(c) {
    return c === "<" ? "&#60;" : c === ">" ? "&#62;" : c === "[" ? "&#91;" : c === "]" ? "&#93;" : c
}

// An inline code span as styled HTML. The content stays literal through the
// escaper below; math keeps its kind tag for the later figure unit.
function codeHtml(content, chrome, kind) {    if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(chrome || "")))
        return null
    var tag = kind === "math" ? '<code data-math="inline" style="background-color:' + chrome + '">'
        : '<code style="background-color:' + chrome + '">'
    return tag + escapeHtmlText(content) + "</code>"
}

function escapeHtmlText(content) {
    // The exact set the old pipeline escaped: & < > and every ASCII
    // punctuation character. Letters, digits, spaces and non-ASCII pass, so
    // emphasis, links and autolinks cannot form inside converted spans and cells.
    var text = String(content)
    if (text.length < 1024) {
        return text.replace(/[&<>\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]/g, function (c) {
            return "&#" + c.charCodeAt(0) + ";"
        })
    }
    // Long inputs pay the callback once per match in this engine, seconds per
    // megabyte, so they take one native pass per PRESENT character instead.
    // Same bytes out: only characters found by the scan are rewritten.
    if (!/[&<>\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]/.test(text))
        return text
    for (var k = 0; k < ESCAPED_CHARS.length; k++) {
        var c = ESCAPED_CHARS[k]
        if (text.indexOf(c) >= 0)
            text = text.split(c).join("&#" + c.charCodeAt(0) + ";")
    }
    return text
}

// Every character the escaper above rewrites, as literal one-character strings.
var ESCAPED_CHARS = ["&", "<", ">", "!", '"', "#", "$", "%", "'", "(", ")", "*",
    "+", ",", "-", ".", "/", ":", ";", "=", "?", "@", "[", "\\", "]", "^", "_",
    "`", "{", "|", "}", "~"]

// A link as a font-wrapped anchor: the importer hardcodes its own link blue
// over QML linkColor, but a presentational font tag survives the import.
function linkHtml(label, url, ink) {
    if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(ink || "")))
        return null
    var safe = String(url).replace(/&/g, "&#38;").replace(/"/g, "&#34;")
    return '<a href="' + safe + '"><font color="' + ink + '">' + escapeHtmlText(label) + "</font></a>"
}

// Read an inline (...)-target after labelEnd (the index past "]"). Same-line
// only; answers {url, end} with end past ")", or null. Balanced parens nest.
function readInlineTarget(text, i) {
    if (text.charAt(i) !== "(")
        return null
    // Targets past 8 KiB read as literal text: no legitimate image or link
    // target runs that long, and an unbounded paren-depth walk rescans the
    // tail once per "]". Whatever md4c makes of it stays inert, because the
    // "[![" that would form it never reaches md4c unresolved.
    var cap = i + 8192
    var j = i + 1
    while (j < text.length && (text.charAt(j) === " " || text.charAt(j) === "\t"))
        j++
    if (j < text.length && text.charAt(j) === "\n")
        return null
    var url = ""
    if (text.charAt(j) === "<") {
        j++
        var start = j
        while (j < text.length && j < cap && text.charAt(j) !== ">" && text.charAt(j) !== "\n")
            j++
        if (j >= text.length || j >= cap || text.charAt(j) !== ">")
            return null
        url = text.slice(start, j)
        j++
    } else {
        var depth = 0
        var begin = j
        while (j < text.length && j < cap) {
            var c = text.charAt(j)
            if (c === "\n" || ((c === " " || c === "\t") && depth === 0))
                break
            if (c === "\\") {
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
    while (j < text.length && (text.charAt(j) === " " || text.charAt(j) === "\t"))
        j++
    if (text.charAt(j) === '"' || text.charAt(j) === "'" || text.charAt(j) === "(") {
        var q = text.charAt(j)
        var qclose = q === "(" ? ")" : q
        j++
        while (j < text.length && text.charAt(j) !== qclose && text.charAt(j) !== "\n") {
            if (text.charAt(j) === "\\")
                j++
            j++
        }
        if (j >= text.length || text.charAt(j) !== qclose)
            return null
        j++
        while (j < text.length && (text.charAt(j) === " " || text.charAt(j) === "\t"))
            j++
    }
    if (text.charAt(j) !== ")")
        return null
    return { url: url, end: j + 1 }
}

// A [label] or collapsed [label][] after labelEnd; answers {label, end} or null.
function readLabelRef(text, i) {
    if (text.charAt(i) !== "[")
        return null
    var j = i + 1
    var depth = 0
    while (j < text.length && j - i < 1000) {
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
    if (j >= text.length || j - i >= 1000)
        return null
    return { label: text.slice(i + 1, j), end: j + 1 }
}

function normalizeLabel(label) {
    return String(label).replace(/[\t\n ]+/g, " ").replace(/^ | $/g, "").toLowerCase()
}

// A <scheme:...> or <mail> autolink at text[i] === "<"; answers {url, end} or null.
function readAutolink(text, i) {
    var j = i + 1
    while (j < text.length && j - i < 8192 && text.charAt(j) !== ">" && !isSpace(text.charAt(j)))
        j++
    if (j >= text.length || j - i >= 8192 || text.charAt(j) !== ">")
        return null
    var inner = text.slice(i + 1, j)
    if (/^[a-zA-Z][a-zA-Z0-9+.-]{1,31}:[^<>]*$/.test(inner)
            || /^[^<>\s@]+@[^<>\s@]+\.[^<>\s@]+$/.test(inner))
        return { url: inner, end: j + 1 }
    return null
}

// Bare http(s)/www autolink starting at i; answers {url, end} or null. GFM's
// trailing-punctuation strip, bounded and linear.
function readBarelink(text, i) {
    var http = text.slice(i, i + 7) === "http://" || text.slice(i, i + 8) === "https://"
    if (!http) {
        if (text.slice(i, i + 4) !== "www.")
            return null
        var before = i > 0 ? text.charAt(i - 1) : " "
        if (/[A-Za-z0-9_\/@]/.test(before))
            return null
    }
    var j = i
    while (j < text.length && !isSpace(text.charAt(j)) && text.charAt(j) !== "<")
        j++
    var url = text.slice(i, j)
    while (url.length > 0 && "?!.,;:".indexOf(url.charAt(url.length - 1)) >= 0) {
        url = url.slice(0, -1)
        j--
    }
    if (url.charAt(url.length - 1) === ")" && url.indexOf("(") < 0) {
        url = url.slice(0, -1)
        j--
    }
    return url.length < 9 ? null : { url: url, end: j }
}
