.pragma library

// Serialize the block reader's events; all container and code decisions belong to MdBlocks.
.import "MdLeaf.js" as Leaf
.import "MdContainer.js" as Container
.import "MdRun.js" as Run
.import "MdItems.js" as Items
.import "MdChunks.js" as Chunks
.import "MdResolve.js" as Res
.import "MdMath.js" as Maths
.import "MdEntity.js" as Ent

// Items and quotes hold their blocks as parts down to this many levels; deeper text stays one markdown text, which keeps a deep chain linear.
var NEST_LIMIT = 8

// shared is set for the writer of an item's or a quote's parts, which numbers footnotes and tokens with the document's.
function writer(state, dir, chrome, ink, pass, shared) {
    var out = []
    var run = []
    var tokens = shared !== undefined ? shared.tokens : []
    var cited = shared !== undefined ? shared.cited : []
    var level = shared !== undefined ? shared.level : 0
    function inlineOf(text, citations, literalPlain, bareText) {
        return Run.parseInline(text, dir, state.defs, state.numbers, chrome, ink, tokens,
            citations === false ? undefined : cited, literalPlain, bareText)
    }
    // Prose outside every container: a ">" in it, even after a formula's figure, is text and never a quote mark.
    function pushText(text) {
        var html = inlineOf(text, undefined, false, true)
        if (html.trim().length === 0)
            return
        var block = { type: "run", text: html }
        var maths = Maths.inlineSources(text)
        if (maths.length > 0)
            block.maths = maths
        out.push(block)
    }
    // A display formula inside a paragraph stands on its own as a figure, the way a display block does.
    function pushRun(lines) {
        var text = lines.join("\n")
        var pieces = Maths.splitDisplay(text)
        if (pieces === null)
            return pushText(text)
        for (var p = 0; p < pieces.length; p++) {
            if (pieces[p].math === undefined)
                pushText(pieces[p].text)
            else if (pieces[p].math !== "")
                out.push({ type: "figure", kind: "math", source: pieces[p].math, display: true })
        }
    }
    // Sample input: the lines "a", "```", "x", "```" answer a run and a fence; null past NEST_LIMIT, where the lines stay one text.
    function partsOf(lines) {
        if (level >= NEST_LIMIT)
            return null
        var own = { defs: state.defs, notes: state.notes, numbers: state.numbers, hidden: {}, escaped: {}, code: {}, dropped: [] }
        var inner = writer(own, dir, chrome, ink, pass, { tokens: tokens, cited: cited, level: level + 1 })
        pass(lines, own, inner.project, false, true)
        return inner.finish()
    }
    function pushAll(blocks) {
        for (var b = 0; b < blocks.length; b++)
            out.push(blocks[b])
    }
    function flushRun() {
        var plain = []
        for (var i = 0; i < run.length; i++) {
            var solo = run[i].trim().length > 0 && (i === 0 || run[i - 1].trim().length === 0)
                && (i + 1 === run.length || run[i + 1].trim().length === 0)
            var image = solo ? Leaf.standaloneImage(run[i], dir, state.defs) : null
            if (image !== null) {
                image.alt = Res.plainText(inlineOf(image.alt, false))
                pushRun(plain)
                plain = []
                out.push(image)
            } else {
                plain.push(run[i])
            }
        }
        pushRun(plain)
        run = []
    }
    // The underline of a setext heading takes the paragraph above it out of the pending run and draws it as a heading.
    function setext(event) {
        var at = run.length
        while (at > 0 && run[at - 1].trim().length > 0 && !Leaf.isThematic(run[at - 1]))
            at--
        var paragraph = run.slice(at)
        run.length = at
        flushRun()
        var text = Leaf.headingSafe(paragraph.join("\n").trim())
        if (text !== "")
            out.push({ type: "heading", level: Leaf.setextLevel(event.text), text: inlineOf(text) })
    }
    function emit(event) {
        if (event.type === "setext")
            return setext(event)
        if (event.type === "run") {
            var lines = Items.visibleLines(event.lines, state)
            for (var l = 0; l < lines.length; l++)
                run.push(lines[l])
            return
        }
        flushRun()
        if (event.type === "fence") {
            var source = event.lines.map(function (line) { return line.text }).join("\n")
            if (event.figureKind !== "")
                out.push({ type: "figure", kind: event.figureKind, source: source, display: true })
            else
                out.push({ type: "fence", text: source, info: Ent.decodeReferences(event.info) })
        } else if (event.type === "heading") {
            out.push({ type: "heading", level: event.level, text: inlineOf(Leaf.headingSafe(event.text)) })
        } else if (event.type === "table") {
            pushAll(Leaf.chunkTable(Leaf.tableBlock(event.head, event.aligns, event.rows,
                function (text) { return inlineOf(text, true, true) })))
        } else if (event.type === "quote") {
            pushAll(Items.quoteBlocks(event.lines, state, inlineOf, partsOf))
        } else if (event.type === "list") {
            var list = Items.listBlock(event, state, inlineOf, partsOf)
            if (list.items.length > 0)
                pushAll(Chunks.chunkList(list))
        } else {
            out.push(event)
        }
    }
    // The line's text once the list markers and indents around it are gone; a lazy line has none to remove.
    function leadText(event) {
        var lead = event.lead
        return lead.here === lead.n && !lead.lazy
            ? " ".repeat(lead.pad) + Container.expandLead(lead.raw.slice(lead.at), lead.col + lead.pad) : event.text
    }
    // A delimiter row the block reader refused as a table keeps its first dash from the renderer, which would make a table of it.
    function tableless(text) {
        return text.indexOf("|") >= 0 && Leaf.delimAligns(text) !== null ? text.replace("-", "\\-") : text
    }
    var outer = null
    var code = null
    function flushOuter() {
        if (outer !== null)
            emit(outer)
        outer = null
    }
    function flushCode() {
        if (code === null)
            return
        if (code.indented) {
            while (code.lines.length > 0 && code.lines[code.lines.length - 1].text.trim().length === 0)
                code.lines.pop()
        }
        emit(code)
        code = null
    }
    function project(event) {
        if (event.type !== "line") {
            flushOuter()
            flushCode()
            emit(event)
            return
        }
        var top = event.outer
        var group = top === null ? null : top.type === "list" ? top.group : top.id
        if (outer !== null && outer.group !== group)
            flushOuter()
        if (top !== null) {
            flushCode()
            if (outer === null)
                outer = { type: top.type, group: group, lines: [], ordered: top.ordered, start: top.start,
                    builder: top.type === "list" ? Items.builder() : null }
            if (event.kind === "codeEnd")
                return
            if (top.type === "quote")
                outer.lines.push({ text: leadText(event), index: event.index, depth: event.lead.n, raw: Items.isRaw(event.kind) })
            else
                outer.builder.add(event, leadText(event))
            return
        }
        if (event.kind === "hidden")
            return
        if (event.kind === "fenceOpen") {
            flushCode()
            code = { type: "fence", lines: [], info: event.info, figureKind: event.figureKind, indented: false }
        } else if (event.kind === "fenceBody" || event.kind === "codeLine") {
            if (code === null)
                code = { type: "fence", lines: [], info: "", figureKind: "", indented: true }
            code.lines.push({ text: event.text, index: event.index })
        } else if (event.kind === "fenceClose" || event.kind === "codeEnd") {
            flushCode()
        } else if (event.kind === "setext") {
            flushCode()
            emit({ type: "setext", text: event.text })
        } else {
            flushCode()
            emit({ type: "run", lines: [{ text: tableless(event.text), index: event.index }] })
        }
    }
    function finish() {
        flushOuter()
        // A fence left open at the end of the text holds no line for the final newline.
        if (code !== null && !code.indented && code.lines.length > 0 && code.lines[code.lines.length - 1].text === "")
            code.lines.pop()
        flushCode()
        flushRun()
        var footItems = []
        // Only the document's own writer lists the notes cited anywhere, parts included.
        for (var i = 0; shared === undefined && i < cited.length; i++) {
            var id = cited[i]
            footItems.push("<sup>" + state.numbers[id] + "</sup> " + inlineOf(state.notes[id].text, false))
        }
        if (footItems.length > 0) {
            out.push({ type: "run", text: "---" })
            out.push({ type: "list", ordered: false, start: 0, items: footItems })
        }
        return out
    }
    return { project: project, finish: finish }
}

function preparedText(lines, state, dir, defs, chrome, ink) {
    var out = []
    var prose = []
    var tokens = []
    var cited = []
    function flush() {
        if (prose.length > 0)
            out.push(Run.parseInline(prose.join("\n"), dir, defs || state.defs,
                state.numbers, chrome, ink, tokens, cited))
        prose = []
    }
    for (var i = 0; i < lines.length; i++) {
        var line = { text: lines[i], index: i }
        if (state.hidden.hasOwnProperty(line.index))
            continue
        if (state.code.hasOwnProperty(line.index)) {
            flush()
            out.push(line.text)
        } else {
            prose.push(Items.visibleLines([line], state)[0])
        }
    }
    flush()
    return out.join("\n")
}
