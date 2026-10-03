.pragma library

// Parse one definition's text; MdBlocks alone decides where definitions are allowed.
.import "MdInline.js" as Md
.import "MdHtml.js" as MdHtml

// Sample: [pic]: image.png "Title"; an empty destination can continue on the next container line.
function readDefinition(line) {
    var match = /^ {0,3}\[([^\]\n]+)\]:\s*(.*)$/.exec(line)
    if (match === null || match[1].charAt(0) === "^")
        return null
    var rest = match[2].trim()
    var target = rest.length === 0 ? "" : readDefinitionTarget(rest)
    if (rest.length > 0 && target === "")
        return null
    return { key: Md.normalizeLabel(match[1]), target: target }
}

// Sample: <my pic.png> "Title" or pic.png, with no unquoted spaces in a bare destination.
function readDefinitionTarget(text) {
    var match = /^(<[^>\n]+>|[^<\s]\S*)(?:\s+("[^"\n]*"|'[^'\n]*'|\([^\n)]*\)))?$/.exec(text)
    if (match === null)
        return ""
    var target = match[1]
    return target.charAt(0) === "<" ? target.slice(1, -1) : target
}

// Sample: [^id]: note body; the block reader supplies any indented continuation lines.
function readFootnoteDefinition(line) {
    var match = /^ {0,3}\[\^([^\]\n]+)\]:\s*(.*)$/.exec(line)
    return match === null ? null : { id: match[1], text: match[2] }
}

// Escape a definition-shaped leaf refused by the block reader before handing it to md4c.
function killDefinition(line) {
    if (!/^ {0,3}\[(?:\\.|[^\]\\\n])+\]:/.test(line))
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
