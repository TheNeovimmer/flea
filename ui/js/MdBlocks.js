.pragma library

// The same streaming block pass collects definitions and renders with the resulting complete map.
.import "MdLeaf.js" as Leaf
.import "MdRefs.js" as Refs
.import "MdContainer.js" as Container
.import "MdDocument.js" as Document
.import "MdHtml.js" as Html

var CODE_INDENT = 4
var MIN_RULE_MARKS = 3
var MAX_RULE_INDENT = 3

function listMarker(line) {
    var mark = Container.readListMarker(line)
    if (mark !== null)
        mark.text = Leaf.taskText(mark.text)
    return mark
}

// Sample: "> - - -" has one thematic suffix; cache it before opening any nested containers.
function ruleSuffix(line) {
    var at = line.length - 1
    while (at >= 0 && (line.charAt(at) === " " || line.charAt(at) === "\t"))
        at--
    var tick = line.charAt(at)
    var count = 0
    if (tick !== "-" && tick !== "*" && tick !== "_")
        return { start: line.length, count: count }
    while (at >= 0 && (line.charAt(at) === tick || line.charAt(at) === " " || line.charAt(at) === "\t")) {
        if (line.charAt(at) === tick)
            count++
        at--
    }
    return { start: at + 1, count: count }
}

function referenceState() {
    return { defs: {}, notes: {}, order: [], numbers: {}, hidden: {}, escaped: {}, code: {}, dropped: [] }
}

function hideDefinition(state, from, to) {
    for (var i = from; i <= to; i++)
        state.hidden[i] = true
    state.dropped.push([from, to])
}

