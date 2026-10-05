.pragma library

// MdHtmlHeading: an HTML heading inside a wrapper or opening with a picture, lifted whole so no wrapper is split and no picture sits in a text line.
.import "MdHtml.js" as MdHtml
.import "MdHtmlImage.js" as HtmlImage
.import "MdHtmlBlock.js" as HtmlBlock

// Sample input: drawn heading text '![](file:///d/logo.png)Flea' or '<img src="a.png">' holds a picture; 'Flea' and 'Wow!\[beta]' hold none.
var DRAWN_PICTURE = /<img\b|!\[(?:\\.|[^\]\\])*\]\(/i

// Sample input: ['<div align="center">', '<h1>Flea</h1>', '<p>x</p>', '</div>'] at 0 answers { head, end: 3, wrapper: ['<div align="center"><p>x</p></div>'] }; a heading with no lone wrapper before it, or a wrapper that cannot be matched, answers null.
// The heading lifts out with its own align, else the wrapper's centre; what the wrapper held after it is drawn centred as it was.
function headingUnit(lines, at) {
    var open = String(lines[at]).trim()
    if (!HtmlImage.WRAPPER_OPEN.test(open) || at + 1 >= lines.length)
        return null
    var head = HtmlBlock.htmlHeading(lines[at + 1])
    if (head === null)
        return null
    var name = MdHtml.tagHead(open).name
    var tail = HtmlImage.wrapperTail(lines, at + 2, name)
    if (tail === null)
        return null
    if (!head.aligned && HtmlImage.isCentred(open))
        head.align = "center"
    var shown = tail.rest.filter(function (line) { return line.length > 0 })
    return { head: head, end: tail.end, wrapper: shown.length === 0 ? [] : [open + shown.join("\n") + "</" + name + ">"] }
}

// Sample input: ('<div>', 0) answers 1 and ('</div>', 1) answers 0; a line with no block tag leaves the depth as it was.
// The open block HTML a run holds after a line, so a heading is judged inside open HTML by what the lines before it left open.
function nestDepth(line, depth) {
    line.replace(HtmlBlock.NESTING_TAG, function (tag, slash) {
        depth = slash === "/" ? Math.max(0, depth - 1) : depth + 1
        return tag
    })
    return depth
}

// Sample input: '<a href="https://x/"><img src="logo.png" width="120"></a><br>Flea' answers { block: the linked image, rest: 'Flea' }; text first answers null.
var HEADING_PICTURE = /^\s*(<a\b[^<>]*>)?\s*(<img\b[^<>]*>)\s*(<\/a>)?\s*(?:<br\s*\/?>\s*)*/i
// A picture opening a heading's text draws through the picture path, so it is sized and fetched there and never sits in a text line.
function headingPicture(inner, dir) {
    var parts = HEADING_PICTURE.exec(inner)
    if (parts === null || (parts[1] === undefined) !== (parts[3] === undefined))
        return null
    var block = HtmlImage.rawImage(parts[2], dir)
    if (block === null)
        return null
    if (parts[1] !== undefined && block.type === "image" && HtmlImage.linkOf(parts[1]) !== null)
        block.link = HtmlImage.linkOf(parts[1])
    return { block: block, rest: inner.slice(parts[0].length) }
}
