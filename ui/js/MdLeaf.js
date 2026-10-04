.pragma library

// MdLeaf: leaf-block readers over MdRun (tasks, fences, breaks, tables, images, alerts), each a pure function of its lines.
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml
.import "MdInline.js" as Md
.import "MdLink.js" as Link

// The limits MdContainer names for list markers; the worker bundle shares only functions between files, so each holds its own.
var MAX_MARKER_INDENT = 3
var MAX_MARKER_DIGITS = 9
var MAX_HEADING_LEVEL = 6
var hasOwn = Object.prototype.hasOwnProperty
var ORDERED_MARKER = new RegExp("^(\\d{1," + MAX_MARKER_DIGITS + "})([.)])(?=[ \\t]|$)")
var HEADING_MARKER = new RegExp("^(?:[-+*](?:[ \\t]|$)|>|#{1," + MAX_HEADING_LEVEL + "}(?:[ \\t]|$)|```|~~~)")

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

// Sample input: "## Second level ##" answers { level: 2, text: "Second level" }; "#hashtag" answers null.
function atxHeading(line) {
    var s = String(line)
    var i = 0
    while (i < MAX_MARKER_INDENT && s.charAt(i) === " ")
        i++
    var from = i
    while (i < s.length && s.charAt(i) === "#")
        i++
    var level = i - from
    if (level < 1 || level > MAX_HEADING_LEVEL || (i < s.length && s.charAt(i) !== " " && s.charAt(i) !== "\t"))
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

// Sample input: 1. Intro answers 1\. Intro; - item answers \- item; _Plain_ is unchanged.
function headingSafe(text) {
    var t = String(text)
    var ordered = ORDERED_MARKER.exec(t)
    if (ordered !== null)
        return ordered[1] + "\\" + t.slice(ordered[1].length)
    var block = HEADING_MARKER.test(t)
    return block || isThematic(t) ? "\\" + t : t
}

// Sample: "Title\n=" or "Title\n--" closes a paragraph with a setext underline.
function isSetext(line) {
    return /^ {0,3}(?:=+|-+)[ \t]*$/.test(String(line))
}

// Sample input: "===" underlines a level 1 heading, "---" and "--" a level 2.
function setextLevel(line) {
    return String(line).trim().charAt(0) === "=" ? 1 : 2
}

// Sample input: "```js" opens a backtick fence with info "js".
function fenceOpen(line) {
    var m = /^( {0,3})(```+|~~~+) *(.*)$/.exec(String(line))
    if (m === null)
        return null
    if (m[2].charAt(0) === "`" && m[3].indexOf("`") >= 0)
        return null
    return { tick: m[2].charAt(0), len: m[2].length, indent: m[1].length, info: m[3].replace(/\s+$/, "") }
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

// Sample input: "| a | b \|" keeps the final pipe as cell text; other backslash pairs reach the inline scanner.
function splitRow(line) {
    var text = String(line).trim().replace(/^\|/, "")
    var cells = []
    var cell = ""
    for (var i = 0; i < text.length; i++) {
        var ch = text.charAt(i)
        if (ch === "\\" && i + 1 < text.length && /[!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~]/.test(text.charAt(i + 1))) {
            cell += text.charAt(i + 1) === "|" ? "|" : ch + text.charAt(i + 1)
            i++
        } else if (ch === "|") {
            if (i + 1 === text.length)
                break
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

// Rows per table chunk and items per list chunk: a longer container is emitted as consecutive blocks the outer ListView draws lazily.
var TABLE_CHUNK_ROWS = 24
var LIST_CHUNK_ITEMS = 32

// Sample input: '<a href="https://x.example/long"><font color="#eeeeee">a</font></a>' draws 1 character, "**bo**ld&#33;" draws 5.
function renderedLength(cell) {
    // Raw markers are markup (a literal one arrives as an entity), so they go before entities decode.
    var plain = String(cell).replace(/<[^>"]*("[^"]*"[^>"]*)*>/g, "").replace(/[*_~`]/g, "")
    return plain.replace(/&#(\d+);/g, function (m, n) {
        return String.fromCharCode(parseInt(n, 10))
    }).replace(/&(amp|lt|gt|quot);/g, "?").length
}

// Sample input: ["a", "b&#33;&#33;"] measures "b&#33;&#33;" (3 characters drawn) over "a" (1).
function longestCell(cells) {
    var best = ""
    var bestLength = 0
    for (var i = 0; i < cells.length; i++) {
        var drawn = renderedLength(cells[i])
        if (drawn > bestLength) {
            best = cells[i]
            bestLength = drawn
        }
    }
    return best
}

// The board's table as data (Qt's importer drops style attributes); measure is each column's widest cell, so chunks share widths.
function tableBlock(head, aligns, rows, inlineOf) {
    var cols = head.length
    var shownHead = head.map(inlineOf)
    // GFM: a row's cells beyond the header's are dropped, and a short row is padded with empty cells.
    var shownRows = rows.map(function (cells) {
        var row = cells.slice(0, cols).map(inlineOf)
        while (row.length < cols)
            row.push("")
        return row
    })
    var measure = []
    for (var c = 0; c < cols; c++) {
        var column = [c < shownHead.length ? shownHead[c] : ""]
        for (var r = 0; r < shownRows.length; r++)
            column.push(c < shownRows[r].length ? shownRows[r][c] : "")
        measure.push(longestCell(column))
    }
    return { type: "table", head: shownHead, aligns: aligns, rows: shownRows, cols: cols, measure: measure }
}

// Splits a long table into consecutive blocks: the header stays on the first, the rest are marked joined.
function chunkTable(table) {
    if (table.rows.length <= TABLE_CHUNK_ROWS)
        return [table]
    var chunks = []
    for (var at = 0; at < table.rows.length; at += TABLE_CHUNK_ROWS)
        chunks.push({ type: "table", head: at === 0 ? table.head : [], aligns: table.aligns,
            rows: table.rows.slice(at, at + TABLE_CHUNK_ROWS), cols: table.cols, measure: table.measure, joined: at > 0 })
    return chunks
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
            var t = Link.readInlineTarget(text, after)
            if (t === null || t.end !== text.length)
                return null
            target = t.url
        } else if (text.charAt(after) === "[") {
            var r = Link.readLabelRef(text, after)
            if (r === null || r.end !== text.length)
                return null
            var key = Link.normalizeLabel(r.label.length > 0 ? r.label : alt)
            if (!hasOwn.call(defs, key))
                return null
            target = defs[key]
        } else if (after === text.length) {
            var skey = Link.normalizeLabel(alt)
            if (alt.length === 0 || !hasOwn.call(defs, skey))
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
        var head = MdHtml.tagHead(tag.tag)
        if (head.name !== "img" || head.closing || !head.validAttrs)
            return null
        // First attributes win even when their values are empty or absent.
        var src = null
        var alt = null
        for (var a = 0; a < head.attributes.length; a++) {
            var attr = head.attributes[a]
            if (attr.name === "src" && src === null)
                src = attr.value === null ? "" : attr.value
            if (attr.name === "alt" && alt === null)
                alt = attr.value === null ? "" : attr.value
        }
        var cls = MdUrl.classifyImage(src === null ? "" : src, dir)
        if (cls.kind === "remote")
            return { type: "remote", host: cls.host }
        if (cls.kind === "local")
            return { type: "image", url: cls.url, alt: alt === null ? "" : alt }
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
    var title = m[1].charAt(0).toUpperCase() + m[1].slice(1).toLowerCase()
    return "**" + title + "**" + (m[2].length > 0 ? " " + m[2] : "")
}