// Sample: "- > ```\n  > [id]: literal\n  > ```" matches an item, then a quote, before its fence.
function blockPass(lines, state, emit, collect) {
    var frames = []
    var leaf = null
    var pending = null
    var serial = 0
    var lastQuote = -1
    function send(kind, index, text, top, display, info) {
        if (emit !== undefined)
            emit({ type: "line", kind: kind, index: index, text: text,
                outer: top, display: display, info: info || "" })
    }
    function finishNote() {
        if (pending !== null && pending.note !== undefined)
            pending.note.text = pending.body.join("\n")
        pending = null
    }
    for (var i = 0; i < lines.length; i++) {
        var raw = lines[i]
        var view = { at: 0, padding: 0, column: 0 }
        var rawBlank = raw.trim().length === 0
        var matched = 0
        var display = raw
        var rule = ruleSuffix(raw)
        var previousTop = frames.length > 0 ? frames[0] : null
        for (; matched < frames.length; matched++) {
            var frame = frames[matched]
            if (frame.type === "quote") {
                var quote = Container.quoteAt(raw, view)
                if (quote < 0)
                    break
                Container.takeQuote(raw, view, quote)
            } else {
                var indent = Container.indentationAt(raw, view, frame.contentCol).width
                if (indent >= frame.contentCol) {
                    Container.takeIndent(raw, view, frame.contentCol)
                } else if (rawBlank || raw.slice(view.at).trim().length === 0) {
                    if (matched > lastQuote) {
                        matched = frames.length
                        break
                    }
                } else {
                    break
                }
            }
            if (matched === 0)
                display = Container.textAt(raw, view)
        }
        var unmatchedText = Container.textAt(raw, view)
        var startsQuote = Container.quoteAt(raw, view) >= 0
        var startsList = Container.listAt(raw, view)
        var startsFence = Leaf.fenceOpen(unmatchedText)
        var thematic = Leaf.isThematic(unmatchedText)
        var setext = leaf !== null && leaf.kind === "paragraph" && matched === frames.length && Leaf.isSetext(unmatchedText)
        var lazy = leaf !== null && leaf.kind === "paragraph" && unmatchedText.trim().length > 0
            && !startsQuote && startsList === null && startsFence === null && !thematic
            && !/^ {0,3}#{1,6}(?:\s|$)/.test(unmatchedText)
        if (matched < frames.length && !lazy) {
            frames.length = matched
            lastQuote = -1
            for (var q = 0; q < frames.length; q++) {
                if (frames[q].type === "quote")
                    lastQuote = q
            }
            leaf = null
        }
        var owner = frames.length > 0 ? frames[frames.length - 1].id : 0
        var fenced = leaf !== null && leaf.kind === "fence" && leaf.owner === owner
        if (!fenced && !lazy && !setext) {
            while (true) {
                var quoteIndent = Container.quoteAt(raw, view)
                var marker = quoteIndent < 0 ? Container.listAt(raw, view) : null
                var ruleHere = rule.count >= MIN_RULE_MARKS && view.at >= rule.start
                    && marker !== null && marker.indent <= MAX_RULE_INDENT
                if (quoteIndent < 0 && (marker === null || thematic || ruleHere))
                    break
                var next = { id: ++serial, type: quoteIndent >= 0 ? "quote" : "list" }
                if (quoteIndent >= 0) {
                    Container.takeQuote(raw, view, quoteIndent)
                    lastQuote = frames.length
                } else {
                    next.contentCol = marker.contentCol
                    next.ordered = marker.ordered
                    next.start = marker.start
                    next.group = frames.length === 0 && previousTop !== null
                        && previousTop.type === "list" && previousTop.ordered === marker.ordered
                        ? previousTop.group : next.id
                    Container.takeList(raw, view, marker)
                }
                frames.push(next)
                owner = next.id
                leaf = null
                if (frames.length === 1)
                    display = Container.textAt(raw, view)
            }
        }
        var top = frames.length > 0 ? frames[0] : null
        var text = Container.textAt(raw, view)
        if (fenced) {
            var closer = Leaf.fenceOpen(text)
            var closed = closer !== null && closer.info === "" && closer.tick === leaf.tick && closer.len >= leaf.len
            state.code[i] = true
            send(closed ? "fenceClose" : "fenceBody", i, text, top, display)
            if (closed)
                leaf = null
            continue
        }
        if (pending !== null) {
            if (collect && pending.owner === owner && pending.note !== undefined
                    && Container.indentationAt(raw, view).width >= CODE_INDENT) {
                pending.body.push(text.replace(/^\s+/, ""))
                hideDefinition(state, i, i)
                send("hidden", i, text, top, display)
                continue
            }
            if (collect && pending.owner === owner && pending.ref !== undefined
                    && Container.indentationAt(raw, view).width < CODE_INDENT && Leaf.fenceOpen(text) === null) {
                // Sample: '[cover].png "Title"' accepts a destination only when the complete line parses.
                var destination = Refs.readDefinitionTarget(text.trim())
                if (destination !== "") {
                    if (!state.defs.hasOwnProperty(pending.ref.key))
                        state.defs[pending.ref.key] = destination
                    hideDefinition(state, pending.index, i)
                    // Replay the opener's paragraph state so its lazy destination keeps the same containers.
                    state.hidden[pending.index] = "paragraph"
                    pending = null
                    leaf = null
                    send("hidden", i, text, top, display)
                    continue
                }
            }
            finishNote()
        }
        if (state.hidden.hasOwnProperty(i)) {
            leaf = state.hidden[i] === "paragraph" ? { kind: "paragraph", owner: owner } : null
            send("hidden", i, text, top, display)
            continue
        }
        if (i === 0 && raw === "---") {
            var front = i + 1
            while (front < lines.length && lines[front] !== "---" && lines[front] !== "...")
                front++
            if (front < lines.length) {
                send("fenceOpen", i, "", null, raw)
                state.code[i] = true
                for (i++; i < front; i++) {
                    send("fenceBody", i, lines[i], null, lines[i])
                    state.code[i] = true
                }
                send("fenceClose", i, "", null, lines[i])
                state.code[i] = true
                leaf = null
                continue
            }
        }
        var open = Leaf.fenceOpen(text)
        if (open !== null) {
            leaf = { kind: "fence", owner: owner, tick: open.tick, len: open.len }
            state.code[i] = true
            send("fenceOpen", i, text, top, display, open.info)
            continue
        }
        var blank = text.trim().length === 0
        var width = Container.indentationAt(raw, view).width
        if (leaf !== null && leaf.kind === "code" && (blank || width >= CODE_INDENT)) {
            state.code[i] = true
            Container.takeIndent(raw, view, CODE_INDENT)
            send("codeLine", i, blank ? "" : Container.textAt(raw, view), top, display)
            continue
        }
        if (leaf !== null && leaf.kind === "code") {
            send("codeEnd", i, "", top, display)
            leaf = null
        }
        if ((leaf === null || leaf.kind !== "paragraph") && !blank && width >= CODE_INDENT) {
            leaf = { kind: "code", owner: owner }
            state.code[i] = true
            Container.takeIndent(raw, view, CODE_INDENT)
            send("codeLine", i, Container.textAt(raw, view), top, display)
            continue
        }
        if (collect && leaf === null && !blank) {
            var note = Refs.readFootnoteDefinition(text)
            var ref = note === null ? Refs.readDefinition(text) : null
            if (note !== null) {
                var number = state.order.length + 1
                var stored = state.notes.hasOwnProperty(note.id) ? null : { n: number, text: note.text }
                if (stored !== null) {
                    state.notes[note.id] = stored
                    state.numbers[note.id] = number
                    state.order.push(note.id)
                }
                pending = { owner: owner, note: stored || {}, body: [note.text] }
                hideDefinition(state, i, i)
                send("hidden", i, text, top, display)
                continue
            }
            if (ref !== null) {
                if (ref.target !== "") {
                    if (!state.defs.hasOwnProperty(ref.key))
                        state.defs[ref.key] = ref.target
                    hideDefinition(state, i, i)
                    send("hidden", i, text, top, display)
                    continue
                }
                pending = { owner: owner, ref: ref, index: i }
            }
        }
        var aligns = top === null && text.indexOf("|") >= 0 && i + 1 < lines.length
            ? Leaf.delimAligns(lines[i + 1]) : null
        if (aligns !== null) {
            var header = Leaf.splitRow(text)
            var rows = []
            i += 2
            while (i < lines.length && lines[i].trim().length > 0 && lines[i].indexOf("|") >= 0)
                rows.push(Leaf.splitRow(lines[i++]))
            if (emit !== undefined)
                emit(Leaf.tableBlock(header, aligns, rows))
            i--
            leaf = null
            continue
        }
        if (Refs.killDefinition(text) !== text)
            state.escaped[i] = true
        send("run", i, text, top, display)
        leaf = blank || setext || Leaf.isThematic(text) || /^ {0,3}#{1,6}(?:\s|$)/.test(text) ? null : { kind: "paragraph", owner: owner }
    }
    finishNote()
}

function collectReferences(source) {
    var state = referenceState()
    blockPass(Html.documentText(source).split("\n"), state, undefined, true)
    return state
}

function blocks(source, dir, chrome, ink) {
    var lines = Html.documentText(source).split("\n")
    var state = referenceState()
    blockPass(lines, state, undefined, true)
    var writer = Document.writer(state, dir, chrome, ink)
    blockPass(lines, state, writer.project, false)
    return writer.finish()
}

function prepare(source, dir, defs, chrome, ink) {
    var lines = Html.documentText(source).split("\n")
    var state = referenceState()
    blockPass(lines, state, undefined, true)
    blockPass(lines, state, undefined, false)
    return Document.preparedText(lines, state, dir, defs, chrome, ink)
}
