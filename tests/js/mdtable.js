.import "../../ui/js/MdLeaf.js" as Leaf
.import "../../ui/js/MarkdownTableFit.js" as Fit
.import "../../ui/js/MdEscape.js" as Escape

// The table's column data the parser carries, and how the table shares its block's width between columns.
function run(assert) {
    function check(label, actual, expected) {
        assert(label, JSON.stringify(actual), JSON.stringify(expected))
    }
    function table(head, rows) {
        return Leaf.tableBlock(head, head.map(function () { return "left" }), rows, function (text) { return text })
    }
    function sum(list) { return list.reduce(function (a, b) { return a + b }, 0) }

    check("an image cell never wins the measure by its source text", table(["h"], [["![d](file:///x/dot.png) in"], ["a plain cell"]]).measure, ["a plain cell"])
    check("the image cell rides beside the measure so its width counts", table(["h"], [["![d](file:///x/dot.png) in"], ["a plain cell"]]).pictures, ["![d](file:///x/dot.png) in"])
    check("a raw img tag is an image too", table(["h"], [["<img src=\"a.png\" width=\"80\"> x"], ["ab"]]).pictures[0].indexOf("<img"), 0)
    check("a table without images carries no picture cell", table(["h"], [["a"], ["bb"]]).pictures, [""])
    check("a wide script takes two columns a glyph", table(["h"], [["abcdefghij"], ["日本語日本語"]]).measure, ["日本語日本語"])
    check("a break starts a line, so the widest line sets the width", table(["h"], [["First line<br>second line<br/>third"], ["a plain cell!"]]).measure, ["a plain cell!"])
    check("an emoji counts two columns on its own", Leaf.cellExtent("🚀").text, 2)
    check("a joined sequence counts two in all on its own", Leaf.cellExtent("👩‍💻").text, 2)
    // A chip pad is a spacer span, so a padded chip counts the columns of its text and keeps its words' length.
    var chipPad = Escape.chipPad()
    check("a chip's pad span holds no column", Leaf.cellExtent("a " + chipPad + "bc" + chipPad).text, 4)
    check("a chip's pad span adds no word length", Leaf.cellExtent("<code>" + chipPad + "bc" + chipPad + "</code>").word, 2)
    check("the pad leaves a column's weight as its plain text", table(["h"], [["x " + chipPad + "bc" + chipPad]]).weights, [4])
    check("an emoji takes two columns and a joined sequence two in all", [table(["h"], [["🚀"], ["abc"]]).weights[0], table(["h"], [["👩‍💻"], ["a"]]).weights[0]], [3, 2])
    check("the longest unbreakable run is the column's word", table(["h"], [["see /a/very/long/path ok"], ["short"]]).words, [17])
    check("a chunk keeps the table's shared column data", Leaf.chunkTable(table(["h"], Array.apply(null, Array(30)).map(function () { return ["ab"] })))
        .map(function (b) { return b.words[0] + ":" + b.weights[0] }).join(), "2:2,2:2")

    check("a table that fits keeps its natural widths", Fit.fit([50, 60], [20, 30], 200, 10), [50, 60])
    var shared = Fit.fit([100, 400], [50, 100], 300, 10)
    check("a too wide table gives each column its longest word and shares the rest by want", [sum(shared) <= 300, shared[0] >= 50, shared[1] >= 100, shared[1] > shared[0]], [true, true, true, true])
    check("a column that cannot wrap keeps its width beside a long one, and the table is wider than avail", Fit.fit([60, 1000], [60, 1000], 300, 10), [60, 1000])
    check("equal long columns share the room equally when their words fit", Fit.fit([900, 900, 900], [100, 100, 100], 300, 10), [100, 100, 100])
    check("equal long columns whose words do not fit hold their words whole", Fit.fit([900, 900, 900], [500, 500, 500], 300, 10), [500, 500, 500])
    check("a short column keeps its word while the long ones shrink to theirs", Fit.fit([40, 900, 900], [40, 100, 100], 300, 10), [40, 130, 130])
    check("a short column keeps its word beside long columns whose words do not fit", Fit.fit([40, 900, 900], [40, 500, 500], 300, 10), [40, 500, 500])
    check("a column never falls under the least a glyph needs", Fit.fit([900, 900, 900], [5, 5, 5], 20, 10), [10, 10, 10])
    check("no columns share nothing", Fit.fit([], [], 300, 10), [])
    var leastHeld = Fit.fit([30, 500], [5, 200], 300, 20)
    check("least joins each column floor, so the split shares 300 with none under 20", [sum(leastHeld) <= 300, leastHeld[0] >= 20, leastHeld[1] >= 20], [true, true, true])
    check("a hopeless table keeps a column narrower than least at its natural width and the rest at their words", Fit.fit([15, 15, 15, 15, 500], [15, 15, 15, 15, 400], 40, 20), [15, 15, 15, 15, 400])
    // A fixed seed keeps the sweep deterministic; the Park-Miller step stays under 2^53, so doubles hold it exactly.
    var sweepSeed = 1917
    var sweepTrials = 5000
    var parkMillerMultiplier = 48271
    var parkMillerModulus = 2147483647
    function sweepNext(bound) { sweepSeed = sweepSeed * parkMillerMultiplier % parkMillerModulus; return sweepSeed % bound }
    // Every swept split whose floors with least fit avail sums inside it (a hopeless one is wider); word runs draw from a tighter range.
    var sweepOver = 0
    var sweepUnder = 0
    var sweepBroken = 0
    for (var trial = 0; trial < sweepTrials; trial++) {
        var count = 1 + sweepNext(4)
        var wild = []
        var tiny = []
        for (var w = 0; w < count; w++) {
            wild.push(sweepNext(600))
            tiny.push(sweepNext(60))
        }
        var room = 50 + sweepNext(600)
        var need = 5 + sweepNext(30)
        var floor = 0
        for (var f = 0; f < count; f++) { floor += wild[f] < need ? wild[f] : Math.max(need, Math.min(tiny[f], wild[f])) }
        var split = Fit.fit(wild, tiny, room, need)
        if (floor <= room && sum(split) > room)
            sweepOver++
        // Hopeless or not, no column lands under least or its own natural width, whichever is smaller.
        for (var u = 0; u < count; u++) { if (split[u] < Math.min(need, wild[u])) sweepUnder++ }
        // Fitting or not, no column lands under its held width: its longest word, least, or its natural width when that is smaller.
        for (var k = 0; k < count; k++) { if (split[k] < (wild[k] < need ? wild[k] : Math.max(need, Math.min(tiny[k], wild[k])))) sweepBroken++ }
    }
    check("no fitting swept split ever sums past avail", sweepOver, 0)
    check("no swept column ever lands under least or its natural width", sweepUnder, 0)
    check("no swept column ever lands under its longest word", sweepBroken, 0)
}
