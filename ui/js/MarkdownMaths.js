.pragma library

// MarkdownMaths: an inline formula's SVG as a picture inside a line of Qt rich text, and the code span it replaces.
var SPAN = /<code data-math="inline"[^>]*>[\s\S]*?<\/code>/g
var ROOT = /<svg\b[^>]*>/
// Marks encodeURIComponent leaves bare that break an attribute or a Markdown destination, so they are percent-encoded too.
var URL_MARKS = /[()'!*~]/g
var HEX_RADIX = 16
// A transparent 1 by 1 PNG, and the height a calibration picture of it is laid out at.
var CLEAR = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
var CALIBRATION_HEIGHT = 100

// Sample input: 'a <code data-math="inline" style="background-color:#222">x&#94;2</code> b' holds one span.
function spans(html) {
    return String(html).match(SPAN) || []
}

// Sample input: ('a <code data-math="inline">x</code> b', ['<img src="p">']) answers 'a <img src="p"> b'; an empty picture keeps its code span.
function compose(html, pictures) {
    var at = 0
    return String(html).replace(SPAN, function (span) {
        var picture = pictures[at++]
        return picture !== undefined && picture !== "" ? picture : span
    })
}

function attr(root, name) {
    var m = new RegExp("\\s" + name + "=\"([^\"]*)\"").exec(root)
    return m === null ? null : m[1]
}

function percent(c) {
    return "%" + c.charCodeAt(0).toString(HEX_RADIX).toUpperCase()
}

// Sample input: svg '<svg width="30px" height="20px" viewBox="0 -15 60 20">' answers an <img> that sits that formula's baseline on the text's, or "" when the root carries no size or svg is "".
// anchor is how far above the baseline Qt centres a middle-aligned picture in this font; a picture shorter than minTall is padded to it, since a short one is placed otherwise.
function picture(svg, anchor, minTall) {
    var root = ROOT.exec(svg)
    if (root === null)
        return ""
    var width = parseFloat(attr(root[0], "width"))
    var height = parseFloat(attr(root[0], "height"))
    var box = (attr(root[0], "viewBox") || "").trim().split(/\s+/).map(Number)
    if (!(width > 0) || !(height > 0) || box.length !== 4 || box.some(isNaN) || !(box[3] > 0))
        return ""
    var unit = height / box[3]
    var above = -box[1] * unit
    var below = (box[1] + box[3]) * unit
    var tall = Math.ceil(Math.max(2 * Math.max(above - anchor, below + anchor, 0), minTall))
    // The formula's baseline sits at the picture's centre plus the anchor, whatever its depth.
    var top = tall / 2 + anchor
    var padded = svg.replace(ROOT, root[0]
        .replace(/\sheight="[^"]*"/, " height=\"" + tall + "px\"")
        .replace(/\sviewBox="[^"]*"/, " viewBox=\"" + box[0] + " " + (-top / unit) + " " + box[2] + " " + (tall / unit) + "\""))
    var url = "data:image/svg+xml," + encodeURIComponent(padded).replace(URL_MARKS, percent)
    return "<img src=\"" + url + "\" width=\"" + width + "\" height=\"" + tall + "\" style=\"vertical-align: middle\" />"
}
