.pragma library

// MdParagraphs: cut one run's lines into paragraphs; a blank ends the paragraph unless HTML spans it.
.import "MdHtml.js" as MdHtml

// Tags that never pair across a blank line: void elements carry no content, so an unclosed one never joins paragraphs.
var VOID_TAGS = { area: 1, base: 1, br: 1, col: 1, hr: 1, img: 1, link: 1, meta: 1, source: 1, track: 1, wbr: 1 }

// Sample input: ["a", "", "b"] cuts after the blank; ["<div>", "", "x"] never cuts inside the open tag.
// One forward pass, so hostile input stays linear: tag depth and comments ride along, and a later paragraph never rescans an earlier one.
function cutAfter(lines) {
    var cut = []
    for (var i = 0; i < lines.length; i++)
        cut.push(false)
    var laterText = []
    var seen = false
    for (var w = lines.length - 1; w >= 0; w--) {
        laterText[w] = seen
        if (lines[w].trim().length > 0)
            seen = true
    }
    var depth = 0
    var comment = false
    // An unterminated tag may complete on a later line; past readTag's own cap it never classifies, so it is dropped.
    var carry = ""
    var hasText = false
    for (var l = 0; l < lines.length; l++) {
        var line = lines[l]
        if (line.trim().length === 0) {
            if (hasText && laterText[l] && depth === 0 && !comment) {
                cut[l] = true
                hasText = false
                depth = 0
                comment = false
                carry = ""
            }
            continue
        }
        hasText = true
        var text = carry + line
        carry = ""
        var at = 0
        while (at < text.length) {
            if (comment) {
                var end = text.indexOf("-->", at)
                if (end < 0)
                    break
                comment = false
                at = end + 3
                continue
            }
            var tag = text.indexOf("<", at)
            if (tag < 0)
                break
            if (text.slice(tag, tag + 4) === "<!--") {
                comment = true
                at = tag + 4
                continue
            }
            var found = MdHtml.readTag(text, tag, null)
            if (found === null) {
                at = tag + 1
                continue
            }
            var head = MdHtml.tagHead(found.tag)
            if (head.name !== "" && !VOID_TAGS.hasOwnProperty(head.name)) {
                if (head.closing) {
                    if (depth > 0)
                        depth--
                } else if (!head.selfClose)
                    depth++
            }
            at = found.end
        }
        var lastLt = text.lastIndexOf("<")
        if (lastLt > text.lastIndexOf(">") && text.length - lastLt <= MdHtml.MAX_TAG_LENGTH)
            carry = text.slice(lastLt)
    }
    return cut
}
