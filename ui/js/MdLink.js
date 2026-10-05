.pragma library

// MdLink: the readers of a link's pieces, a destination and title, a reference label, an autolink and a bare address.
.import "MdInline.js" as Md

var TARGET_SCAN_LIMIT = 8192
var LABEL_SCAN_LIMIT = 1000
var MIN_BARELINK_LENGTH = 9
var HTTP_PREFIX_LENGTH = 7
var HTTPS_PREFIX_LENGTH = 8
var WWW_PREFIX_LENGTH = 4

// Sample input: "\n  x" read at 0 answers 4, past the line ending and the indent; "\n \n x" answers -1, a blank line.
function skipBlanks(text, j, cap) {
    var ending = false
    while (j < text.length && j < cap) {
        var c = text.charAt(j)
        if (c === "\r" && text.charAt(j + 1) === "\n")
            j++
        else if (c !== " " && c !== "\t" && c !== "\n" && c !== "\r")
            break
        if (c === "\n" || c === "\r") {
            if (ending)
                return -1
            ending = true
        }
        j++
    }
    return j
}

// Sample input: `a\>b> c` read from 0 answers 4, the ">" that closes an angle destination; a line ending, even after a backslash, answers -1; strict refuses "<".
function angleClose(text, from, limit, strict) {
    var j = from
    while (j < text.length && j < limit) {
        var c = text.charAt(j)
        if (c === ">")
            return j
        if (c === "\n" || c === "\r" || (strict === true && c === "<"))
            return -1
        // A backslash before a line ending is no escape, so the destination ends there unclosed.
        if (c === "\\" && (text.charAt(j + 1) === "\n" || text.charAt(j + 1) === "\r"))
            return -1
        j += c === "\\" ? 2 : 1
    }
    return -1
}

// Sample input: (b "t") after a label's "]"; answers {url, end} past ")", or null; blanks, a line ending and the title may span lines.
function readInlineTarget(text, i) {
    if (text.charAt(i) !== "(")
        return null
    // Targets past the scan limit read as literal text: no real target runs that long, and an unbounded walk is quadratic.
    var cap = i + TARGET_SCAN_LIMIT
    var j = skipBlanks(text, i + 1, cap)
    if (j < 0)
        return null
    var url = ""
    if (text.charAt(j) === "<") {
        j++
        var start = j
        j = angleClose(text, j, cap, true)
        if (j < 0)
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
    var gap = j
    j = skipBlanks(text, j, cap)
    if (j < 0)
        return null
    var opener = text.charAt(j)
    if (j > gap && (opener === '"' || opener === "'" || opener === "(")) {
        var qclose = opener === "(" ? ")" : opener
        j++
        while (j < text.length && j < cap) {
            var titleChar = text.charAt(j)
            if (titleChar === qclose)
                break
            if (titleChar === "\n" || titleChar === "\r") {
                var next = skipBlanks(text, j, cap)
                if (next < 0)
                    return null
                j = next
                continue
            }
            var escaped = titleChar === "\\" && text.charAt(j + 1) !== "\n" && text.charAt(j + 1) !== "\r"
            j += escaped ? 2 : 1
        }
        if (j >= text.length || j >= cap || text.charAt(j) !== qclose)
            return null
        j = skipBlanks(text, j + 1, cap)
        if (j < 0)
            return null
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

// Sample input: "  My\tLabel  " normalizes to "my label" for reference lookup; the case fold sends sharp s to "ss".
function normalizeLabel(label) {
    return String(label).replace(/[\t\n ]+/g, " ").replace(/^ | $/g, "").toLowerCase().replace(/\u00df/g, "ss")
}

// CommonMark's email address: its local part set and dot-separated host labels.
var MAIL_ADDRESS = /^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*$/

// A <scheme:...> or <mail> autolink at text[i] === "<"; answers {url, href, end} or null, href gaining mailto: for an address.
function readAutolink(text, i) {
    var j = i + 1
    while (j < text.length && j - i < TARGET_SCAN_LIMIT && text.charAt(j) !== ">" && !Md.isSpace(text.charAt(j)))
        j++
    if (j >= text.length || j - i >= TARGET_SCAN_LIMIT || text.charAt(j) !== ">")
        return null
    var inner = text.slice(i + 1, j)
    if (/^[a-zA-Z][a-zA-Z0-9+.-]{1,31}:[^<>]*$/.test(inner))
        return { url: inner, href: inner, end: j + 1 }
    if (MAIL_ADDRESS.test(inner))
        return { url: inner, href: "mailto:" + inner, end: j + 1 }
    return null
}

// Sample input: see https://a.example/x. here; answers {url, href, end} or null; trailing punctuation is stripped, www. gains http://.
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
    while (j < text.length && !Md.isSpace(text.charAt(j)) && text.charAt(j) !== "<")
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
    return url.length < MIN_BARELINK_LENGTH ? null : { url: url, href: http ? url : "http://" + url, end: j }
}
