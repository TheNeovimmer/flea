.pragma library

// Parse one definition's text; MdBlocks alone decides where definitions are allowed.
.import "MdInline.js" as Md
.import "MdHtml.js" as MdHtml

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
    return { key: Md.normalizeLabel(match[1]), target: parts.target, titled: parts.titled }
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
