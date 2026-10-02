.pragma library

// MdLeaf: leaf-block readers over MdRun (tasks, fences, breaks, tables, images, alerts), each a pure function of its lines.
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml
.import "MdInline.js" as Md
.import "MdRun.js" as Run
.import "MdRefs.js" as Refs

// GFM task items draw their box, checked or not; anything else passes through.
function taskText(text) {
    var m = /^\[([ xX])\] (.*)$/.exec(String(text))
    if (m === null)
        return text
    return (m[1] === " " ? "\u2610 " : "\u2611 ") + m[2]
}

function indentOf(line) {
    var n = 0
    while (n < line.length && line.charAt(n) === " ")
        n++
    return n
}

function isThematic(line) {
    return /^ {0,3}([*_-])(?: *\1){2,} *$/.test(String(line))
}

// An ATX heading: up to 3 spaces, 1 to 6 hashes, a space or the end, the text and an optional closing run of hashes. Linear, no backtracking.
// Sample input: "## Second level ##" answers { level: 2, text: "Second level" }; "#hashtag" answers null.
function atxHeading(line) {
    var s = String(line)
    var i = 0
    while (i < 3 && s.charAt(i) === " ")
        i++
    var from = i
    while (i < s.length && s.charAt(i) === "#")
        i++
    var level = i - from
    if (level < 1 || level > 6 || (i < s.length && s.charAt(i) !== " " && s.charAt(i) !== "\t"))
        return null
    var end = s.length
    while (end > i && (s.charAt(end - 1) === " " || s.charAt(end - 1) === "\t"))
        end--
    var close = end
    while (close > i && s.charAt(close - 1) === "#")
        close--
    if (close < end && (close === i || s.charAt(close - 1) === " " || s.charAt(close - 1) === "\t"))
        end = close
    while (end > i && (s.charAt(end - 1) === " " || s.charAt(end - 1) === "\t"))
        end--
    while (i < end && (s.charAt(i) === " " || s.charAt(i) === "\t"))
        i++
    return { level: level, text: s.slice(i, end) }
}

// The heading's text is drawn as its own document, so a leading block marker must stay literal.
// Sample input: 1. Intro answers 1\. Intro; - item answers \- item; _Plain_ is unchanged.
function headingSafe(text) {
    var t = String(text)
    var ordered = /^(\d{1,9})([.)])(?=[ \t]|$)/.exec(t)
    if (ordered !== null)
        return ordered[1] + "\\" + t.slice(ordered[1].length)
    var block = /^(?:[-+*](?:[ \t]|$)|>|#{1,6}(?:[ \t]|$)|~~~)/.test(t)
    return block || isThematic(t) ? "\\" + t : t
}

function fenceOpen(line) {
    var m = /^ {0,3}(```+|~~~+) *(.*)$/.exec(String(line))
    if (m === null)
        return null
    return { tick: m[1].charAt(0), len: m[1].length, info: m[2].replace(/\s+$/, "") }
}

function fenceClose(line, tick, len) {
    var m = /^ {0,3}(```+|~~~+) *$/.exec(String(line))
    return m !== null && m[1].charAt(0) === tick && m[1].length >= len
}

// Sample input: "| :--- | ---: |"; dashes with optional edge colons carry the alignment, anything else is not a table.
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

// Sample input: "| a | b \| c |"; split on unescaped pipes, edge pipes shed, a backslash before punctuation escapes it.
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

// The board's table as data for ui/PreviewMarkdown.qml: Qt's Markdown importer drops style attributes.
function tableBlock(head, aligns, rows) {
    var cols = head.length
    for (var i = 0; i < rows.length; i++)
        cols = Math.max(cols, rows[i].length)
    return {
        type: "table",
        head: head.map(Md.escapeHtmlText),
        aligns: aligns,
        rows: rows.map(function (cells) { return cells.map(Md.escapeHtmlText) }),
        cols: cols
    }
}

