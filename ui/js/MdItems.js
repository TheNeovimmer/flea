.pragma library

.import "MdLeaf.js" as Leaf

// MdItems: one top-level list as flat entries (depth, marker, loose flag per list), and the quote and list blocks built from them.
var BULLET = "•"

// Sample input: "fenceBody" and "codeLine" are lines inside a fence or an indented block; "run" is prose.
function isRaw(kind) {
    return kind === "fenceOpen" || kind === "fenceBody" || kind === "fenceClose" || kind === "codeLine"
}

// Sample input: item "a" holding a nested list "b" answers entries a (depth 0, marker bullet) and b (depth 1).
function builder() {
    var entries = []
    // levels[d] is the list now open at depth d: its parent item, its kind, its item count and whether a blank line loosened it.
    var levels = []
    var heads = {}
    var cur = null
    var blank = false

    function sibling(depth, chain) {
        var lv = depth < levels.length ? levels[depth] : null
        return lv !== null && lv.mark === chain[depth].mark
    }

    function open(chain, depth) {
        var frame = chain[depth]
        var lv = sibling(depth, chain) ? levels[depth] : null
        if (lv !== null) {
            lv.count++
        } else {
            lv = { mark: frame.mark, start: frame.start, count: 0, loose: false }
            levels[depth] = lv
        }
        levels.length = depth + 1
        var entry = { depth: depth, lines: [], list: lv, frameId: frame.id, content: 0,
            marker: frame.ordered ? (lv.start + lv.count) + "." : BULLET }
        entries.push(entry)
        heads[frame.id] = entry
        return entry
    }

    // A blank line before a new item loosens the list the item joins, or the list whose item it nests in.
    function loosenOpened(chain, depth) {
        if (sibling(depth, chain))
            levels[depth].loose = true
        else if (depth > 0)
            levels[depth - 1].loose = true
    }

    function add(event, text) {
        var chain = event.chain
        var lead = event.lead
        var line = { text: text, index: event.index, raw: isRaw(event.kind) }
        var last = lead.n - 1
        var from = Math.min(lead.retained, lead.n)
        // A blank line opens no item; "-" alone opens an empty one.
        if (event.kind === "run" && text.trim().length === 0 && from > last) {
            blank = true
            if (cur !== null)
                cur.lines.push(line)
            return
        }
        if (from <= last) {
            if (blank)
                loosenOpened(chain, from)
            for (var depth = from; depth <= last; depth++)
                cur = open(chain, depth)
        } else {
            var head = heads[chain[last].id]
            if (cur.frameId !== head.frameId) {
                levels.length = last + 1
                cur = { depth: last, lines: [], list: head.list, frameId: head.frameId, content: 0, marker: "" }
                entries.push(cur)
                if (blank)
                    head.list.loose = true
            } else if (blank && cur.content > 0) {
                cur.list.loose = true
            }
        }
        blank = false
        cur.content++
        cur.lines.push(line)
    }

    return { add: add, entries: entries }
}

// The text of the lines that draw; kept.raw[k] marks a code line, which the renderer reads as code and the inline pass never sees.
function visibleLines(lines, state) {
    var kept = []
    kept.raw = []
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
        kept.raw.push(line.raw === true)
    }
    return kept
}

// Prose goes through the inline pass; a fence or indented code in an item or quote stays verbatim for the renderer.
function inlineLines(kept, inlineOf) {
    var parts = []
    var prose = []
    for (var k = 0; k <= kept.length; k++) {
        if (k < kept.length && !kept.raw[k]) {
            prose.push(kept[k])
            continue
        }
        if (prose.length > 0)
            parts.push(inlineOf(prose.join("\n")))
        prose = []
        if (k < kept.length)
            parts.push(kept[k])
    }
    return parts.join("\n")
}

// Sample input: lines "a" and "```" answer parts, prose alone answers its one text, and nothing to draw answers an empty text.
function content(lines, inlineOf, partsOf) {
    if (lines.join("\n").trim().length === 0)
        return { text: "" }
    var parts = partsOf(lines)
    if (parts === null)
        return { text: inlineLines(lines, inlineOf) }
    if (parts.length === 0)
        return { text: "" }
    if (parts.length === 1 && parts[0].type === "run" && parts[0].maths === undefined)
        return { text: parts[0].text }
    return { text: "", parts: parts }
}

// One quote block per run of lines at one nesting depth; the depth shows past the first level, joined after the first block.
function quoteBlocks(all, state, inlineOf, partsOf) {
    var out = []
    for (var at = 0; at < all.length; ) {
        var to = at
        while (to < all.length && all[to].depth === all[at].depth)
            to++
        var quote = visibleLines(all.slice(at, to), state)
        // A quote with nothing to draw is still a block: a browser gives it its margin.
        var title = at === 0 && quote.length > 0 && !quote.raw[0] ? Leaf.alertTitle(quote[0]) : null
        if (title !== null)
            quote[0] = title
        var held = content(quote, inlineOf, partsOf)
        var block = { type: "quote", text: held.text }
        if (held.parts !== undefined)
            block.parts = held.parts
        if (all[at].depth > 1)
            block.depth = all[at].depth
        if (at > 0)
            block.joined = true
        out.push(block)
        at = to
    }
    return out
}

// One list as a block; depths, markers and gaps only when nesting or looseness needs them, parts when an item holds more than prose.
function listBlock(event, state, inlineOf, partsOf) {
    var items = []
    var depths = []
    var markers = []
    var gaps = []
    var parts = []
    var nested = false
    var loose = false
    var holds = false
    var entries = event.builder.entries
    for (var k = 0; k < entries.length; k++) {
        var entry = entries[k]
        // An item that opens on a blank line starts at its first line of text.
        var first = 0
        while (first < entry.lines.length - 1 && entry.lines[first].text.trim().length === 0)
            first++
        var lines = visibleLines(entry.lines.slice(first), state)
        while (lines.length > 0 && lines[lines.length - 1].trim().length === 0)
            lines.pop()
        if (entry.marker !== "" && lines.length > 0 && !lines.raw[0])
            lines[0] = Leaf.taskText(lines[0])
        var gap = entry.list.loose
        nested = nested || entry.depth > 0 || entry.marker === ""
        loose = loose || gap
        var held = content(lines, inlineOf, partsOf)
        held.text = Leaf.pinTaskBox(held.text)
        if (held.parts !== undefined && held.parts[0].type === "run")
            held.parts[0].text = Leaf.pinTaskBox(held.parts[0].text)
        holds = holds || held.parts !== undefined
        items.push(held.text)
        parts.push(held.parts !== undefined ? held.parts : null)
        depths.push(entry.depth)
        markers.push(entry.marker)
        gaps.push(gap)
    }
    var block = { type: "list", ordered: event.ordered, start: event.start, items: items }
    if (nested || loose) {
        block.depths = depths
        block.markers = markers
        block.gaps = gaps
    }
    if (holds)
        block.parts = parts
    return block
}
