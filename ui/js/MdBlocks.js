.pragma library

// The same streaming block pass collects definitions and renders with the resulting complete map.
.import "MdLeaf.js" as Leaf
.import "MdRefs.js" as Refs
.import "MdContainer.js" as Container
.import "MdDocument.js" as Document
.import "MdHtml.js" as Html
.import "MdMath.js" as Maths
.import "MdFront.js" as Front

var CODE_INDENT = 4
var MIN_RULE_MARKS = 3
var MAX_RULE_INDENT = 3
var LIST_INTERRUPT_START = 1
// A working parse proves it every few thousand block-pass events or PROGRESS_MS, so the pane's fallback waits for silence, never speed.
var PROGRESS_EVENTS = 4000
// Events cost more or less as the box is loaded, so a parse also beats once PROGRESS_MS passed, the clock read every CLOCK_EVENTS events.
var PROGRESS_MS = 500
var CLOCK_EVENTS = 64
// A live request is parsed SLICE_MS at a time, so a newer request is read between slices (a running parse cannot be cancelled).
var SLICE_MS = 200
var clock = Date.now
// A suite replaces the clock with a stepped one, so the clock beat is proved without waiting.
function useClock(now) {
    clock = now
}
// A slice's stop test: true once ms have passed, the clock read every CLOCK_EVENTS lines.
function sliceDue(ms) {
    var from = clock()
    var seen = 0
    return function () { return ++seen % CLOCK_EVENTS === 0 && clock() - from >= ms }
}
// A document nesting containers deeper than this is not rendered: blocks answers one sentinel and the pane shows the source.
var NESTING_LIMIT = 32
var SETEXT_MARK = /^(\s*)([=-])/
var hasOwn = Object.prototype.hasOwnProperty

function listMarker(line) {
    var mark = Container.readListMarker(line)
    if (mark !== null)
        mark.text = Leaf.taskText(mark.text)
    return mark
}

