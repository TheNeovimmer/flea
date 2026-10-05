.pragma library

// MarkdownTableFit: how a table shares the width its block gives it, a pure function of column widths in pixels.

// Sample input: fit([100, 400], [50, 100], 300, 10) is [71, 228]: each column keeps its longest word, the rest goes by want.
// A table that fits keeps its natural widths; past that no column falls under the least a glyph needs, so a hopeless one overflows.
function fit(natural, minimum, avail, least) {
    var total = 0
    var floor = 0
    for (var i = 0; i < natural.length; i++) {
        total += natural[i]
        floor += Math.min(minimum[i], natural[i])
    }
    if (total <= avail)
        return natural.slice()
    var widths = []
    if (floor <= avail) {
        for (var c = 0; c < natural.length; c++) {
            var held = Math.min(minimum[c], natural[c])
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
                if (Math.min(minimum[at], natural[at]) <= share) {
                    widths[at] = Math.min(minimum[at], natural[at])
                    left -= widths[at]
                    open.splice(k, 1)
                    settled = true
                }
            }
        }
        for (var o = 0; o < open.length; o++)
            widths[open[o]] = left / open.length
    }
    return widths.map(function (w) { return Math.max(least, Math.floor(w)) })
}
