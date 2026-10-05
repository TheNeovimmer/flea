.pragma library

// MdChunks: a long list as consecutive blocks the outer ListView draws lazily.
.import "MdLeaf.js" as Leaf

var ORDERED_START = /^\d/
var ARRAY_FIELDS = ["depths", "markers", "gaps", "parts"]

// Sample input: a list "9.", "10." with a bullet under the first answers, at each chunk edge k, the runs still open after k entries.
function openRuns(list, size) {
    var open = []
    var previous = -1
    var edges = {}
    for (var k = 0; k < list.items.length; k++) {
        // A deeper entry opens a list and a changed marker kind starts another beside the old one, as MarkdownLists.layout reads them.
        if (k % size === 0)
            edges[k] = open.slice()
        var depth = list.depths !== undefined ? list.depths[k] : 0
        var given = list.markers !== undefined ? list.markers[k] : list.ordered ? (list.start + k) + "." : ""
        var ordered = given === "" ? (open[depth] !== undefined ? open[depth].ordered : list.ordered === true) : ORDERED_START.test(given)
        var run = open[depth]
        if (run === undefined || depth > previous || ordered !== run.ordered)
            run = { ordered: ordered, widest: "" }
        open.length = depth
        open[depth] = run
        if (ordered && given.length > run.widest.length)
            run.widest = given
        previous = depth
    }
    edges[list.items.length] = open.slice()
    return edges
}

// A run as the chunk carries it: its kind and the widest marker over the whole list, which fixes its text column.
function carried(runs) {
    return runs.map(function (run) { return { ordered: run.ordered, marker: run.widest } })
}

// Sample input: a list of 40 items answers two blocks of 32 and 8, numbering continued through start, last keeping one marker column width.
function chunkList(list) {
    if (list.items.length <= Leaf.LIST_CHUNK_ITEMS)
        return [list]
    var size = Leaf.LIST_CHUNK_ITEMS
    var chunks = []
    var last = list.start + list.items.length - 1
    // Entries of a nested list are not numbered items, so the last number is the last one a top-level marker carries.
    for (var m = 0; list.depths !== undefined && m < list.items.length; m++) {
        if (list.depths[m] === 0 && ORDERED_START.test(list.markers[m]))
            last = parseInt(list.markers[m], 10)
    }
    var edges = openRuns(list, size)
    for (var at = 0; at < list.items.length; at += size) {
        var chunk = { type: "list", ordered: list.ordered, start: list.start + at, items: list.items.slice(at, at + size), last: last, joined: at > 0 }
        // Each field of a nested, loose or part-holding list is cut at the same places, whichever of them the list carries.
        for (var f = 0; f < ARRAY_FIELDS.length; f++) {
            var name = ARRAY_FIELDS[f]
            if (list[name] !== undefined)
                chunk[name] = list[name].slice(at, at + size)
        }
        // A later chunk's first entry keeps the gap above it that the whole list gave it, a nested list's parent being the entry before.
        if (at > 0 && list.gaps !== undefined) {
            var deeper = list.depths !== undefined && list.depths[at] > list.depths[at - 1]
            chunk.gaps[0] = list.gaps[at] || (deeper && list.gaps[at - 1])
        }
        // The runs open at each end keep the text column the whole list gives them, so a sublist at a seam does not jump.
        chunk.carry = carried(edges[at])
        chunk.tail = carried(edges[Math.min(at + size, list.items.length)])
        chunks.push(chunk)
    }
    return chunks
}
