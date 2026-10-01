.pragma library

.import "Format.js" as Format

// Rendered Markdown's preprocessing: every image URL is resolved here, before Qt's own
// Markdown renderer sees the text, so no remote request is possible. Remote becomes the
// board's placeholder; only a file beside the document loads, as its file:// URL. Fenced
// blocks and inline code are literal, and links carry no handler anywhere, so both stay ink.

var RENDERED = "rendered"
var SOURCE = "source"

function isView(value) {
    return value === RENDERED || value === SOURCE
}

function toggled(value) {
    return value === RENDERED ? SOURCE : RENDERED
}

// An http(s) URL, or a protocol-relative one (which inherits https), loads from the network.
function isRemoteUrl(url) {
    return /^(https?:)?\/\//i.test(String(url))
}

function hostOf(url) {
    var rest = String(url).replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, "").replace(/^\/\//, "")
    var host = rest.split(/[\/?#]/)[0]
    if (host.indexOf("@") >= 0)
        host = host.slice(host.lastIndexOf("@") + 1)
    if (host.charAt(0) === "[" && host.indexOf("]") > 0)
        return host.slice(0, host.indexOf("]") + 1)
    var colon = host.indexOf(":")
    host = colon >= 0 ? host.slice(0, colon) : host
    return host.length > 0 ? host : String(url)
}

function dirOf(path) {
    var text = String(path)
    var slash = text.lastIndexOf("/")
    return slash >= 0 ? text.slice(0, slash) : ""
}

// The board's placeholder, in the text flow where a box cannot go: the host it refused.
function placeholder(host) {
    return "Remote image not loaded \u00b7 " + host
}

function lineCount(text) {
    var body = String(text)
    return body.length === 0 ? 0 : body.split("\n").length
}

function countLine(n) {
    return n === 1 ? "1 line" : Format.count(n) + " lines"
}

// Where an image URL lands: remote (placeholder), local (same folder, as file://),
// or dropped (any other scheme, an absolute path, or outside the folder: alt text only).
function classifyImage(raw, dir) {
    var url = String(raw === undefined || raw === null ? "" : raw)
    if (url.length === 0)
        return { kind: "dropped" }
    if (isRemoteUrl(url))
        return { kind: "remote", host: hostOf(url) }
    // data:, file: and every other scheme never reach Qt.
    if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(url))
        return { kind: "dropped" }
    var name = url
    if (name.charAt(0) === "<" && name.charAt(name.length - 1) === ">")
        name = name.slice(1, -1)
    if (name.length >= 2 && name.slice(0, 2) === "./")
        name = name.slice(2)
    if (name.length === 0 || name === "." || name === ".."
            || name.charAt(0) === "/" || name.charAt(0) === "\\"
            || name.indexOf("/") >= 0 || name.indexOf("\\") >= 0
            || /(^|\/)\.\.(\/|$)/.test(name))
        return { kind: "dropped" }
    return { kind: "local", url: Format.fileUri(dir + "/" + name) }
}

// The URL half of an inline image target, before an optional quoted title.
function targetOf(inner) {
    var text = String(inner).trim()
    if (text.charAt(0) === "<") {
        var close = text.indexOf(">")
        return close > 0 ? text.slice(1, close) : text
    }
    var space = text.search(/\s/)
    return space >= 0 ? text.slice(0, space) : text
}

function imageFor(alt, raw, dir) {
    var seen = classifyImage(targetOf(raw), dir)
    if (seen.kind === "remote")
        return "\n\n" + placeholder(seen.host) + "\n\n"
    if (seen.kind === "local")
        return "![" + alt + "](" + seen.url + ")"
    return alt
}

// A raw HTML image tag, neutralised here rather than trusted to a renderer option.
function tagFor(tag, dir) {
    var src = (/src\s*=\s*"([^"]*)"/i.exec(tag) || /src\s*=\s*'([^']*)'/i.exec(tag)
        || /src\s*=\s*([^\s>]+)/i.exec(tag) || [])[1] || ""
    var seen = classifyImage(src, dir)
    if (seen.kind === "remote")
        return "\n\n" + placeholder(seen.host) + "\n\n"
    if (seen.kind === "local")
        return tag.replace(/src\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/i, 'src="' + seen.url + '"')
    var alt = (/alt\s*=\s*"([^"]*)"/i.exec(tag) || /alt\s*=\s*'([^']*)'/i.exec(tag) || [])[1] || ""
    return alt
}

