.pragma library

// MdRefs: reference collection for rendered Markdown. Definitions (including
// multi-line ones and ones inside containers) and footnote definitions are
// gathered in one linear pass each, with the consumed line ranges so the block
// layer drops them before md4c ever reads the document.
.import "MdInline.js" as Md
.import "MdHtml.js" as MdHtml

// Link reference definitions over lines: multi-line targets, container
// prefixes stripped for detection, labels normalised by case fold and
// whitespace collapse. Answers {defs, dropped}: the table plus the line
// ranges consumed, so the block layer can drop them before md4c ever reads
// the document. One pass, each line visited once.
function collectDefs(lines) {
    var defs = {}
    var dropped = []
    var i = 0
    while (i < lines.length) {
        var stripped = stripContainerPrefix(lines[i]).text
        var m = /^ {0,3}\[([^\]\n]+)\]:/.exec(stripped)
        if (m === null) {
            i++
            continue
        }
        var key = Md.normalizeLabel(m[1])
        var rest = stripped.slice(m[0].length).replace(/^\s+/, "")
        var target = ""
        var last = i
        if (rest.length > 0) {
            target = rest.split(/\s/)[0]
            if (target.charAt(0) === "<") {
                var close = rest.indexOf(">")
                target = close > 0 ? rest.slice(1, close) : rest
            }
        }
        var k = i + 1
        while (target === "" && k < lines.length) {
            var cont = stripContainerPrefix(lines[k]).text.replace(/^\s+|\s+$/g, "")
            if (cont.length === 0 || cont.charAt(0) === "[")
                break
            target = cont.split(/\s/)[0]
            last = k
            k++
        }
        if (target !== "") {
            defs[key] = target
            dropped.push([i, last])
        }
        i = last + 1
    }
    return { defs: defs, dropped: dropped }
}

// Footnote definitions `[^id]: text` over lines. Answers {notes, order,
// dropped}: the id-to-number table in first-use... first-definition order.
function collectFootnotes(lines) {
    var notes = {}
    var order = []
    var dropped = []
    var i = 0
    while (i < lines.length) {
        var stripped = stripContainerPrefix(lines[i]).text
        var m = /^ {0,3}\[\^([^\]\n]+)\]:\s*(.*)$/.exec(stripped)
        if (m === null) {
            i++
            continue
        }
        var id = m[1]
        var text = m[2]
        var last = i
        var k = i + 1
        while (k < lines.length) {
            var cont = stripContainerPrefix(lines[k]).text
            if (/^\s{4,}\S/.test(lines[k].slice(0, 8)) && cont.length > 0) {
                text += "\n" + cont.replace(/^\s+/, "")
                last = k
                k++
                continue
            }
            break
        }
        if (!notes.hasOwnProperty(id)) {
            notes[id] = { n: order.length + 1, text: text }
            order.push(id)
        }
        dropped.push([i, last])
        i = last + 1
    }
    var numbers = {}
    for (var q = 0; q < order.length; q++)
        numbers[order[q]] = notes[order[q]].n
    return { notes: notes, order: order, numbers: numbers, dropped: dropped }
}

// Strip one layer of container prefix for definition DETECTION only: leading
// spaces, one block-quote mark, or one list marker. Structure still reads raw.
function stripContainerPrefix(line) {
    var text = String(line)
    var cut = 0
    while (cut < text.length && text.charAt(cut) === " " && cut < 4)
        cut++
    var body = text.slice(cut)
    if (body.charAt(0) === ">")
        body = body.charAt(1) === " " ? body.slice(2) : body.slice(1)
    else {
        var lm = /^(\d+[.)]|[-*+])\s+/.exec(body)
        if (lm !== null)
            body = body.slice(lm[0].length)
    }
    return { text: body }
}

// Escape the "[" of a leftover definition-shaped line, so md4c never sees a
// reference this parser did not resolve. Only a line that can BE a definition
// (a label plus its colon) loses its bracket; ordinary [text] lines keep
// theirs, and "\[foo]" renders as "[foo]".
function killDefinition(line) {
    var prefix = stripContainerPrefix(line).text
    if (!/^ {0,3}\[(?:\\.|[^\]\\\n])+\]:/.test(prefix))
        return line
    var i = line.indexOf("[")
    return line.slice(0, i) + "\\[" + line.slice(i + 1)
}

function readFootnoteRef(text, i) {
    var j = i + 2
    while (j < text.length && text.charAt(j) !== "]" && text.charAt(j) !== "\n")
        j++
    if (j >= text.length || text.charAt(j) !== "]" || j === i + 2)
        return null
    return { id: text.slice(i + 2, j), end: j + 1 }
}


// Skip a DROP_CONTENT element's body to its matching close, same-name nesting
// counted. Linear: every character is skipped once, sharing the caller's dead
// tag flag so a close-less run of "<" pays one native scan total.
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
            else
                depth++
        }
        i = inner.end
    }
    return i
}