// Sample input: "![alt](a.png)", "![alt][ref]" or one raw <img> tag; balanced brackets nest, backslashes skip.
function standaloneImage(line, dir, defs) {
    var text = String(line).trim()
    var end = scanBalanced(text, 2)
    if (text.charAt(0) === "!" && text.charAt(1) === "[" && end > 0) {
        var alt = text.slice(2, end)
        var after = end + 1
        var target = null
        if (text.charAt(after) === "(") {
            var t = Md.readInlineTarget(text, after)
            if (t === null || t.end !== text.length)
                return null
            target = t.url
        } else if (text.charAt(after) === "[") {
            var r = Md.readLabelRef(text, after)
            if (r === null || r.end !== text.length)
                return null
            var key = Md.normalizeLabel(r.label.length > 0 ? r.label : alt)
            if (!defs.hasOwnProperty(key))
                return null
            target = defs[key]
        } else if (after === text.length) {
            var skey = Md.normalizeLabel(alt)
            if (alt.length === 0 || !defs.hasOwnProperty(skey))
                return null
            target = defs[skey]
        } else {
            return null
        }
        return imageBlock(alt, target, dir)
    }
    if (/^<img\b[^<>]*>$/i.test(text)) {
        var tag = MdHtml.readTag(text, 0)
        if (tag === null)
            return null
        var src = (/src\s*=\s*"([^"]*)"/i.exec(text) || /src\s*=\s*'([^']*)'/i.exec(text)
            || /src\s*=\s*([^\s>]+)/i.exec(text) || [])[1] || ""
        var cls = MdUrl.classifyImage(src, dir)
        if (cls.kind === "remote")
            return { type: "remote", host: cls.host }
        if (cls.kind === "local") {
            var name = (/alt\s*=\s*"([^"]*)"/i.exec(text) || /alt\s*=\s*'([^']*)'/i.exec(text) || [])[1] || ""
            return { type: "image", url: cls.url, alt: name }
        }
        return null
    }
    return null
}

// Balanced ] scan from the [ at pos; backslash escapes skipped. -1 when open.
function scanBalanced(text, pos) {
    var depth = 0
    var i = pos
    while (i < text.length) {
        var c = text.charAt(i)
        if (c === "\\") {
            i += 2
            continue
        }
        if (c === "[")
            depth++
        else if (c === "]") {
            if (depth === 0)
                return i
            depth--
        }
        i++
    }
    return -1
}

function imageBlock(alt, target, dir) {
    var seen = MdUrl.classifyImage(target, dir)
    if (seen.kind === "remote")
        return { type: "remote", host: seen.host }
    if (seen.kind === "local")
        return { type: "image", url: seen.url, alt: alt }
    return null
}

function alertTitle(line) {
    var m = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(.*)$/i.exec(String(line))
    if (m === null)
        return null
    var title = m[1].charAt(0) + m[1].slice(1).toLowerCase()
    return "**" + title + "**" + (m[2].length > 0 ? " " + m[2] : "")
}

// Prepare one document's prose for md4c: fences pass through, the rest resolves inline, definitions are dropped.
function prepare(source, dir, defs, chrome, ink) {
    var body = String(source)
    var rawLines = body.split("\n")
    var found = Refs.collectDefs(rawLines)
    var foot = Refs.collectFootnotes(rawLines)
    var hide = {}
    var ranges = found.dropped.concat(foot.dropped)
    for (var h = 0; h < ranges.length; h++)
        for (var l = ranges[h][0]; l <= ranges[h][1]; l++)
            hide[l] = true
    var lines = []
    for (var li = 0; li < rawLines.length; li++) {
        if (!hide.hasOwnProperty(li))
            lines.push(rawLines[li])
    }
    defs = defs || found.defs
    var tokens = []
    function inlineOf(joined) {
        return Run.parseInline(joined, dir, defs, foot.numbers, chrome, ink, tokens)
    }
    var out = []
    var prose = []
    var fenced = false
    function flush() {
        if (prose.length > 0)
            out.push(inlineOf(prose.join("\n")))
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
            prose.push(Refs.killDefinition(lines[i]))
    }
    flush()
    return out.join("\n")
}