function rewriteProse(segment, dir, defs) {
    var text = String(segment)
    // Inline first: the reference passes below emit final inline forms, and no later pass
    // may resolve those again, which turned a local file:// URL back into its alt text.
    text = text.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, function (whole, alt, inner) {
        return imageFor(alt, inner, dir)
    })
    if (defs) {
        text = text.replace(/!\[([^\]]*)\]\[([^\]]*)\]/g, function (whole, alt, id) {
            var key = (id.length > 0 ? id : alt).toLowerCase()
            if (!defs.hasOwnProperty(key))
                return whole
            return imageFor(alt, defs[key], dir)
        })
        // Shortcut references, `![alt]` with `[alt]: url` defined, which name no target of their own.
        text = text.replace(/!\[([^\]]+)\](?![\(\[])/g, function (whole, alt) {
            var key = alt.toLowerCase()
            if (!defs.hasOwnProperty(key))
                return whole
            return imageFor(alt, defs[key], dir)
        })
    }
    return text
}

// Reference definitions, `[id]: url`, resolved against the same rule.
function definitions(source) {
    var defs = {}
    var lines = String(source).split("\n")
    for (var i = 0; i < lines.length; i++) {
        var match = lines[i].match(/^ {0,3}\[([^\]]+)\]:\s*(\S+)/)
        if (match)
            defs[match[1].toLowerCase()] = match[2]
    }
    return defs
}

// One HTML escape pass: & < > and every ASCII punctuation character become numeric
// entities, so emphasis, links and autolinks cannot form inside converted spans and cells.
function htmlEscaped(text) {
    return String(text).replace(/[&<>\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]/g, function (c) {
        return "&#" + c.charCodeAt(0) + ";"
    })
}

// An inline code span as styled HTML, or the original when no usable chrome arrived.
// The content stays literal through htmlEscaped; letters, digits, spaces and non-ASCII pass.
function codeHtml(content, chrome, original) {
    if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(chrome || "")))
        return original
    return '<code style="background-color:' + chrome + '">' + htmlEscaped(content) + "</code>"
}

// CommonMark code spans over plain text: a run of N backticks opens, the next run of exactly
// N backticks closes, and content with a space at both ends loses one. Unmatched runs stay
// literal. Spans resolve to tokens here and are restored styled after images rewrite, so image
// syntax inside backticks never resolves and styling never lands inside a raw HTML tag.
function codeSpansHold(text, codes, chrome) {
    var out = ""
    var i = 0
    while (i < text.length) {
        if (text.charAt(i) !== "`") {
            out += text.charAt(i)
            i++
            continue
        }
        var open = i
        while (open < text.length && text.charAt(open) === "`")
            open++
        var len = open - i
        var c = open
        var closed = -1
        while (c < text.length) {
            if (text.charAt(c) !== "`") {
                c++
                continue
            }
            var d = c
            while (d < text.length && text.charAt(d) === "`")
                d++
            if (d - c === len) {
                closed = c
                break
            }
            c = d
        }
        if (closed < 0) {
            out += text.slice(i)
            break
        }
        var content = text.slice(open, closed)
        if (content.length > 0 && content.charAt(0) === " " && content.charAt(content.length - 1) === " ")
            content = content.slice(1, -1)
        var token = "\ue000" + codes.length + "\ue001"
        codes.push({ token: token, html: codeHtml(content, chrome, text.slice(i, closed + len)) })
        out += token
        i = closed + len
    }
    return out
}

