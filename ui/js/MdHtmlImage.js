.pragma library

// MdHtmlImage: a raw HTML image on its own line, alone or inside a centring paragraph, as an image block.
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml

// A width attribute draws at most this wide, whatever the file or the pane.
var MAX_IMAGE_WIDTH = 4096
// Sample input: '<p align="center"><img src="a.png"></p>' splits into the wrapper, the image and the closer.
var IMAGE_LINE = /^(<(?:p|div)\b[^<>]*>)?\s*(<img\b[^<>]*>)\s*(<\/(?:p|div)>)?$/i
var WRAPPER_OPEN = /^<(?:p|div)\b[^<>]*>$/i
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
        block.width = Math.min(Number(sized[1]), MAX_IMAGE_WIDTH)
    return block
}

// Sample input: lines ['<p align="center">', '  <img src="a.png">', '</p>'] at 0 answers { block, end: 2 }; a line that is no image unit answers null.
function imageUnit(lines, at, dir) {
    var first = IMAGE_LINE.exec(lines[at].trim())
    var open = null
    var last = at
    var image = null
    if (first !== null && first[1] !== undefined) {
        open = first[1]
        image = first[2]
    } else if (first === null && WRAPPER_OPEN.test(lines[at].trim()) && at + 1 < lines.length) {
        var inner = IMAGE_LINE.exec(lines[at + 1].trim())
        if (inner === null || inner[1] !== undefined)
            return null
        open = lines[at].trim()
        image = inner[2]
        last = at + 1
        if (inner[3] === undefined) {
            if (at + 2 >= lines.length || !/^<\/(?:p|div)>$/i.test(lines[at + 2].trim()))
                return null
            last = at + 2
        }
    } else {
        return null
    }
    var block = rawImage(image, dir)
    if (block === null)
        return null
    if (isCentred(open))
        block.align = "center"
    return { block: block, end: last }
}
