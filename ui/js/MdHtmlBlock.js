.pragma library

// MdHtmlBlock: images leave an HTML block as image blocks, and top-level HTML blocks start their own lines.
.import "MdHtml.js" as MdHtml
.import "MdHtmlImage.js" as HtmlImage

// The names CommonMark starts an HTML block with, and one complete tag alone on its line, which starts one only outside a paragraph.
var BLOCK_NAMES = "address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|meta|nav|noframes|ol|optgroup|option|p|param|section|source|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul"
// Sample input: '<div align="center">' and '  </table>' start an HTML block; '<span>x</span>' and 'text <div>' do not.
var BLOCK_START = new RegExp("^ {0,3}<\\/?(?:" + BLOCK_NAMES + ")(?:[\\s>]|\\/>|$)", "i")
// Sample input: '<a href="x">' and '</span>' alone on a line are complete tags; '<a href="x">text' is not.
var COMPLETE_TAG = /^ {0,3}(?:<[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?\/?>|<\/[A-Za-z][A-Za-z0-9-]*\s*>)\s*$/
// Sample input: 'x <a href="https://y">' ends with a link opener, which the text before an image holds when the image sits in a link.
var LINK_BEFORE = /<a\b[^<>]*>\s*$/i
// Sample input: '</a>' and '</A>' close the link around an image; the four characters after the image are tested against it.
var LINK_CLOSE = /^<\/a>$/i
var LINK_CLOSE_LENGTH = "</a>".length
// Sample input: 'A<IMG' holds the capital letters asciiLower lowers, by their distance from lower case.
var UPPER_ASCII = /[A-Z]/g
var CASE_OFFSET = "a".charCodeAt(0) - "A".charCodeAt(0)
// Sample input: '<p align="center"><b>x</b>' and '<center>' open a block that may centre; '<span>' and 'text' do not.
var CENTRED_OPEN = /^\s*<(?:p|div|center)\b[^<>]*>/i
// Sample input: 'a <div>b</div>' and '<h1 align="center">' hold a block tag that centres itself; '<b>x</b>' holds none.
var BLOCK_TAG = /<(?:p|div|h[1-6]|table|ul|ol|blockquote|pre)\b/i
// Sample input: '</p><p>' and '<div align="center">' open or close a block, so pictures either side of them sit on lines of their own; '<b>' and '</td><td>' do not.
var BLOCK_BOUNDARY = /<\/?(?:p|div|h[1-6]|table|tr|ul|ol|li|blockquote|pre)\b/i
// Sample input: '<br>' and '<BR />' break a line.
var BREAK_TAG = /<br\b[^<>]*>/i
// The most pictures one images block holds.
var ROW_IMAGE_CAP = 64
var CENTRED_WRAP = '<p align="center">'
// The elements that start their own line, and the ones that nest and so are counted open and closed.
// Sample input: '<h1 align="center">Flea</h1>' and '  <details open>' start a line of their own; '<b>x</b>' does not.
var LINE_OPENER = /^ {0,3}<(?:p|div|h[1-6]|details|summary|hr|table|ul|ol|blockquote|pre)(?=[\s>\/])/i
// Sample input: '<div class="x">' answers slash "" and '</div>' answers "/"; '<b>' and '<divider>' match nothing.
var NESTING_TAG = /<(\/?)(?:p|div|h[1-6]|details|summary|table|ul|ol|blockquote|pre)(?=[\s>\/])[^<>]*>/gi
// Sample input: '<b>' answers slash "" and name "b"; '</p>' answers "/" and "p"; text with no angle bracket matches nothing.
var ANY_TAG = /<(\/?)([A-Za-z][A-Za-z0-9]*)[^<>]*>/g

// Sample input: '<IMG SRC>' after a U+0130 answers '<img src>'; only A to Z change, so an index in the answer is an index in the text.
function asciiLower(text) {
    return text.replace(UPPER_ASCII, function (letter) { return String.fromCharCode(letter.charCodeAt(0) + CASE_OFFSET) })
}

// Sample input: '<td><img src="a.png"></td>' from 0 answers { start: 4, end: 24, block }; remote and unreadable images answer null.
// lower is the line in asciiLower form and dead its tag cache, made once per line, so a row of many images costs one pass.
function findImage(line, lower, from, dead, dir) {
    var at = lower.indexOf("<img", from)
    while (at >= 0) {
        var tag = MdHtml.readTag(line, at, dead)
        var block = tag === null ? null : HtmlImage.rawImage(tag.tag, dir)
        if (block !== null && block.type === "image")
            return { start: at, end: tag.end, block: block }
        at = lower.indexOf("<img", at + 1)
    }
    return null
}

// Sample input: '<td>a</p>' drops the closer no opener in the text matches; text with its own pairs is unchanged.
function withoutStrayClosers(text) {
    var open = {}
    return text.replace(ANY_TAG, function (tag, slash, name) {
        var key = name.toLowerCase()
        if (slash === "") {
            open[key] = (open[key] || 0) + 1
            return tag
        }
        if (open[key] > 0) {
            open[key]--
            return tag
        }
        return ""
    })
}

// What stays of the lines around an extracted image: lines with visible text, their stray closers gone, centred when its block was.
function remainder(kept, centred) {
    var split = withoutStrayClosers(kept.join("\n")).split("\n")
    var lines = []
    // A line that holds a block tag of its own centres itself; wrapping it would nest the paragraphs.
    var nests = false
    for (var i = 0; i < split.length; i++) {
        // A line holding an image the splitter did not take (a remote one) draws its placeholder, so it stays.
        if (split[i].replace(ANY_TAG, "").trim().length === 0 && !/<(?:hr|img)\b/i.test(split[i]))
            continue
        lines.push(split[i])
        nests = nests || BLOCK_TAG.test(split[i])
    }
    if (lines.length > 0)
        lines[0] = lines[0].replace(HtmlImage.LEADING_BREAK, "")
    return lines.length === 0 ? [] : centred && !nests ? [CENTRED_WRAP + lines.join("\n") + "</p>"] : lines
}

// Sample input: images a and b with nothing between them answer [{ block: { type: "images", items: [a, b] } }]; one image, text or a row break keeps them apart.
// A row longer than ROW_IMAGE_CAP continues in the next block, so no block builds an unbounded number of pictures at once.
function imageRows(parts) {
    var out = []
    var row = []
    function close() {
        for (var at = 0; at < row.length; at += ROW_IMAGE_CAP) {
            var items = row.slice(at, at + ROW_IMAGE_CAP)
            if (items.length === 1) {
                out.push({ block: items[0] })
                continue
            }
            var rows = { type: "images", items: items }
            if (items[0].align !== undefined)
                rows.align = items[0].align
            for (var r = 0; r < items.length; r++)
                delete items[r].align
            out.push({ block: rows })
        }
        row = []
    }
    for (var i = 0; i < parts.length; i++) {
        if (parts[i].block !== undefined) {
            row.push(parts[i].block)
        } else {
            close()
            if (parts[i].lines !== undefined)
                out.push(parts[i])
        }
    }
    close()
    return out
}

// One HTML block's lines as parts, each a { lines } to parse or a { block } image; the block's wrappers do not outlive its image.
function splitBlock(group, dir) {
    var centred = CENTRED_OPEN.test(group[0]) && (/^\s*<center\b/i.test(group[0]) || HtmlImage.isCentred(CENTRED_OPEN.exec(group[0])[0]))
    var parts = []
    var kept = []
    var found = false
    function flush() {
        var lines = remainder(kept, centred)
        // A line break or a block boundary between two images starts the next row.
        var between = kept.join("\n")
        var broke = BREAK_TAG.test(between) || BLOCK_BOUNDARY.test(between)
        kept = []
        if (lines.length > 0)
            parts.push({ lines: lines })
        else if (broke)
            parts.push({ rowBreak: true })
    }
    for (var i = 0; i < group.length; i++) {
        var line = group[i]
        var lower = asciiLower(line)
        var dead = { tagDead: -1 }
        // The scan walks the line by position, so a line of many images is cut once, never once per image.
        var from = 0
        for (var hit = findImage(line, lower, from, dead, dir); hit !== null; hit = findImage(line, lower, from, dead, dir)) {
            var before = line.slice(from, hit.start)
            var wrap = LINK_BEFORE.exec(before)
            // The link closer follows the image after optional whitespace.
            var next = hit.end
            while (next < line.length && /\s/.test(line.charAt(next)))
                next++
            from = hit.end
            if (wrap !== null && LINK_CLOSE.test(line.slice(next, next + LINK_CLOSE_LENGTH))) {
                if (HtmlImage.linkOf(wrap[0]) !== null)
                    hit.block.link = HtmlImage.linkOf(wrap[0])
                before = before.slice(0, wrap.index)
                from = next + LINK_CLOSE_LENGTH
            }
            kept.push(before)
            flush()
            if (centred)
                hit.block.align = "center"
            parts.push({ block: hit.block })
            found = true
        }
        kept.push(line.slice(from))
    }
    flush()
    return found ? imageRows(parts) : [{ lines: group }]
}

// Sample input: ['<table><tr><td><img src="a.png"></td></tr></table>'] answers [{ block }]; a paragraph's inline image stays in its lines.
// The importer draws no Markdown inside an HTML block and drops a raw img with all that follows it, so a block's images leave it.
function splitHtmlImages(lines, dir) {
    var parts = []
    var text = []
    var group = null
    var paragraph = false
    function closeGroup() {
        if (group !== null) {
            var split = splitBlock(group, dir)
            for (var s = 0; s < split.length; s++)
                parts.push(split[s])
        }
        group = null
    }
    function closeText() {
        if (text.length > 0)
            parts.push({ lines: text })
        text = []
    }
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (line.trim().length === 0) {
            closeGroup()
            text.push(line)
            paragraph = false
        } else if (group !== null) {
            group.push(line)
        } else if (BLOCK_START.test(line) || (!paragraph && COMPLETE_TAG.test(line))) {
            closeText()
            group = [line]
        } else {
            paragraph = true
            text.push(line)
        }
    }
    closeGroup()
    closeText()
    // Lines the split left alone stay one run, as the importer joins an HTML block with the paragraph after it.
    var merged = []
    for (var k = 0; k < parts.length; k++) {
        var last = merged.length - 1
        if (last >= 0 && merged[last].lines !== undefined && parts[k].lines !== undefined) {
            for (var m = 0; m < parts[k].lines.length; m++)
                merged[last].lines.push(parts[k].lines[m])
        } else {
            merged.push(parts[k].lines === undefined ? parts[k] : { lines: parts[k].lines.slice(0) })
        }
    }
    return merged
}