// Inline links as font-wrapped anchors: the importer hardcodes its own link blue over
// QML linkColor, but a presentational font tag survives the import. Images keep their bang
// and never enter here; reference links and autolinks are handled beside the tags below.
function rewriteLinks(text, ink) {
    return String(text).replace(/(!?)\[([^\]]+)\]\(([^)]+)\)/g, function (whole, bang, label, inner) {
        if (bang === "!")
            return whole
        var html = linkHtml(label, inner, ink)
        return html === null ? whole : html
    })
}

function linkTarget(inner) {
    var text = String(inner).trim()
    if (text.charAt(0) === "<") {
        var close = text.indexOf(">")
        return close > 0 ? text.slice(1, close) : text
    }
    var space = text.search(/\s/)
    return space >= 0 ? text.slice(0, space) : text
}

function linkHtml(label, inner, ink) {
    if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(ink || "")))
        return null
    var url = linkTarget(inner).replace(/&/g, "&#38;")
    return '<a href="' + url + '"><font color="' + ink + '">' + htmlEscaped(label) + "</font></a>"
}

// A prose run: raw HTML tags pass through untouched, so styling never lands inside one;
// elsewhere code spans are held first (image and link syntax inside them never resolves),
// links wrap, images rewrite, and the held spans are restored styled.
function resolveRun(joined, dir, defs, chrome, ink) {
    var segs = String(joined).split(/(<[^<>]*>)/g)
    for (var s = 0; s < segs.length; s += 2) {
        var codes = []
        var held = codeSpansHold(segs[s], codes, chrome)
        var linked = rewriteLinks(held, ink)
        var fixed = rewriteProse(linked, dir, defs)
        for (var i = 0; i < codes.length; i++)
            fixed = fixed.split(codes[i].token).join(codes[i].html)
        segs[s] = fixed
    }
    for (var t = 1; t < segs.length; t += 2) {
        if (/^<img\b/i.test(segs[t]))
            segs[t] = tagFor(segs[t], dir)
        else if (/^<https?:\/\/[^<>]*>$/i.test(segs[t])) {
            var auto = linkHtml(segs[t].slice(1, -1), segs[t].slice(1, -1), ink)
            if (auto !== null)
                segs[t] = auto
        }
    }
    return segs.join("")
}