// Sample input: "mermaid chart title" selects a diagram by its first word, ignoring case.
function figureKind(info) {
    var first = String(info || "").trim().split(/\s+/)[0] || ""
    var word = first.toLowerCase()
    if (word === "mermaid")
        return "mermaid"
    if (word === "math" || word === "latex")
        return "math"
    return ""
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

// Keys are document text, so the three keyed maps have no prototype: "__proto__" and "hasOwnProperty" are ordinary ids.
function referenceState() {
    return { defs: Object.create(null), notes: Object.create(null), numbers: Object.create(null),
        hidden: {}, escaped: {}, code: {}, dropped: [] }
}

// Sample: "- > ```\n  > [id]: literal\n  > ```" matches an item, then a quote, before its fence; nested lines hold no front matter.
function blockPass(lines, state, emit, collect, nested, onProgress, job) {
    // A job's due() stops the pass at a line boundary, and its saved state is what the next slice resumes with.
    var frames = []
    var leaf = null
    var pending = null
    var serial = 0
    var lastQuote = -1
    // No listener means no heartbeat: a parse without onProgress never beats.
    var beatEvery = onProgress !== undefined ? PROGRESS_EVENTS : 0
    var sinceBeat = 0
    var beatAt = beatEvery !== 0 ? clock() : 0
    // Leading frames now open that share frame 0's type (items or quotes), where the line's text starts after them, and the frames found open.
    var lead = { n: 0, here: 0, lazy: false, retained: 0, at: 0, pad: 0, col: 0, raw: "" }
    function send(kind, index, text, top, display, info) {
        if (emit !== undefined)
            emit({ type: "line", kind: kind, index: index, text: text,
                outer: top, display: display, info: info || "", chain: frames, lead: lead,
                figureKind: kind === "fenceOpen" ? figureKind(info) : "" })
        // A pass carrying the heartbeat proves it is moving every few thousand sends or every half second.
        if (beatEvery !== 0) {
            sinceBeat++
            if (sinceBeat >= beatEvery || (sinceBeat % CLOCK_EVENTS === 0 && clock() - beatAt >= PROGRESS_MS)) {
                sinceBeat = 0
                beatAt = clock()
                onProgress()
            }
        }
    }
    function finishNote() {
        if (pending !== null && pending.note !== undefined)
            pending.note.text = pending.body.join("\n")
        pending = null
    }
    var due = job !== undefined ? job.due : undefined
    var from = 0
    if (job !== undefined && job.saved !== null) {
        from = job.saved.at
        frames = job.saved.frames
        leaf = job.saved.leaf
        pending = job.saved.pending
        serial = job.saved.serial
        lastQuote = job.saved.lastQuote
        lead = job.saved.lead
    }
    for (var i = from; i < lines.length; i++) {
        if (due !== undefined && due()) {
            job.saved = { at: i, frames: frames, leaf: leaf, pending: pending, serial: serial, lastQuote: lastQuote, lead: lead }
            job.paused = true
            return
        }
        var raw = lines[i]
        var view = { at: 0, padding: 0, column: 0 }
        var rawBlank = raw.trim().length === 0
        var matched = 0
        var leadHere = 0
        lead = { n: lead.n, here: 0, lazy: false, retained: 0, at: 0, pad: 0, col: 0, raw: raw }
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
                if (indent >= frame.contentCol && frame.sealed !== true) {
                    Container.takeIndent(raw, view, frame.contentCol)
                } else if (rawBlank || raw.slice(view.at).trim().length === 0) {
                    // An item opened on a blank line holds at most that one blank line, so a second seals it against more content.
                    if (frame.bareAt === i - 1)
                        frame.sealed = true
                    if (matched > lastQuote) {
                        matched = frames.length
                        break
                    }
                } else {
                    break
                }
            }
            if (frame.type === frames[0].type && leadHere === matched) {
                lead.here = ++leadHere
                lead.at = view.at
                lead.pad = view.padding
                lead.col = view.column
            }
            if (matched === 0)
                display = Container.textAt(raw, view)
        }
        var unmatchedText = Container.textAt(raw, view)
        var startsQuote = Container.quoteAt(raw, view) >= 0
        var startsList = Container.listAt(raw, view)
        var siblingList = matched < frames.length && frames[matched].type === "list" && startsList !== null
        var listInterrupts = startsList !== null && (siblingList || ((!startsList.ordered
            || startsList.start === LIST_INTERRUPT_START) && raw.slice(startsList.markerEnd).trim().length > 0))
        var startsFence = Leaf.fenceOpen(unmatchedText)
        var thematic = Leaf.isThematic(unmatchedText)
        var setext = leaf !== null && leaf.kind === "paragraph" && matched === frames.length && Leaf.isSetext(unmatchedText)
        var lazy = leaf !== null && leaf.kind === "paragraph" && unmatchedText.trim().length > 0
            && !startsQuote && !listInterrupts && startsFence === null && !thematic
            && !/^ {0,3}#{1,6}(?:\s|$)/.test(unmatchedText)
        if (matched < frames.length && !lazy) {
            frames.length = matched
            lead.n = Math.min(lead.n, matched)
            lastQuote = -1
            for (var q = 0; q < frames.length; q++) {
                if (frames[q].type === "quote")
                    lastQuote = q
            }
            leaf = null
        }
        var owner = frames.length > 0 ? frames[frames.length - 1].id : 0
        var fenced = leaf !== null && leaf.kind === "fence" && leaf.owner === owner
        lead.retained = frames.length
        lead.lazy = lazy && matched < frames.length
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
                    next.mark = marker.mark
                    next.start = marker.start
                    next.bareAt = raw.slice(marker.markerEnd).trim().length === 0 ? i : -1
                    next.group = frames.length === 0 && previousTop !== null
                        && previousTop.type === "list" && previousTop.mark === marker.mark
                        ? previousTop.group : next.id
                    Container.takeList(raw, view, marker)
                }
                if (lead.n === frames.length && (frames.length === 0 || next.type === frames[0].type)) {
                    lead.here = ++lead.n
                    leadHere = lead.n
                    lead.at = view.at
                    lead.pad = view.padding
                    lead.col = view.column
                }
                frames.push(next)
                if (frames.length > NESTING_LIMIT) {
                    state.deep = true
                    return
                }
                owner = next.id
                leaf = null
                if (frames.length === 1)
                    display = Container.textAt(raw, view)
            }
        }
        var top = frames.length > 0 ? frames[0] : null
        var text = Container.textAt(raw, view)
        // Sample: "> foo\nbar\n===" keeps its lazy "===" as text, so the renderer cannot take it for a setext underline.
        if (lazy && matched < frames.length && Leaf.isSetext(unmatchedText)) {
            text = text.replace(SETEXT_MARK, "$1\\$2")
            display = display.replace(SETEXT_MARK, "$1\\$2")
        }
        if (fenced) {
            var closer = Leaf.fenceOpen(text)
            var closed = closer !== null && closer.info === "" && closer.tick === leaf.tick && closer.len >= leaf.len
            state.code[i] = true
            send(closed ? "fenceClose" : "fenceBody", i, closed ? text : Container.unindent(text, leaf.indent), top, display)
            if (closed)
                leaf = null
            continue
        }
        if (pending !== null) {
            if (collect && pending.owner === owner && pending.note !== undefined
                    && Container.indentationAt(raw, view).width >= CODE_INDENT) {
                pending.body.push(text.replace(/^\s+/, ""))
                Refs.hideDefinition(state, i, i)
                send("hidden", i, text, top, display)
                continue
            }
            if (collect && pending.owner === owner && pending.ref !== undefined && Leaf.fenceOpen(text) === null) {
                // Sample: '[cover].png "Title"' accepts a destination only when the complete line parses.
                var destination = Refs.readDefinitionParts(text.trim())
                if (destination.target !== "") {
                    Refs.storeDefinition(state.defs, pending.ref.key, destination.target)
                    Refs.hideDefinition(state, pending.index, i)
                    Refs.hideTitle(lines, i + 1, state, owner === 0 && !destination.titled)
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
        var front = i === 0 && nested !== true ? Front.closeAt(lines) : -1
        if (front > 0) {
            i = Front.sendFront(lines, front, send, state)
            leaf = null
            continue
        }
        var open = Leaf.fenceOpen(text)
        if (open !== null) {
            leaf = { kind: "fence", owner: owner, tick: open.tick, len: open.len, indent: open.indent }
            state.code[i] = true
            send("fenceOpen", i, text, top, display, open.info)
            continue
        }
        // Sample input: "$$x^2$$" and "$$\nx^2\n$$" emit figures, with trailing prose retained.
        var math = top === null ? Maths.displayAt(lines, i, text) : null
        if (math !== null) {
            for (var m = i; m <= math.to; m++)
                state.code[m] = true
            if (emit !== undefined)
                emit({ type: "figure", kind: "math", source: math.source, display: true })
            i = math.to
            if (math.tail.length > 0)
                send("run", i, math.tail, null, math.tail)
            leaf = math.tail.trim().length > 0 ? { kind: "paragraph", owner: owner } : null
            continue
        }
        var blank = text.trim().length === 0
        var width = Container.indentationAt(raw, view).width
        if (leaf !== null && leaf.kind === "code" && (blank || width >= CODE_INDENT)) {
            state.code[i] = true
            Container.takeIndent(raw, view, CODE_INDENT)
            send("codeLine", i, Container.textAt(raw, view), top, display)
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
            // Outside a container a definition may span lines; inside one it is read a line at a time.
            var multi = note === null && top === null ? Refs.definitionAt(lines, i) : null
            var ref = note === null && top !== null ? Refs.readDefinition(text) : null
            if (multi !== null) {
                Refs.storeDefinition(state.defs, multi.key, multi.target)
                Refs.hideDefinition(state, i, multi.end)
                i = multi.end
                continue
            }
            if (note !== null) {
                var stored = hasOwn.call(state.notes, note.id) ? null : { text: note.text }
                if (stored !== null) {
                    state.notes[note.id] = stored
                    state.numbers[note.id] = 0
                }
                pending = { owner: owner, note: stored || {}, body: [note.text] }
                Refs.hideDefinition(state, i, i)
                send("hidden", i, text, top, display)
                continue
            }
            if (ref !== null) {
                if (ref.target !== "") {
                    Refs.storeDefinition(state.defs, ref.key, ref.target)
                    Refs.hideDefinition(state, i, i)
                    Refs.hideTitle(lines, i + 1, state, owner === 0 && !ref.titled)
                    send("hidden", i, text, top, display)
                    continue
                }
                pending = { owner: owner, ref: ref, index: i }
            }
        }
        var heading = top === null ? Leaf.atxHeading(text) : null
        if (heading !== null) {
            if (emit !== undefined)
                emit({ type: "heading", level: heading.level, text: heading.text })
            leaf = null
            continue
        }
        var aligns = top === null && text.indexOf("|") >= 0 && i + 1 < lines.length ? Leaf.delimAligns(lines[i + 1]) : null
        var header = aligns === null ? null : Leaf.splitRow(text)
        // The delimiter row must match the header's cell count; a row ends the table at a blank line or another block.
        if (header !== null && header.length === aligns.length) {
            var rows = []
            i += 2
            while (i < lines.length && lines[i].trim().length > 0 && !Container.startsBlock(lines[i]))
                rows.push(Leaf.splitRow(lines[i++]))
            if (emit !== undefined)
                emit({ type: "table", head: header, aligns: aligns, rows: rows })
            i--
            leaf = null
            continue
        }
        if (Refs.killDefinition(text) !== text)
            state.escaped[i] = true
        send(setext && top === null ? "setext" : "run", i, text, top, display)
        leaf = blank || setext || Leaf.isThematic(text) || /^ {0,3}#{1,6}(?:\s|$)/.test(text) ? null : { kind: "paragraph", owner: owner }
    }
    finishNote()
}

function collectReferences(source) {
    var state = referenceState()
    blockPass(Html.documentText(source).split("\n"), state, undefined, true)
    return state
}

// A parse that stops between lines: run(due) answers the blocks when both passes are done, or null when due() stopped it.
function blockJob(source, dir, chrome, ink, headCount, onHead, onProgress) {
    var lines = Html.documentText(source).split("\n")
    var state = referenceState()
    var collecting = { due: undefined, saved: null, paused: false }
    var rendering = { due: undefined, saved: null, paused: false }
    var writer = null
    var project = null
    var answer = null
    function run(due) {
        if (answer !== null)
            return answer
        if (writer === null) {
            collecting.due = due
            collecting.paused = false
            // The collecting pass carries the heartbeat too, so a slow reference scan still proves it is moving.
            blockPass(lines, state, undefined, true, undefined, onProgress, collecting)
            if (collecting.paused)
                return null
            if (state.deep === true) {
                answer = [{ type: "deep", limit: NESTING_LIMIT }]
                return answer
            }
            writer = Document.writer(state, dir, chrome, ink, blockPass)
            project = onHead !== undefined && headCount > 0 ? writer.headed(headCount, onHead) : writer.project
        }
        rendering.due = due
        rendering.paused = false
        blockPass(lines, state, project, false, undefined, onProgress, rendering)
        if (rendering.paused)
            return null
        answer = writer.finish()
        return answer
    }
    return { run: run }
}

function blocks(source, dir, chrome, ink, headCount, onHead, onProgress) {
    var job = blockJob(source, dir, chrome, ink, headCount, onHead, onProgress)
    return job.run(undefined)
}

function prepare(source, dir, defs, chrome, ink) {
    var lines = Html.documentText(source).split("\n")
    var state = referenceState()
    blockPass(lines, state, undefined, true)
    return Document.preparedText(lines, state, dir, defs, chrome, ink)
}
