.pragma library

// The spec harness's reader of Qt's rich text: the HTML a TextEdit exports for a Markdown string, as plain semantic HTML again.
.import "mdspec-canon.js" as Canon

// Sample input: ' font-weight:700; font-style:italic;' answers { "font-weight": "700", "font-style": "italic" }.
function styleOf(attrs) {
    var out = {}
    var parts = String(attrs.style || "").split(";")
    for (var i = 0; i < parts.length; i++) {
        var at = parts[i].indexOf(":")
        if (at > 0)
            out[parts[i].slice(0, at).trim().toLowerCase()] = parts[i].slice(at + 1).trim().toLowerCase()
    }
    return out
}

function esc(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

var BOLD_WEIGHT = 600
var MONO_FAMILY = /mono|courier/i
var QUOTE_INDENT_PX = 40

function isMono(style) {
    return MONO_FAMILY.test(style["font-family"] || "")
}

// A span's drawn format as the tags a reader would have written; nothing is added for the base face.
function wrap(style, inner, headed) {
    var out = inner
    if (isMono(style))
        out = "<code>" + out + "</code>"
    if (!headed && parseInt(style["font-weight"] || "400", 10) >= BOLD_WEIGHT)
        out = "<strong>" + out + "</strong>"
    if (style["font-style"] === "italic")
        out = "<em>" + out + "</em>"
    if ((style["text-decoration"] || "").indexOf("line-through") >= 0)
        out = "<del>" + out + "</del>"
    if (style["vertical-align"] === "super")
        out = "<sup>" + out + "</sup>"
    if (style["vertical-align"] === "sub")
        out = "<sub>" + out + "</sub>"
    return out
}

// The inline children of one block: text, spans, links, images and breaks; Qt draws a heading's whole text in bold, so headed drops it.
function inlineOf(nodes, dir, headed) {
    var out = ""
    for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i]
        if (n.text !== undefined)
            out += esc(n.text)
        else if (n.tag === "span")
            out += wrap(styleOf(n.attrs), inlineOf(n.kids, dir, headed), headed)
        else if (n.tag === "a")
            out += "<a href=\"" + esc(n.attrs.href || "") + "\">" + inlineOf(n.kids, dir, headed) + "</a>"
        else if (n.tag === "img")
            out += "<img src=\"" + esc(String(n.attrs.src || "").replace("file://" + dir + "/", "")) + "\" alt=\"" + esc(n.attrs.alt || "") + "\">"
        else if (n.tag === "br")
            out += "<br>"
        else if (n.tag !== "ul" && n.tag !== "ol")
            out += inlineOf(n.kids, dir, headed)
    }
    return out
}

// A code block is paragraphs with no margin above, every run monospace: a spaced paragraph of one code span is prose.
function allMono(node) {
    var seen = false
    if (styleOf(node.attrs)["margin-top"] !== "0px")
        return false
    if (node.kids.length === 1 && node.kids[0].tag === "br")
        return isMono(styleOf(node.attrs))
    for (var i = 0; i < node.kids.length; i++) {
        var k = node.kids[i]
        if (k.tag === "span" && isMono(styleOf(k.attrs)))
            seen = true
        else if (!(k.text !== undefined && k.text.trim() === ""))
            return false
    }
    return seen
}

// The empty paragraph Qt exports for a rule that has no text beside it.
function ruleCarrier(node, next) {
    return node.tag === "p" && node.kids.length === 1 && node.kids[0].tag === "br" && next !== undefined && next.tag === "hr"
}

function plain(node) {
    var out = ""
    for (var i = 0; i < node.kids.length; i++)
        out += node.kids[i].text !== undefined ? node.kids[i].text : plain(node.kids[i])
    return out
}