// Sample input: ['<h1>A</h1>', '<p>B</p>'] answers ['<h1>A</h1>', '', '<p>B</p>']; a block nested in an open one stays on its line.
// The importer draws adjacent HTML block lines as one line, so each top-level block starts after a blank line.
function separateBlocks(lines) {
    var out = []
    var depth = 0
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (line.trim().length === 0)
            depth = 0
        else if (depth === 0 && out.length > 0 && out[out.length - 1].trim().length > 0 && LINE_OPENER.test(line))
            out.push("")
        out.push(line)
        line.replace(NESTING_TAG, function (tag, slash) {
            depth = slash === "/" ? Math.max(0, depth - 1) : depth + 1
            return tag
        })
    }
    return out
}

// The six heading levels by tag name, so an HTML heading maps to its Markdown level.
var HEADING_LEVEL = { h1: 1, h2: 2, h3: 3, h4: 4, h5: 5, h6: 6 }
// The shortest heading line that holds text, "<h1>x</h1>": anything shorter is never one.
var HEADING_SHORTEST = 10
// Sample input: '<h1 align="center">Flea</h1>' answers level 1 with centre and inner Flea; '<h2>x</h2> tail' answers null.
function htmlHeading(line) {
    var text = String(line).trim()
    if (text.length < HEADING_SHORTEST)
        return null
    var open = MdHtml.readTag(text, 0, null)
    if (open === null || open.end <= 0)
        return null
    var head = MdHtml.tagHead(open.tag)
    var level = HEADING_LEVEL[head.name]
    if (level === undefined || head.closing)
        return null
    var rest = text.slice(open.end)
    var lower = asciiLower(rest)
    var closeName = "</h" + level
    var closeAt = lower.lastIndexOf(closeName)
    if (closeAt < 0)
        return null
    var close = MdHtml.readTag(text, open.end + closeAt, null)
    if (close === null || close.end !== text.length)
        return null
    var closeHead = MdHtml.tagHead(close.tag)
    if (closeHead.name !== head.name || !closeHead.closing)
        return null
    var inner = rest.slice(0, closeAt)
    var align = null
    for (var i = 0; i < head.attributes.length; i++) {
        if (head.attributes[i].name === "align" && head.attributes[i].value !== null) {
            var seen = head.attributes[i].value.toLowerCase()
            if (seen === "center" || seen === "right")
                align = seen
        }
    }
    return { level: level, align: align, inner: inner }
}
