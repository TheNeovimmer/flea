.pragma library

// MarkdownLists: where each entry of a list block draws, from the parser's depths, markers and gaps.

// Unordered markers by depth are disc, circle, square (U+2022, U+25E6, U+25AA), then square for deeper levels.
var BULLETS = ["•", "◦", "▪"]
var ORDERED_MARKER = /^\d/

function bulletAt(depth) {
    return BULLETS[Math.min(depth, BULLETS.length - 1)]
}

// The first drawn text under an item's blocks, in tree order, skipping the hidden measurer.
function firstPartsText(blocks) {
    if (blocks.children === undefined)
        return null
    for (var i = 0; i < blocks.children.length; i++) {
        var kid = blocks.children[i]
        if (kid.box !== undefined && kid.baselineOffset !== undefined && kid.visible && typeof kid.text === "string" && kid.text.length > 0 && kid.objectName !== "measurer")
            return kid
        var deep = firstPartsText(kid)
        if (deep !== null)
            return deep
    }
    return null
}

// The marker y for an item drawn through blocks, 0 when its first block is not a paragraph run.
// Sample input: blocks holding a run then a fence answer the run text baseline less the marker baseline, else 0.
function partsMarkerY(blocksRoot, markerBase) {
    if (blocksRoot === null || blocksRoot === undefined || blocksRoot.blocks === undefined || blocksRoot.blocks.length === 0)
        return 0
    var first = blocksRoot.blocks[0]
    if (first.type !== "run" || first.maths !== undefined)
        return 0
    var text = firstPartsText(blocksRoot)
    if (text === null || !text.visible)
        return 0
    return text.baselineOffset - markerBase
}

// Sample input: items a (depth 0) and b (depth 1) answer cells at x 0 and at a's marker width plus spacing.
// advance(text) is the marker font's advance width; spacing is the gap between a marker and its text.
function layout(block, advance, spacing) {
    var count = block.items.length
    var out = []
    var runs = []
    var open = []
    var previous = -1
    var bullet = advance(BULLETS[0])
    // The marker a run's column is sized by: the parser's own for an ordered run, the depth's bullet for the rest.
    function widest(held, depth) {
        return held.ordered ? held.marker : bulletAt(depth)
    }
    // A chunk opens under the runs the list had open before it, each at the column the whole list gives it.
    var carry = block.carry !== undefined ? block.carry : []
    for (var c = 0; c < carry.length; c++) {
        var held = { depth: c, ordered: carry[c].ordered, width: advance(widest(carry[c], c)), parent: c > 0 ? open[c - 1] : undefined, x: 0 }
        runs.push(held)
        open[c] = held
        previous = c
    }
    for (var k = 0; k < count; k++) {
        var depth = block.depths !== undefined ? block.depths[k] : 0
        var given = block.markers !== undefined ? block.markers[k] : block.ordered ? (block.start + k) + "." : BULLETS[0]
        var ordered = given === "" ? (open[depth] !== undefined ? open[depth].ordered : block.ordered) : ORDERED_MARKER.test(given)
        var run = open[depth]
        // A deeper entry opens a list under the item above, and a changed marker kind starts a list beside the old one.
        if (run === undefined || depth > previous || ordered !== run.ordered) {
            run = { depth: depth, ordered: ordered, width: 0, parent: depth > 0 ? open[depth - 1] : undefined, x: 0 }
            runs.push(run)
        }
        open.length = depth
        open[depth] = run
        var marker = given === "" ? "" : ordered ? given : bulletAt(depth)
        run.width = Math.max(run.width, advance(marker))
        // A long list's later chunks keep the first chunk's marker column width, so a chunk's text stays in line with its neighbours.
        if (depth === 0 && ordered && block.last !== undefined)
            run.width = Math.max(run.width, advance(block.last + "."))
        // A joined chunk lies flush under its predecessor, so its first entry keeps the gap the whole list gave it.
        var gap = (k > 0 || block.joined === true) && block.gaps !== undefined && (block.gaps[k] || (k > 0 && depth > previous && block.gaps[k - 1]))
        out.push({ x: 0, w: 0, marker: marker, gap: gap === true, run: run })
        previous = depth
    }
    // The runs still open at the chunk's end take the column the whole list gives them, which a later entry may widen.
    var tail = block.tail !== undefined ? block.tail : []
    for (var t = 0; t < tail.length; t++) {
        if (open[t] !== undefined && open[t].ordered === tail[t].ordered)
            open[t].width = Math.max(open[t].width, advance(widest(tail[t], t)))
    }
    // Parents come before their children in runs, so a run's own column is known when its children read it.
    for (var r = 0; r < runs.length; r++) {
        var at = runs[r]
        // A chunk that opens inside a nested list with nothing carried has no parent here, so each missing level counts one disc column.
        at.x = at.parent !== undefined ? at.parent.x + at.parent.width + spacing : at.depth * (bullet + spacing)
    }
    for (var e = 0; e < out.length; e++) {
        out[e].x = out[e].run.x
        out[e].w = out[e].run.width
        delete out[e].run
    }
    return out
}
