.pragma library

// MarkdownLists: where each entry of a list block draws, from the parser's depths, markers and gaps.
// Unordered markers by depth: disc, circle, square (U+2022, U+25E6, U+25AA), then square for deeper levels.
var BULLETS = ["•", "◦", "▪"]
var ORDERED_MARKER = /^\d/

function bulletAt(depth) {
    return BULLETS[Math.min(depth, BULLETS.length - 1)]
}

// Sample input: block { items: ["a", "b", "c"], depths: [0, 1, 0], markers: ["•", "•", "•"] } answers
// [{ x: 0, w: 8, marker: "•", gap: false }, { x: 8 + spacing, ... marker: "◦" }, { x: 0, ... }].
// advance(text) is the marker font's advance width; spacing is the gap between a marker and its text.
function layout(block, advance, spacing) {
    var count = block.items.length
    var out = []
    var runs = []
    var open = []
    var previous = -1
    var bullet = advance(BULLETS[0])
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
        var gap = k > 0 && block.gaps !== undefined && (block.gaps[k] || (depth > previous && block.gaps[k - 1]))
        out.push({ x: 0, w: 0, marker: marker, gap: gap === true, run: run })
        previous = depth
    }
    // Parents come before their children in runs, so a run's own column is known when its children read it.
    for (var r = 0; r < runs.length; r++) {
        var at = runs[r]
        // A chunk that opens inside a nested list has no parent here, so each missing level counts one disc column.
        at.x = at.parent !== undefined ? at.parent.x + at.parent.width + spacing : at.depth * (bullet + spacing)
    }
    for (var e = 0; e < out.length; e++) {
        out[e].x = out[e].run.x
        out[e].w = out[e].run.width
        delete out[e].run
    }
    return out
}
