.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MarkdownLists.js" as Lists
.import "../../ui/js/MarkdownMaths.js" as Maths

// Where nested entries and inline formulas draw: the list layout, the chunk carry-over and the formula picture.
function run(check) {
    var dir = "/home/gm/notes"
    var chrome = "#181825"
    var ink = "#c0caf5"
    // A fake font: every character is 8 px wide, a bullet included.
    var CHAR_PX = 8
    var GAP = 6
    function advance(text) { return String(text).length * CHAR_PX }
    function layout(doc) {
        var block = Markdown.blocks(doc, dir, chrome, ink)[0]
        return Lists.layout(block, advance, GAP)
    }
    function columns(cells) {
        return cells.map(function (c) { return c.x }).join(",")
    }
    var bullet = "•", circle = "◦", square = "▪"

    // A depth's marker column starts at its parent's text column, and its marker follows the depth.
    var nested = layout("- one\n  - two\n    - three\n- four\n  - five\n")
    check("markers by depth are disc, circle, square", nested.map(function (c) { return c.marker }).join(""), bullet + circle + square + bullet + circle)
    var text0 = CHAR_PX + GAP
    check("a nested marker starts at the parent's text column", columns(nested), [0, text0, 2 * text0, 0, text0].join(","))
    check("a fourth level keeps the square", layout("- a\n  - b\n    - c\n      - d\n")[3].marker, square)
    check("a tight list has no gaps", nested.some(function (c) { return c.gap }), false)

    // An ordered parent's text column follows its own marker width, and a bullet child starts there.
    var ordered = layout("9. a\n   - b\n10. c\n")
    check("ordered markers keep the parser's numbers", ordered.map(function (c) { return c.marker }).join(" "), "9. " + circle + " 10.")
    check("an ordered list's entries share the widest marker column", ordered[0].w, 3 * CHAR_PX)
    check("a child starts at the wider text column", ordered[1].x, 3 * CHAR_PX + GAP)

    // A loose list has the gap before every entry but the first; a blank before a nested list puts it above that list too.
    check("a loose list gaps its entries after the first", layout("- a\n\n- b\n\n- c\n").map(function (c) { return c.gap }).join(","), "false,true,true")
    check("a loose item gaps its nested list", layout("- a\n\n  - b\n- c\n").map(function (c) { return c.gap }).join(","), "false,true,true")
    check("a continuation paragraph has no marker and sits in its item's marker column, so its text is the item's text column", JSON.stringify(layout("- a\n  - b\n\n  tail\n").slice(1).map(function (c) { return [c.marker, c.x] })),
        JSON.stringify([[circle, text0], ["", 0]]))
    check("a flat list reads its numbering without the parser's markers", Lists.layout({ ordered: true, start: 8, items: ["a", "b", "c"] }, advance, GAP).map(function (c) { return c.marker }).join(" "), "8. 9. 10.")

    // A chunk after the first keeps depths, markers and the first chunk's marker width, and a chunk that opens deep counts a disc column per missing level.
    var long = []
    for (var i = 1; i <= 40; i++)
        long.push(i + ". item" + (i === 33 ? "\n    - child" : ""))
    var chunks = Markdown.blocks(long.join("\n") + "\n", dir, chrome, ink)
    check("a long nested list splits in chunks of 32 entries", chunks.map(function (b) { return b.items.length }).join(","), "32,9")
    check("a later chunk keeps its depths", JSON.stringify(chunks[1].depths), JSON.stringify([0, 1, 0, 0, 0, 0, 0, 0, 0]))
    check("a later chunk carries the markers of its entries", chunks[1].markers[0] + " " + chunks[1].markers[1], "33. " + bullet)
    check("every chunk's marker column is as wide as the last number's", Lists.layout(chunks[0], advance, GAP)[0].w, 3 * CHAR_PX)
    var orphan = Lists.layout({ items: ["x"], depths: [2], markers: [bullet], gaps: [false] }, advance, GAP)
    check("a chunk that opens inside a nested list counts a disc column per level", orphan[0].x, 2 * (CHAR_PX + GAP))

    // A formula's picture: baseline at the centre plus the anchor, tall enough for its own depth, padded to the least height.
    var svg = '<svg style="vertical-align: -3px;" width="30px" height="10px" viewBox="0 -15 60 20" role="img"><path d="M0 0"/></svg>'
    var anchor = 2
    var drawn = Maths.picture(svg, anchor, 0)
    var url = decodeURIComponent(/src="([^"]*)"/.exec(drawn)[1].replace("data:image/svg+xml,", ""))
    // The formula sits 15 viewBox units (7.5 px) above its baseline and 5 units (2.5 px) below, at a scale of 0.5 px per unit.
    check("the picture asks the aligned middle", /style="vertical-align: middle" \/>$/.test(drawn), true)
    check("the picture's own width is the formula's", /width="30"/.test(drawn), true)
    check("the picture is tall enough for the part above the baseline", /height="11"/.test(drawn), true)
    check("the picture's baseline sits at its centre plus the anchor", /viewBox="0 -15 60 22"/.test(url), true)
    check("the picture keeps its shape and ink", /<path d="M0 0"\/>/.test(url) && /height="11px"/.test(url), true)
    check("a short formula pads to the least height", /height="40"/.test(Maths.picture(svg, anchor, 40)), true)
    check("an svg without a size has no picture", Maths.picture("<svg><path/></svg>", anchor, 0), "")
    check("no svg has no picture", Maths.picture("", anchor, 0), "")
    check("a picture's url has no bare mark that ends a destination", /src="[^"]*[()']/.test(drawn), false)

    // The spans of a run are replaced in order, and a formula without a picture keeps its code span.
    var html = 'a <code data-math="inline" style="background-color:#181825">x</code> b <code data-math="inline">y</code> c'
    check("a run counts its inline spans", Maths.spans(html).length, 2)
    check("a drawn formula replaces its span", Maths.compose(html, ["<img>", ""]), 'a <img> b <code data-math="inline">y</code> c')
    check("a code span of ordinary code is not a formula", Maths.spans("a <code>x</code> b").length, 0)
}
