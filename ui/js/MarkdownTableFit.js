.pragma library

// MarkdownTableFit: how a table shares the width its block gives it, a pure function of column widths in pixels.

// Sample input: fit([100, 400], [50, 100], 300, 10) is [71, 228]: each column keeps its longest word, the rest goes by want.
// A table that fits keeps its natural widths; past that no column falls under its longest word or least (one narrower keeps its natural), so a hopeless one is wider than avail.
function fit(natural, minimum, avail, least) {
    function heldAt(c) {
        return natural[c] < least ? natural[c] : Math.max(least, Math.min(minimum[c], natural[c]))
    }
    function capped(w, c) {
        return Math.max(Math.min(least, natural[c]), Math.floor(w))
    }
    var total = 0
    var floor = 0
    for (var i = 0; i < natural.length; i++) {
        total += natural[i]
        floor += heldAt(i)
    }
    if (total <= avail)
        return natural.slice()
    var widths = []
    if (floor <= avail) {
        for (var c = 0; c < natural.length; c++) {
            var held = heldAt(c)
            widths.push(held + (avail - floor) * (natural[c] - held) / (total - floor))
        }
    } else {
        // Even the longest words do not fit: every column holds its longest word whole and the table scrolls sideways.
        for (var h = 0; h < natural.length; h++)
            widths.push(heldAt(h))
    }
    return widths.map(capped)
}
