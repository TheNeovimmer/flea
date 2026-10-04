.pragma library

// MdHtmlImage: a raw HTML image on its own line, alone or inside a centring paragraph, as an image block.
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml

// Sample input: '<p align="center"><a href="https://x"><img src="a.png"></a></p>' splits into wrapper, link, image, link end and closer.
var IMAGE_LINE = /^(<(?:p|div)\b[^<>]*>)?\s*(<a\b[^<>]*>)?\s*(<img\b[^<>]*>)\s*(<\/a>)?\s*(<\/(?:p|div)>)?$/i
// Sample input: '<div align="center">' and '<p>' open a wrapper; '<div>text' and '<span>' do not.
var WRAPPER_OPEN = /^<(?:p|div)\b[^<>]*>$/i
// Sample input: '</div>' and '</P>' close a wrapper and answer its tag name; '</div> text' does not.
var WRAPPER_CLOSE = /^<\/(p|div)>$/i
// Sample input: '<div class="x">' and '</div>' in a line each count once for div, with the slash captured; '<divider>' counts for none.
var WRAPPER_NESTING = { p: /<(\/?)p(?=[\s>\/])[^<>]*>/gi, div: /<(\/?)div(?=[\s>\/])[^<>]*>/gi }
// Sample input: "<br>" or "<br />" at the start of a line; the image above it already ends its line.
var LEADING_BREAK = /^\s*(?:<br\s*\/?>\s*)+/i
// Sample input: " 64", "64px" and "64 " are widths; "50%", "6.4" and "abc" are not.
var WIDTH_VALUE = /^\s*(\d{1,4})(?:px)?\s*$/i

// Sample input: '<p align="center">' is centred; '<p>' and '<div align="left">' are not.
function isCentred(open) {
    var attributes = MdHtml.tagHead(open).attributes
    for (var i = 0; i < attributes.length; i++) {
        if (attributes[i].name === "align")
            return attributes[i].value !== null && attributes[i].value.toLowerCase() === "center"
    }
    return false
}

// Sample input: '<img src="a.png" width="64" alt="x">' answers an image block with its width; null when the tag draws nothing.
function rawImage(text, dir) {
    var tag = MdHtml.readTag(text, 0)
    if (tag === null)
        return null
    var head = MdHtml.tagHead(tag.tag)
    if (head.name !== "img" || head.closing || !head.validAttrs)
        return null
    // First attributes win even when their values are empty or absent.
    var src = null
    var alt = null
    var width = null
    for (var a = 0; a < head.attributes.length; a++) {
        var attr = head.attributes[a]
        var value = attr.value === null ? "" : attr.value
        if (attr.name === "src" && src === null)
            src = value
        if (attr.name === "alt" && alt === null)
            alt = value
        if (attr.name === "width" && width === null)
            width = value
    }
    var cls = MdUrl.classifyImage(src === null ? "" : src, dir)
    if (cls.kind === "remote")
        return { type: "remote", host: cls.host }
    if (cls.kind !== "local")
        return null
    var block = { type: "image", url: cls.url, alt: alt === null ? "" : alt }
    var sized = width === null ? null : WIDTH_VALUE.exec(width)
    if (sized !== null && Number(sized[1]) > 0)
        block.width = Number(sized[1])
    return block
}

// Sample input: '<a href="https://x/y">' answers "https://x/y"; a javascript: or relative target answers null.
function linkOf(open) {
    var attributes = MdHtml.tagHead(open).attributes
    for (var i = 0; i < attributes.length; i++) {
        if (attributes[i].name === "href" && attributes[i].value !== null) {
            var url = MdHtml.normalizedTarget(MdUrl.canonicalUrl(attributes[i].value))
            return /^(?:https?|mailto):/i.test(url) ? url : null
        }
    }
    return null
}

// Sample input: lines ['<p>', 'note', '</p>', '</div>'] from 0 for "div" answer { rest: ['<p>', 'note', '</p>'], end: 3 }; a blank line or a missing closer answers null.
// The lines after a wrapper's image up to the closer of the wrapper's own tag, nested openers of that tag counted, none blank.
function wrapperTail(lines, from, name) {
    var rest = []
    var depth = 1
    for (var j = from; j < lines.length; j++) {
        var line = lines[j].trim()
        if (line === "")
            return null
        var closer = WRAPPER_CLOSE.exec(line)
        if (depth === 1 && closer !== null && closer[1].toLowerCase() === name)
            return { rest: rest, end: j }
        line.replace(WRAPPER_NESTING[name], function (tag, slash) {
            depth += slash === "/" ? -1 : 1
            return tag
        })
        // A closer sharing its line with text, or one with no opener, ends the wrapper where no unit can follow.
        if (depth < 1)
            return null
        rest.push(line)
    }
    return null
}

// Sample input: lines ['<p align="center">', '  <img src="a.png">', '</p>'] at 0 answers { block, end: 2, wrapper: [] }; a line that is no image unit answers null.
// wrapper holds the opener, the lines between the image and the closer, and the closer on one line, to draw under the image; empty when none.
function imageUnit(lines, at, dir) {
    var first = IMAGE_LINE.exec(lines[at].trim())
    var open = null
    var parts = null
    var last = at
    if (first !== null && first[1] !== undefined) {
        open = first[1]
        parts = first
    } else if (first === null && WRAPPER_OPEN.test(lines[at].trim()) && at + 1 < lines.length) {
        parts = IMAGE_LINE.exec(lines[at + 1].trim())
        if (parts === null || parts[1] !== undefined)
            return null
        open = lines[at].trim()
        last = at + 1
    } else {
        return null
    }
    if ((parts[2] === undefined) !== (parts[4] === undefined))
        return null
    var name = MdHtml.tagHead(open).name
    var rest = []
    if (parts[5] !== undefined) {
        if (WRAPPER_CLOSE.exec(parts[5])[1].toLowerCase() !== name)
            return null
    } else {
        var tail = wrapperTail(lines, last + 1, name)
        if (tail === null)
            return null
        rest = tail.rest
        last = tail.end
        // Another image in the wrapper makes the block a row of images, which the block splitter draws whole.
        if (/<img\b/i.test(rest.join("\n")))
            return null
    }
    var block = rawImage(parts[3], dir)
    if (block === null)
        return null
    if (isCentred(open))
        block.align = "center"
    if (parts[2] !== undefined && block.type === "image" && linkOf(parts[2]) !== null)
        block.link = linkOf(parts[2])
    if (rest.length > 0)
        rest[0] = rest[0].replace(LEADING_BREAK, "")
    var shown = []
    for (var r = 0; r < rest.length; r++) {
        if (rest[r].length > 0)
            shown.push(rest[r])
    }
    return { block: block, end: last, wrapper: shown.length === 0 ? [] : [open + shown.join("\n") + "</" + name + ">"] }
}
