.pragma library

// MdChunks: a long list as consecutive blocks the outer ListView draws lazily.
.import "MdLeaf.js" as Leaf

// Sample input: a list of 40 items answers two blocks of 32 and 8, numbering continued through start, last keeping one marker column width.
function chunkList(list) {
    if (list.items.length <= Leaf.LIST_CHUNK_ITEMS)
        return [list]
    var size = Leaf.LIST_CHUNK_ITEMS
    var chunks = []
    var last = list.start + list.items.length - 1
    // Entries of a nested list are not numbered items, so the last number is the last one a top-level marker carries.
    for (var m = 0; list.depths !== undefined && m < list.items.length; m++) {
        if (list.depths[m] === 0 && /^\d/.test(list.markers[m]))
            last = parseInt(list.markers[m], 10)
    }
    for (var at = 0; at < list.items.length; at += size) {
        var chunk = { type: "list", ordered: list.ordered, start: list.start + at, items: list.items.slice(at, at + size), last: last, joined: at > 0 }
        // A nested or loose list keeps its depths, markers and gaps beside its items, cut at the same places.
        if (list.depths !== undefined) {
            chunk.depths = list.depths.slice(at, at + size)
            chunk.markers = list.markers.slice(at, at + size)
            chunk.gaps = list.gaps.slice(at, at + size)
        }
        chunks.push(chunk)
    }
    return chunks
}
