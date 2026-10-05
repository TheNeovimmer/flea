.pragma library

// MarkdownTableFit: how a table shares the width its block gives it, a pure function of column widths in pixels.

// Sample input: fit([100, 400], [50, 100], 300, 10) is [71, 228]: each column keeps its longest word, the rest goes by want.
// A table that fits keeps its natural widths; past that no column falls under the least a glyph needs, so a hopeless one overflows.
// A column narrower than least keeps its natural width: raising it would add width no share accounts for.
function fit(natural, minimum, avail, least) {
    function heldAt(c) {
        return natural[c] < least ? natural[c] : Math.max(least, Math.min(minimum[c], natural[c]))
    }
    function capped(w, c) {
        return natural[c] < least ? Math.floor(w) : Math.max(least, Math.floor(w))
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
        // Columns whose longest word fits an equal share keep it; the others split what is left equally.
        var open = natural.map(function (n, i) { return i })
        var left = avail
        var settled = true
        while (settled && open.length > 0) {
            settled = false
            var share = left / open.length
            for (var k = open.length - 1; k >= 0; k--) {
                var at = open[k]
                if (heldAt(at) <= share) {
                    widths[at] = heldAt(at)
                    left -= widths[at]
                    open.splice(k, 1)
                    settled = true
                }
            }
        }
        for (var o = 0; o < open.length; o++)
            widths[open[o]] = left / open.length
    }
    return widths.map(capped)
}
