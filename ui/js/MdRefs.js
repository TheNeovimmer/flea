.pragma library

// MdRefs: collect references and footnotes in linear passes, returning consumed ranges for the block layer.
.import "MdInline.js" as Md
.import "MdHtml.js" as MdHtml
.import "MdContainer.js" as Container

// Sample: [pic]: image.png "Title". Collect normalized labels and multiline destinations outside code, returning {defs, dropped}.
function collectDefs(lines) {
    var defs = {}
    var dropped = []
    var i = 0
    var context = codeLines(lines)
    while (i < lines.length) {
        if (context[i].code) {
            i++
            continue
        }
        var stripped = context[i].text
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
            if (context[k].code)
                break
            var cont = context[k].text.replace(/^\s+|\s+$/g, "")
            if (cont.length === 0 || cont.charAt(0) === "[")
                break
            var next = /^(<[^>]+>|\S+)(?:\s+("[^"\n]*"|'[^'\n]*'|\([^\n)]*\)))?$/.exec(cont)
            if (next === null)
                break
            target = next[1]
            if (target.charAt(0) === "<")
                target = target.slice(1, -1)
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

// Footnote definitions `[^id]: text` over lines. Answers {notes, order, dropped}: the id-to-number table in first-use... first-definition order.
function collectFootnotes(lines) {
    var notes = {}
    var order = []
    var dropped = []
    var i = 0
    var context = codeLines(lines)
    while (i < lines.length) {
        if (context[i].code) {
            i++
            continue
        }
        var stripped = context[i].text
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
            if (/^\s{4,}\S/.test(lines[k]) && cont.length > 0) {
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

// Strip one layer of container prefix for definition DETECTION only: leading spaces, one block-quote mark, or one list marker. Structure still reads raw.
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

// Escape the opener of leftover definition-shaped lines so md4c cannot resolve definitions this parser refused.
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
            else
                depth++
        }
        i = inner.end
    }
    return i
}

// Sample: - parent followed by four-space [a]: b is an item continuation, not indented code.
function codeLines(lines) {
    var next = []
    var nonblank = null
    for (var n = lines.length - 1; n >= 0; n--) {
        next[n] = nonblank
        if (lines[n].trim().length > 0)
            nonblank = lines[n]
    }
    var state = { marker: "", length: 0, listCol: 0, quote: false, scope: "" }
    var context = []
    for (var i = 0; i < lines.length; i++) {
        var code = skipCode(lines[i], state, next[i])
        context.push({ code: code, text: state.text })
    }
    return context
}

// Sample: > ``` ends at the first unquoted line; - ``` ends when the item indentation ends.
function skipCode(line, state, next) {
    var text = String(line)
    var quoted = /^ {0,3}>/.test(text)
    if (state.scope === "quote" && !quoted)
        state.marker = ""
    if (state.quote !== quoted)
        state.listCol = 0
    state.quote = quoted
    if (quoted)
        text = text.replace(/^ {0,3}> ?/, "")
    var blank = text.trim().length === 0
    var mark = Container.readListMarker(text)
    if (state.listCol > 0) {
        var ended = blank ? !Container.blankKeepsList(next, state.listCol)
            : state.scope === "list" && !Container.continuesItem(text, state.listCol)
        if (ended) {
            if (state.scope === "list")
                state.marker = ""
            state.listCol = 0
        }
    }
    if (state.marker === "" && mark !== null) {
        state.listCol = mark.contentCol
        text = mark.text
    } else if (state.listCol > 0 && Container.continuesItem(text, state.listCol)) {
        text = text.slice(state.listCol)
    }
    state.text = text
    var marker = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(text)
    if (state.marker !== "") {
        if (marker !== null && marker[1].charAt(0) === state.marker
                && marker[1].length >= state.length && /^\s*$/.test(marker[2]))
            state.marker = ""
        return true
    }
    if (/^(?: {4}|\t)/.test(text))
        return true
    if (marker === null || (marker[1].charAt(0) === "`" && marker[2].indexOf("`") >= 0))
        return false
    state.marker = marker[1].charAt(0)
    state.length = marker[1].length
    state.scope = quoted ? "quote" : state.listCol > 0 ? "list" : "document"
    return true
}
