.pragma library

var FENCE_OPEN = /^ {0,3}(`{3,}|~{3,})(.*)$/
var FENCE_CLOSE = /^ {0,3}(`+|~+)[ \t]*$/
var QUOTE_MARK = /^ {0,3}> ?/
// Sample input: "  - ```js" answers ["  - ", ...]; the marker and its spaces are the width the item's lines must keep.
var ITEM_MARKER = /^( *(?:[-*+]|\d{1,9}[.)]) +)(?=\S)/
// Sample input: "- - -", "* * *" and "  ___" are thematic breaks, which outrank a list item marker.
var THEMATIC_BREAK = /^ {0,3}([-*_])(?: *\1){2,} *$/
// Sample input: "# h", "---" and "***" are blocks that end a paragraph and are not text of one.
var HEADING_OR_RULE = /^ {0,3}(?:#{1,6}(?: |$)|([-*_])(?: *\1){2,} *$)/

// Sample input: "b" and "  text" are lazy continuation text; "- b", "```" and "# h" start a block of their own.
function startsBlock(rest) {
    return ITEM_MARKER.test(rest) || FENCE_OPEN.test(rest) || HEADING_OR_RULE.test(rest)
}

// Sample input: "> - ```" answers { quotes: 1, rest: "- ```" }; a line in no quote answers quotes 0 and the line itself.
function stripQuotes(line) {
    var quotes = 0
    var rest = line
    while (QUOTE_MARK.test(rest)) {
        rest = rest.replace(QUOTE_MARK, "")
        quotes++
    }
    return { quotes: quotes, rest: rest }
}

// Sample input: "> a" kept in 1 quote with indent 0 answers "a"; "b" answers null, the quote ended; "  c" with indent 2 answers "c"; a blank line stays inside.
function insideContainer(line, quotes, indent) {
    var inner = stripQuotes(line)
    if (inner.quotes < quotes)
        return null
    if (indent === 0)
        return inner.rest
    if (inner.rest.trim().length === 0)
        return ""
    var lead = /^ */.exec(inner.rest)[0].length
    return lead < indent ? null : inner.rest.slice(indent)
}

// Sample input: a line "- ```" over an empty stack answers { quotes: 0, indent: 2, rest: "```" } and pushes the item; "  ```" under it answers the same.
// An item whose last block is an open paragraph (para) keeps a dedented line of paragraph text, as CommonMark's lazy continuation does.
function openerOf(line, items) {
    var inner = stripQuotes(line)
    var rest = inner.rest
    var blank = rest.trim().length === 0
    var top = items.length > 0 ? items[items.length - 1] : null
    if (!blank) {
        var lead = /^ */.exec(rest)[0].length
        var lazy = top !== null && top.para && top.quotes === inner.quotes && !startsBlock(rest)
        while (!lazy && items.length > 0 && (items[items.length - 1].quotes > inner.quotes || (items[items.length - 1].quotes === inner.quotes && lead < items[items.length - 1].indent)))
            items.pop()
        top = items.length > 0 ? items[items.length - 1] : null
    } else if (top !== null) {
        top.para = false
    }
    var local = top !== null && top.quotes === inner.quotes && !blank && lead >= top.indent ? rest.slice(top.indent) : rest
    var marker = THEMATIC_BREAK.test(local) ? null : ITEM_MARKER.exec(rest)
    if (marker !== null) {
        items.push({ quotes: inner.quotes, indent: marker[1].length, para: !HEADING_OR_RULE.test(rest.slice(marker[1].length)) })
        return { quotes: inner.quotes, indent: marker[1].length, rest: rest.slice(marker[1].length) }
    }
    if (top !== null && !blank)
        top.para = !HEADING_OR_RULE.test(rest)
    if (top !== null && top.quotes === inner.quotes && /^ */.exec(rest)[0].length >= top.indent)
        return { quotes: inner.quotes, indent: top.indent, rest: rest.slice(top.indent) }
    return { quotes: inner.quotes, indent: 0, rest: rest }
}

// Sample input: "a\n```js\n![x](u)\n```\nb" answers "a\n\nb", a fence being one empty line; "```a`b" opens none; a fence ends with its quote or item.
function withoutFences(text) {
    var lines = String(text).split("\n")
    var out = []
    var items = []
    for (var i = 0; i < lines.length; i++) {
        var box = openerOf(lines[i], items)
        var open = FENCE_OPEN.exec(box.rest)
        // A backtick fence's info string holds no backtick, or the line is prose with a code span.
        if (open === null || (open[1].charAt(0) === "`" && open[2].indexOf("`") >= 0)) {
            out.push(lines[i])
            continue
        }
        var close = i + 1
        while (close < lines.length) {
            var inner = insideContainer(lines[close], box.quotes, box.indent)
            if (inner === null)
                break
            var hit = FENCE_CLOSE.exec(inner)
            if (hit !== null && hit[1].charAt(0) === open[1].charAt(0) && hit[1].length >= open[1].length)
                break
            close++
        }
        out.push("")
        if (items.length > 0)
            items[items.length - 1].para = false
        // A closing fence belongs to the fence; a line that left the container is read again as ordinary text.
        i = close < lines.length && insideContainer(lines[close], box.quotes, box.indent) === null ? close - 1 : close
    }
    return out.join("\n")
}
