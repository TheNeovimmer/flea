.pragma library

// Serialize the block reader's events; all container and code decisions belong to MdBlocks.
.import "MdLeaf.js" as Leaf
.import "MdRun.js" as Run

function visibleLines(lines, state) {
    var kept = []
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (state.hidden.hasOwnProperty(line.index))
            continue
        var text = line.text
        if (state.escaped.hasOwnProperty(line.index)) {
            var at = text.indexOf("[")
            text = text.slice(0, at) + "\\[" + text.slice(at + 1)
        }
        kept.push(text)
    }
    return kept
}

function writer(state, dir, chrome, ink) {
    var out = []
    var run = []
    var tokens = []
    var cited = []
    function inlineOf(text, citations, literalPlain) {
        return Run.parseInline(text, dir, state.defs, state.numbers, chrome, ink, tokens,
            citations === false ? undefined : cited, literalPlain)
    }
    function pushRun(lines) {
        var text = inlineOf(lines.join("\n"))
        if (text.trim().length > 0)
            out.push({ type: "run", text: text })
    }
    function flushRun() {
        var plain = []
        for (var i = 0; i < run.length; i++) {
            var solo = run[i].trim().length > 0 && (i === 0 || run[i - 1].trim().length === 0)
                && (i + 1 === run.length || run[i + 1].trim().length === 0)
            var image = solo ? Leaf.standaloneImage(run[i], dir, state.defs) : null
            if (image !== null) {
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
    function emit(event) {
        if (event.type === "run") {
            var lines = visibleLines(event.lines, state)
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
                out.push({ type: "fence", text: source, info: event.info })
        } else if (event.type === "heading") {
            if (event.text.length > 0)
                out.push({ type: "heading", level: event.level, text: inlineOf(Leaf.headingSafe(event.text)) })
        } else if (event.type === "table") {
            out.push(Leaf.tableBlock(event.head, event.aligns, event.rows,
                function (text) { return inlineOf(text, true, true) }))
        } else if (event.type === "quote") {
            var quote = visibleLines(event.lines, state)
            if (quote.join("\n").trim().length === 0)
                return
            var title = Leaf.alertTitle(quote[0])
            if (title !== null)
                quote[0] = title
            out.push({ type: "quote", text: inlineOf(quote.join("\n")) })
        } else if (event.type === "list") {
            var items = []
            for (var k = 0; k < event.items.length; k++) {
                var item = visibleLines(event.items[k], state)
                if (item.length > 0)
                    item[0] = Leaf.taskText(item[0])
                items.push(inlineOf(item.join("\n")))
            }
            if (items.length > 0)
                out.push({ type: "list", ordered: event.ordered, start: event.start, items: items })
        } else {
            out.push(event)
        }
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
                outer = { type: top.type, group: group, lines: [], items: [], ordered: top.ordered, start: top.start }
            if (event.kind === "codeEnd")
                return
            var line = { text: event.display, index: event.index }
            if (top.type === "quote") {
                outer.lines.push(line)
            } else {
                if (outer.item !== top.id) {
                    outer.items.push([])
                    outer.item = top.id
                }
                outer.items[outer.items.length - 1].push(line)
            }
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
        } else {
            flushCode()
            emit({ type: "run", lines: [{ text: event.text, index: event.index }] })
        }
    }
    function finish() {
        flushOuter()
        flushCode()
        flushRun()
        var footItems = []
        for (var i = 0; i < cited.length; i++) {
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
            prose.push(visibleLines([line], state)[0])
        }
    }
    flush()
    return out.join("\n")
}