// Fenced blocks pass through untouched: a URL inside one is shown, never resolved.
function prepare(source, dir, defs, chrome, ink) {
    var body = String(source)
    defs = defs || definitions(body)
    var lines = body.split("\n")
    var out = []
    var prose = []
    var fenced = false
    function flush() {
        if (prose.length > 0)
            out.push(resolveRun(prose.join("\n"), dir, defs, chrome, ink))
        prose = []
    }
    for (var i = 0; i < lines.length; i++) {
        if (/^ {0,3}(```|~~~)/.test(lines[i])) {
            flush()
            fenced = !fenced
            out.push(lines[i])
            continue
        }
        if (fenced)
            out.push(lines[i])
        else
            prose.push(lines[i])
    }
    flush()
    return out.join("\n")
}

// A top-level list marker: up to 3 leading spaces, then digits+[.)] or a bullet, then text.
// Deeper markers nest and join the open item as text rather than splitting the list.
function listMarker(line) {
    var m = String(line).match(/^(\s*)(\d+[.)]|[-*+])(\s+)(.*)$/)
    if (!m)
        return null
    var indent = 0
    for (var i = 0; i < m[1].length; i++)
        indent += m[1].charAt(i) === "\t" ? 4 - (indent % 4) : 1
    if (indent > 3 || m[4].length === 0)
        return null
    var ordered = /^\d/.test(m[2])
    return { indent: indent, ordered: ordered,
             start: ordered ? parseInt(m[2], 10) : 0, text: m[4] }
}
// A paragraph that is one image and nothing else, so it can draw in its own material:
// a remote one as the board's box, a same-folder one as the image itself. A dropped URL
// or an image mid-paragraph stays a run and is handled there.
function imageParagraph(line, dir, defs) {
    var text = String(line).trim()
    var alt = ""
    var raw = null
    var m = text.match(/^!\[([^\]]*)\]\(([^)]+)\)$/)
    if (m) {
        alt = m[1]
        raw = m[2]
    } else if (defs) {
        // A reference names its id, or its own alt for a shortcut; either may be empty-sided.
        var r = text.match(/^!\[([^\]]*)\]\[([^\]]*)\]$/) || text.match(/^!\[([^\]]+)\]$/)
        if (r) {
            var id = (r.length > 2 && r[2].length > 0) ? r[2] : r[1]
            if (!defs.hasOwnProperty(id.toLowerCase()))
                return null
            alt = r[1]
            raw = defs[id.toLowerCase()]
        }
    }
    if (raw !== null) {
        var seen = classifyImage(targetOf(raw), dir)
        if (seen.kind === "remote")
            return { type: "remote", host: seen.host }
        if (seen.kind === "local")
            return { type: "image", url: seen.url, alt: alt }
        return null
    }
    if (!/^<img\b[^<>]*>$/i.test(text))
        return null
    var src = (/src\s*=\s*"([^"]*)"/i.exec(text) || /src\s*=\s*'([^']*)'/i.exec(text)
        || /src\s*=\s*([^\s>]+)/i.exec(text) || [])[1] || ""
    var tag = classifyImage(src, dir)
    if (tag.kind === "remote")
        return { type: "remote", host: tag.host }
    if (tag.kind === "local") {
        var name = (/alt\s*=\s*"([^"]*)"/i.exec(text) || /alt\s*=\s*'([^']*)'/i.exec(text) || [])[1] || ""
        return { type: "image", url: tag.url, alt: name }
    }
    return null
}

// A GFM delimiter row: every cell is dashes with optional edge colons, which also carry
// the alignment. Anything else is not a table, however many pipes it holds.
function delimAligns(line) {
    var cells = String(line).trim().replace(/^\||\|$/g, "").split("|")
    if (cells.length === 0)
        return null
    var aligns = []
    for (var i = 0; i < cells.length; i++) {
        var m = cells[i].match(/^\s*(:?)-+(:?)\s*$/)
        if (!m)
            return null
        aligns.push(m[1] && m[2] ? "center" : m[2] ? "right" : "left")
    }
    return aligns
}

// A table row split on unescaped pipes, with leading/trailing pipes and whitespace shed.
// A backslash before punctuation escapes it, the way GFM reads `\_` as `_` in a cell.
function splitRow(line) {
    var text = String(line).trim().replace(/^\||\|$/g, "")
    var cells = []
    var cell = ""
    for (var i = 0; i < text.length; i++) {
        var ch = text.charAt(i)
        if (ch === "\\" && i + 1 < text.length && /[!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~]/.test(text.charAt(i + 1))) {
            cell += text.charAt(i + 1)
            i++
        } else if (ch === "|") {
            cells.push(cell)
            cell = ""
        } else {
            cell += ch
        }
    }
    cells.push(cell)
    for (var j = 0; j < cells.length; j++)
        cells[j] = cells[j].trim()
    return cells
}

// The board's table as data, drawn by ui/PreviewMarkdown.qml: Qt's Markdown importer drops
// style attributes, so no inline CSS can carry the rules, and the delegate draws them.
function tableBlock(head, aligns, rows) {
    var cols = head.length
    for (var i = 0; i < rows.length; i++)
        cols = Math.max(cols, rows[i].length)
    return {
        type: "table",
        head: head.map(htmlEscaped),
        aligns: aligns,
        rows: rows.map(function (cells) { return cells.map(htmlEscaped) }),
        cols: cols
    }
}

// Top-level block split: runs of ordinary blocks share one Text.MarkdownText, and the
// three special kinds get their own delegates in ui/PreviewMarkdown.qml.
function blocks(source, dir, chrome, ink) {
    var body = String(source)
    var defs = definitions(body)
    var lines = body.split("\n")
    var out = []
    var run = []
    var quote = []
    var fence = null
    function flushRun() {
        if (run.length === 0)
            return
        // A run of blank lines alone draws nothing, so it never becomes a block.
        var text = resolveRun(run.join("\n"), dir, defs, chrome, ink)
        if (text.trim().length > 0)
            out.push({ type: "run", text: text })
        run = []
    }
    function flushQuote() {
        if (quote.length === 0)
            return
        var inner = quote.map(function (line) { return line.replace(/^ {0,3}> ?/, "") })
        out.push({ type: "quote", text: resolveRun(inner.join("\n"), dir, defs, chrome, ink) })
        quote = []
    }
    function flushFence() {
        out.push({ type: "fence", text: fence.join("\n") })
        fence = null
    }
    var list = null
    function flushList() {
        if (list === null)
            return
        var items = []
        for (var k = 0; k < list.items.length; k++)
            items.push(resolveRun(list.items[k].join("\n"), dir, defs, chrome, ink))
        out.push({ type: "list", ordered: list.ordered, start: list.start, items: items })
        list = null
    }
    // A standalone image paragraph has blank lines on both sides; mid-text images stay runs.
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (fence !== null) {
            if (/^ {0,3}(```|~~~)/.test(line)) flushFence(); else fence.push(line)
            continue
        }
        if (/^ {0,3}(```|~~~)/.test(line)) { flushRun(); flushQuote(); flushList(); fence = []; continue }
        // A fence quoted as `> ``` ` is quote content, never a fence: CommonMark nests it.
        if (/^ {0,3}>/.test(line)) { flushRun(); flushList(); quote.push(line); continue }
        // A GFM table: a header line carrying | over a delimiter row, with the body behind it.
        if (line.indexOf("|") >= 0 && i + 1 < lines.length && delimAligns(lines[i + 1]) !== null) {
            var aligns = delimAligns(lines[i + 1])
            var head = splitRow(line)
            var bodyRows = []
            var j = i + 2
            while (j < lines.length && lines[j].trim().length > 0 && lines[j].indexOf("|") >= 0) {
                bodyRows.push(splitRow(lines[j]))
                j++
            }
            flushRun()
            flushQuote()
            flushList()
            out.push(tableBlock(head, aligns, bodyRows))
            i = j - 1
            continue
        }
        var mark = listMarker(line)
        if (mark !== null) {
            // A deeper marker nests and joins the open item as text; dedenting or a kind
            // change at the same depth closes the list first.
            if (list === null || mark.indent < list.indent
                    || (mark.indent === list.indent && mark.ordered !== list.ordered))
                flushList()
            if (list === null) {
                flushRun()
                flushQuote()
                list = { ordered: mark.ordered, start: mark.start, indent: mark.indent, items: [[mark.text]] }
            } else if (mark.indent === list.indent) {
                list.items.push([mark.text])
            } else {
                list.items[list.items.length - 1].push(line)
            }
            continue
        }
        if (list !== null) {
            if (line.trim().length > 0) {
                list.items[list.items.length - 1].push(line)
                continue
            }
            var n = i + 1
            while (n < lines.length && lines[n].trim().length === 0)
                n++
            var nm = n < lines.length ? listMarker(lines[n]) : null
            if (nm !== null && nm.indent <= 3) {
                list.items[list.items.length - 1].push("")
                continue
            }
            flushList()
        }
        var solo = line.trim().length > 0 && (i === 0 || lines[i - 1].trim().length === 0)
            && (i === lines.length - 1 || lines[i + 1].trim().length === 0)
        var held = solo ? imageParagraph(line, dir, defs) : null
        if (held !== null) { flushRun(); flushQuote(); flushList(); out.push(held); continue }
        flushQuote()
        run.push(line)
    }
    if (fence !== null)
        flushFence()
    flushList()
    flushQuote()
    flushRun()
    return out
}
