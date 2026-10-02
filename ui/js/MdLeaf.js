.pragma library

// MdLeaf: leaf-block readers over MdRun's inline driver. Task text, fences,
// thematic breaks, GFM tables, standalone images and alerts; each reader is a
// pure function of its lines, so the block splitter stays a loop.
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

// A GFM delimiter row: every cell is dashes with optional edge colons, which
// also carry the alignment. Anything else is not a table.
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

// A table row split on unescaped pipes, with leading/trailing pipes shed.
// A backslash before punctuation escapes it, the way GFM reads \_ as _.
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

// The board's table as data, drawn by ui/PreviewMarkdown.qml: Qt's Markdown
// importer drops style attributes, so no inline CSS can carry the rules.
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

// A standalone image paragraph: inline, reference (full, collapsed, shortcut)
// or a single raw <img> tag. Balanced brackets nest; backslash escapes skip.
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

// Prepare one document's prose for md4c: fenced blocks pass through untouched,
// everything else resolves through the inline driver. Reference definitions
// are dropped after collection, never rendered.
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
