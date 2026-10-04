.pragma library

// Parse one definition's text; MdBlocks alone decides where definitions are allowed.
.import "MdInline.js" as Md
.import "MdLink.js" as Link
.import "MdHtml.js" as MdHtml
.import "MdContainer.js" as Container

var hasOwn = Object.prototype.hasOwnProperty

// Sample: [pic]: image.png "Title"; an empty destination can continue on the next container line.
function readDefinition(line) {
    var match = /^ {0,3}\[((?:\\.|[^\[\]\\\n])+)\]:\s*(.*)$/.exec(line)
    if (match === null || match[1].charAt(0) === "^")
        return null
    var rest = match[2].trim()
    var parts = rest.length === 0 ? { target: "", titled: false } : readDefinitionParts(rest)
    if (rest.length > 0 && parts.target === "")
        return null
    return { key: Link.normalizeLabel(match[1]), target: parts.target, titled: parts.titled }
}

// Sample: <my pic.png> "Title" or pic.png, with no unquoted spaces in a bare destination; answers { target, titled }.
function readDefinitionParts(text) {
    var match = /^(<[^>\n]+>|[^<\s]\S*)(?:\s+("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|\((?:\\.|[^()\\\n])*\)))?$/.exec(text)
    if (match === null)
        return { target: "", titled: false }
    var target = match[1]
    return { target: target.charAt(0) === "<" ? target.slice(1, -1) : target, titled: match[2] !== undefined }
}

function readDefinitionTarget(text) {
    return readDefinitionParts(text).target
}

var LABEL_MAX_LENGTH = 999
var MAX_INDENT = 3
var TITLE_CLOSER = { '"': '"', "'": "'", "(": ")" }

// Sample input: "\n  x" read from 0 answers { at: 4, newline: true }; spaces, tabs and at most one line ending are skipped.
function skipGap(text, from) {
    var at = from
    var newline = false
    while (at < text.length && (text.charAt(at) === " " || text.charAt(at) === "\t" || (!newline && text.charAt(at) === "\n"))) {
        newline = newline || text.charAt(at) === "\n"
        at++
    }
    return { at: at, newline: newline }
}

// Sample input: "[a\nb]" read from 0 answers { label: "a\nb", end: 5 }, the index after "]"; an inner "[" answers null.
function readLabel(text, from) {
    if (text.charAt(from) !== "[")
        return null
    var at = from + 1
    while (at < text.length && at - from <= LABEL_MAX_LENGTH && text.charAt(at) !== "]") {
        if (text.charAt(at) === "[")
            return null
        at += text.charAt(at) === "\\" ? 2 : 1
    }
    return text.charAt(at) === "]" && at - from <= LABEL_MAX_LENGTH ? { label: text.slice(from + 1, at), end: at + 1 } : null
}

// Sample input: '<a b> "t"' read from 0 answers { target: "a b", end: 5 }; "/u x" answers { target: "/u", end: 2 }; "<a" answers null.
function readDestinationAt(text, from) {
    var at = from
    if (text.charAt(at) === "<") {
        for (at++; at < text.length && text.charAt(at) !== ">"; at++) {
            if (text.charAt(at) === "<" || text.charAt(at) === "\n")
                return null
            at += text.charAt(at) === "\\" ? 1 : 0
        }
        return text.charAt(at) === ">" ? { target: text.slice(from + 1, at), end: at + 1 } : null
    }
    var depth = 0
    while (at < text.length && !/[\s\x00-\x1f]/.test(text.charAt(at))) {
        var c = text.charAt(at)
        depth += c === "(" ? 1 : c === ")" ? -1 : 0
        at += c === "\\" && at + 1 < text.length && !/\s/.test(text.charAt(at + 1)) ? 2 : 1
    }
    return at > from && depth === 0 ? { target: text.slice(from, at), end: at } : null
}

// Sample input: `"a\nb" x` read from 0 answers 6, the index after the closing quote; a title needs its closer, and "(" titles hold no "(".
function readTitleEnd(text, from) {
    var opener = text.charAt(from)
    var closer = TITLE_CLOSER.hasOwnProperty(opener) ? TITLE_CLOSER[opener] : ""
    for (var at = from + 1; closer !== "" && at < text.length; at++) {
        var c = text.charAt(at)
        if (c === closer)
            return at + 1
        if (opener === "(" && c === "(")
            return -1
        at += c === "\\" && text.charAt(at + 1) !== "\n" ? 1 : 0
    }
    return -1
}

// Sample input: "a  \nb" at 1 answers true, only blanks remain on the line; "a b" at 1 answers false.
function endsLine(text, from) {
    var at = from
    while (text.charAt(at) === " " || text.charAt(at) === "\t")
        at++
    return at >= text.length || text.charAt(at) === "\n"
}

// Sample input: lines "[Foo\n  bar]: /url\n'a\nb'" answer { key: "foo bar", titled: true, end: 3 }; "[a]: /u x" answers null.
function definitionAt(lines, from) {
    var stop = from + 1
    while (stop < lines.length && lines[stop].trim().length > 0 && !Container.startsBlock(lines[stop]))
        stop++
    var text = lines.slice(from, stop).join("\n")
    var indent = 0
    while (indent < MAX_INDENT && text.charAt(indent) === " ")
        indent++
    var label = readLabel(text, indent)
    if (label === null || label.label.trim().length === 0 || label.label.charAt(0) === "^" || text.charAt(label.end) !== ":")
        return null
    var lead = skipGap(text, label.end + 1)
    var dest = readDestinationAt(text, lead.at)
    if (dest === null)
        return null
    var end = dest.end
    var gap = skipGap(text, end)
    var close = gap.at > end ? readTitleEnd(text, gap.at) : -1
    var titled = close >= 0 && endsLine(text, close)
    // A title that does not close its own line is dropped when it sits on the next line, and spoils the definition when it follows the destination.
    if (!titled && !endsLine(text, end))
        return null
    return { key: Link.normalizeLabel(label.label), target: dest.target, titled: titled,
        end: from + text.slice(0, titled ? close : end).split("\n").length - 1 }
}

// Sample input: lines "'a" over "b'" answer 1, the line that closes the title; "'open" with no closer, or junk after it, answers -1.
function titleEnd(lines, at) {
    var open = at < lines.length ? lines[at].trim().charAt(0) : ""
    if (open !== "\"" && open !== "'" && open !== "(")
        return -1
    var close = open === "(" ? ")" : open
    for (var k = at; k < lines.length && lines[k].trim().length > 0; k++) {
        var text = lines[k]
        for (var c = k === at ? text.indexOf(open) + 1 : 0; c < text.length; c++) {
            if (text.charAt(c) === "\\")
                c++
            else if (text.charAt(c) === close)
                return text.slice(c + 1).trim().length === 0 ? k : -1
        }
    }
    return -1
}

// The first definition of a label wins.
function storeDefinition(defs, key, target) {
    if (!hasOwn.call(defs, key))
        defs[key] = target
}

// A title on the lines after a finished definition belongs to it: its lines hide with the definition; allowed says the definition has none yet.
function hideTitle(lines, from, state, allowed) {
    var end = allowed ? titleEnd(lines, from) : -1
    if (end < 0)
        return
    for (var k = from; k <= end; k++)
        state.hidden[k] = true
    state.dropped.push([from, end])
}

// Sample: [^id]: note body; the block reader supplies any indented continuation lines.
function readFootnoteDefinition(line) {
    var match = /^ {0,3}\[\^([^\]\n]+)\]:\s*(.*)$/.exec(line)
    return match === null ? null : { id: match[1], text: match[2] }
}

// Escape a definition-shaped leaf refused by the block reader before handing it to md4c.
function killDefinition(line) {
    if (!/^ {0,3}\[(?:\\.|[^\[\]\\\n])+\]:/.test(line))
        return line
    var at = line.indexOf("[")
    return line.slice(0, at) + "\\[" + line.slice(at + 1)
}

// Sample input: "[^note]" at its "[" yields id "note" and the index after "]".
function readFootnoteRef(text, i) {
    var j = i + 2
    while (j < text.length && text.charAt(j) !== "]" && text.charAt(j) !== "\n")
        j++
    if (j >= text.length || text.charAt(j) !== "]" || j === i + 2)
        return null
    return { id: text.slice(i + 2, j), end: j + 1 }
}


// Skip DROP_CONTENT bodies with same-name nesting; share the dead-tag flag to keep unmatched runs linear.
function skipDropContent(body, i, name, dead) {
    var depth = 1
    while (i < body.length && depth > 0) {
        var o = body.indexOf("<", i)
        if (o < 0)
            return body.length
        var inner = MdHtml.readTag(body, o, dead)
        if (inner === null) {
            i = o + 1
            continue
        }
        var head = MdHtml.tagHead(inner.tag)
        if (head.name === name) {
            if (head.closing)
                depth--
            else if (!head.selfClose)
                depth++
        }
        i = inner.end
    }
    return i
}

// Sample input: lines 2 to 3 hide both and record the span as dropped, so no line of the definition reaches the renderer.
function hideDefinition(state, from, to) {
    for (var i = from; i <= to; i++)
        state.hidden[i] = true
    state.dropped.push([from, to])
}
