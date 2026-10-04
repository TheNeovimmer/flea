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
// Sample input: '<p>text <img src="b.png"></p>' holds a second image; '<p>text</p>' and '<imgs>' hold none.
var SECOND_IMAGE = /<img\b/i
// Sample input: "<br>" or "<br />" at the start of a line; the image above it already ends its line.
var LEADING_BREAK = /^\s*(?:<br\s*\/?>\s*)+/i
// Sample input: " 64", "64px" and "64 " are sizes; "50%", "6.4" and "abc" are not.
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

// Sample input: '<img src="a.png" width="64" height="20" alt="x">' answers an image block with its width and height; null when the tag draws nothing.
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
    var height = null
    for (var a = 0; a < head.attributes.length; a++) {
        var attr = head.attributes[a]
        var value = attr.value === null ? "" : attr.value
        if (attr.name === "src" && src === null)
            src = value
        if (attr.name === "alt" && alt === null)
            alt = value
        if (attr.name === "width" && width === null)
            width = value
        if (attr.name === "height" && height === null)
            height = value
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
    var tall = height === null ? null : WIDTH_VALUE.exec(height)
    if (tall !== null && Number(tall[1]) > 0)
        block.height = Number(tall[1])
    return block
}

// Sample input: { width: 120 } on a 40x30 picture in a 500 pane answers { w: 120, h: 90, stretch: false }; { width: 70, height: 20 } answers { w: 70, h: 20, stretch: true }.
// One size rule for a lone picture and a row: a width or height attribute is honoured past the natural size, both name the box, none keeps the natural size; the pane width caps it, the ratio kept.
function pictureSize(spec, naturalW, naturalH, limit) {
    var w = spec.width > 0 ? spec.width : 0
    var h = spec.height > 0 ? spec.height : 0
    var stretch = w > 0 && h > 0
    if (w === 0 && h === 0) {
        w = naturalW
        h = naturalH
    } else if (h === 0) {
        h = naturalW > 0 ? w * naturalH / naturalW : 0
    } else if (w === 0) {
        w = naturalH > 0 ? h * naturalW / naturalH : 0
    }
    if (w > limit && w > 0) {
        h = h * limit / w
        w = limit
    }
    return { w: w, h: h, stretch: stretch }
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
// A line holding another image answers null on the spot (the block is a row the splitter draws whole), so each opener's scan stops at the next image.
function wrapperTail(lines, from, name) {
    var rest = []
    var depth = 1
    for (var j = from; j < lines.length; j++) {
        var line = lines[j].trim()
        if (line === "")
            return null
        if (SECOND_IMAGE.test(line))
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