function listOf(node, dir, state) {
    var tag = node.tag
    var start = node.attrs.start
    var out = "<" + tag + (start !== undefined ? " start=\"" + start + "\"" : "") + ">"
    var open = false
    for (var i = 0; i < node.kids.length; i++) {
        var k = node.kids[i]
        if (k.tag === "li") {
            if (open)
                out += "</li>"
            var cls = k.attrs["class"]
            var inline = []
            var nested = ""
            for (var j = 0; j < k.kids.length; j++) {
                if (k.kids[j].tag === "ul" || k.kids[j].tag === "ol")
                    nested += listOf(k.kids[j], dir, state)
                else
                    inline.push(k.kids[j])
            }
            out += "<li>" + (cls === "checked" ? "<input checked=\"\" disabled=\"\" type=\"checkbox\"> " : cls === "unchecked" ? "<input disabled=\"\" type=\"checkbox\"> " : "")
                + inlineOf(inline, dir) + nested
            open = true
        } else if (k.tag === "p") {
            out += "<p>" + inlineOf(k.kids, dir) + "</p>"
        }
    }
    return out + (open ? "</li>" : "") + "</" + tag + ">"
}

function tableOf(node, dir) {
    var rows = []
    function collect(n) {
        for (var i = 0; i < n.kids.length; i++) {
            if (n.kids[i].tag === "tr")
                rows.push(n.kids[i])
            else if (n.kids[i].tag !== undefined)
                collect(n.kids[i])
        }
    }
    collect(node)
    var out = "<table>"
    for (var r = 0; r < rows.length; r++) {
        var head = r === 0
        out += (head ? "<thead>" : r === 1 ? "<tbody>" : "") + "<tr>"
        for (var c = 0; c < rows[r].kids.length; c++) {
            var cell = rows[r].kids[c]
            if (cell.tag !== "td")
                continue
            var p = cell.kids.filter(function (x) { return x.tag === "p" })[0]
            var align = p !== undefined && p.attrs.align !== undefined && p.attrs.align !== "left" ? " align=\"" + p.attrs.align + "\"" : ""
            out += "<" + (head ? "th" : "td") + align + ">" + (p !== undefined ? inlineOf(p.kids, dir) : "") + "</" + (head ? "th" : "td") + ">"
        }
        out += "</tr>" + (head ? "</thead>" : "")
    }
    return out + (rows.length > 1 ? "</tbody>" : "") + "</table>"
}

// Qt keeps no element for a code block, and a lone html paragraph has the same zero margin, so only source with code syntax can hold one.
var CODE_SYNTAX = /```|~~~|(^|\n)[ \t>]*(?: {4}|\t)/

// The export's body as semantic HTML; a block's left margin counts the quotes around it.
function fromExport(exported, dir, source) {
    var codeAllowed = CODE_SYNTAX.test(source || "")
    var at = exported.indexOf("<body>")
    var end = exported.lastIndexOf("</body>")
    var tree = Canon.parse(exported.slice(at + 6, end < 0 ? exported.length : end))
    tree.kids = tree.kids.filter(function (k) { return k.tag !== undefined })
    var out = ""
    var depth = 0
    var code = null
    function setDepth(d) {
        while (depth < d) {
            out += "<blockquote>"
            depth++
        }
        while (depth > d) {
            out += "</blockquote>"
            depth--
        }
    }
    function flushCode() {
        if (code !== null)
            out += "<pre><code>" + esc(code.join("\n") + "\n") + "</code></pre>"
        code = null
    }
    for (var i = 0; i < tree.kids.length; i++) {
        var n = tree.kids[i]
        if (n.tag === undefined)
            continue
        if (ruleCarrier(n, tree.kids[i + 1]))
            continue
        var indent = parseInt(((styleOf(n.attrs)["margin-left"]) || "0"), 10)
        var d = Math.round(indent / QUOTE_INDENT_PX)
        if (codeAllowed && n.tag === "p" && allMono(n)) {
            if (code === null)
                setDepth(d)
            code = (code || []).concat([n.kids[0].tag === "br" ? "" : plain(n)])
            continue
        }
        flushCode()
        if (n.tag === "ul" || n.tag === "ol") {
            out += listOf(n, dir)
        } else if (n.tag === "table") {
            out += tableOf(n, dir)
        } else if (n.tag === "hr") {
            out += "<hr>"
        } else {
            setDepth(n.tag === "p" ? d : 0)
            out += "<" + n.tag + ">" + inlineOf(n.kids, dir, /^h[1-6]$/.test(n.tag)) + "</" + n.tag + ">"
        }
    }
    flushCode()
    setDepth(0)
    return out
}
