.pragma library

// MdLeaf: leaf-block readers over MdRun (tasks, fences, breaks, tables, images, alerts), each a pure function of its lines.
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml
.import "MdInline.js" as Md
.import "MdRun.js" as Run

// Sample input: "[x] done" draws a checked GFM task box; "[ ] pending" draws an empty one.
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

// Sample input: "  * * *" is a thematic break.
function isThematic(line) {
    return /^ {0,3}([*_-])(?:[ \t]*\1){2,}[ \t]*$/.test(String(line))
}

// Sample: "Title\n=" or "Title\n--" closes a paragraph with a setext underline.
function isSetext(line) {
    return /^ {0,3}(?:=+|-+)[ \t]*$/.test(String(line))
}

// Sample input: "```js" opens a backtick fence with info "js".
function fenceOpen(line) {
    var m = /^ {0,3}(```+|~~~+) *(.*)$/.exec(String(line))
    if (m === null)
        return null
    if (m[1].charAt(0) === "`" && m[2].indexOf("`") >= 0)
        return null
    return { tick: m[1].charAt(0), len: m[1].length, info: m[2].replace(/\s+$/, "") }
}

// Sample input: "```" closes a backtick fence opened with length 3.
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

// Sample input: "[!NOTE] Remember this" names a GFM alert and its trailing text.
function alertTitle(line) {
    var m = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(.*)$/i.exec(String(line))
    if (m === null)
        return null
    var title = m[1].charAt(0) + m[1].slice(1).toLowerCase()
    return "**" + title + "**" + (m[2].length > 0 ? " " + m[2] : "")
}
