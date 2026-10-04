.pragma library

// MdHtmlBlock: images leave an HTML block as image blocks, and top-level HTML blocks start their own lines.
.import "MdHtml.js" as MdHtml
.import "MdHtmlImage.js" as HtmlImage

// The names CommonMark starts an HTML block with, and one complete tag alone on its line, which starts one only outside a paragraph.
var BLOCK_NAMES = "address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|meta|nav|noframes|ol|optgroup|option|p|param|section|source|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul"
var BLOCK_START = new RegExp("^ {0,3}<\\/?(?:" + BLOCK_NAMES + ")(?:[\\s>]|\\/>|$)", "i")
var COMPLETE_TAG = /^ {0,3}(?:<[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?\/?>|<\/[A-Za-z][A-Za-z0-9-]*\s*>)\s*$/
var LINK_BEFORE = /<a\b[^<>]*>\s*$/i
var LINK_AFTER = /^\s*<\/a>/i
var CENTRED_OPEN = /^\s*<(?:p|div|center)\b[^<>]*>/i
var BLOCK_TAG = /<(?:p|div|h[1-6]|table|ul|ol|blockquote|pre)\b/i
var CENTRED_WRAP = '<p align="center">'
// The elements that start their own line, and the ones that nest and so are counted open and closed.
var LINE_OPENER = /^ {0,3}<(?:p|div|h[1-6]|details|summary|hr|table|ul|ol|blockquote|pre)(?=[\s>\/])/i
var NESTING_TAG = /<(\/?)(?:p|div|h[1-6]|details|summary|table|ul|ol|blockquote|pre)(?=[\s>\/])[^<>]*>/gi
var ANY_TAG = /<(\/?)([A-Za-z][A-Za-z0-9]*)[^<>]*>/g

// Sample input: '<td><img src="a.png"></td>' at 0 answers { start: 4, end: 24, block }; remote and unreadable images answer null.
function findImage(line, dir) {
    var lower = line.toLowerCase()
    var dead = { tagDead: -1 }
    var at = lower.indexOf("<img")
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
        if (split[i].replace(ANY_TAG, "").trim().length === 0 && !/<hr\b/i.test(split[i]))
            continue
        lines.push(split[i])
        nests = nests || BLOCK_TAG.test(split[i])
    }
    if (lines.length > 0)
        lines[0] = lines[0].replace(HtmlImage.LEADING_BREAK, "")
    return lines.length === 0 ? [] : centred && !nests ? [CENTRED_WRAP + lines.join("\n") + "</p>"] : lines
}

// One HTML block's lines as parts, each a { lines } to parse or a { block } image; the block's wrappers do not outlive its image.
function splitBlock(group, dir) {
    var centred = CENTRED_OPEN.test(group[0]) && (/^\s*<center\b/i.test(group[0]) || HtmlImage.isCentred(CENTRED_OPEN.exec(group[0])[0]))
    var parts = []
    var kept = []
    var found = false
    function flush() {
        var lines = remainder(kept, centred)
        kept = []
        if (lines.length > 0)
            parts.push({ lines: lines })
    }
    for (var i = 0; i < group.length; i++) {
        var line = group[i]
        for (var hit = findImage(line, dir); hit !== null; hit = findImage(line, dir)) {
            var before = line.slice(0, hit.start)
            var after = line.slice(hit.end)
            var wrap = LINK_BEFORE.exec(before)
            if (wrap !== null && LINK_AFTER.test(after)) {
                if (HtmlImage.linkOf(wrap[0]) !== null)
                    hit.block.link = HtmlImage.linkOf(wrap[0])
                before = before.slice(0, wrap.index)
                after = after.replace(LINK_AFTER, "")
            }
            kept.push(before)
            flush()
            if (centred)
                hit.block.align = "center"
            parts.push({ block: hit.block })
            found = true
            line = after
        }
        kept.push(line)
    }
    flush()
    return found ? parts : [{ lines: group }]
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
