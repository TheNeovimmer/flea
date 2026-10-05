.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MdChunks.js" as Chunks
.import "../../ui/js/MarkdownLists.js" as Lists

// What an item or a quote holds besides prose: each block kind arrives as its own part, drawn with its top-level recipe.
function run(check) {
    var dir = "/home/gm/notes"
    var chrome = "#181825"
    var ink = "#c0caf5"
    function blocks(doc) {
        return Markdown.blocks(doc, dir, chrome, ink)
    }
    function kinds(list) {
        return list.map(function (b) { return b.type }).join(",")
    }
    function partsOf(block, k) {
        return block.parts !== undefined && block.parts[k] ? block.parts[k] : []
    }
    // One field of the part at index, "" when there is none, so a missing part fails its check rather than the suite.
    function field(parts, index, name) {
        return parts[index] !== undefined ? parts[index][name] : ""
    }
    // A fake font: every character is 8 px wide, a bullet included.
    var CHAR_PX = 8
    var GAP = 6
    function advance(text) { return String(text).length * CHAR_PX }

    // A fenced block in an item is a fence part with its info, in order with the item's prose.
    var fenced = blocks("- item\n  ```js\n  var a = 1;\n  ```\n  tail\n")[0]
    check("an item with a fence holds its blocks as parts", kinds(partsOf(fenced, 0)), "run,fence,run")
    check("the item's fence part carries its source and info", JSON.stringify([field(partsOf(fenced, 0), 1, "text"), field(partsOf(fenced, 0), 1, "info")]), JSON.stringify(["var a = 1;", "js"]))
    check("an item with parts keeps no text of its own", fenced.items[0], "")
    var quoted = blocks("> q\n> ```js\n> x\n> ```\n")[0]
    check("a quote with a fence holds its blocks as parts", kinds(quoted.parts || []), "run,fence")
    check("the quote's fence part carries its source and info", JSON.stringify([field(quoted.parts || [], 1, "text"), field(quoted.parts || [], 1, "info")]), JSON.stringify(["x", "js"]))
    check("a quote with parts keeps no text of its own", quoted.text, "")

    // Prose alone stays one text, so a plain item or quote builds no parts.
    var plain = blocks("- a\n- b\n\n> q\n> r\n")
    check("a plain list carries no parts", plain[0].parts, undefined)
    check("a plain quote carries no parts", plain[1].parts, undefined)

    // Every other kind nests: indented code, a table, a heading, display maths, a quote in an item.
    check("indented code in a quote is a fence part", kinds(blocks(">     foo\n")[0].parts || []), "fence")
    check("a table in a quote is a table part", kinds(blocks("> | a | b |\n> | - | - |\n> | 1 | 2 |\n")[0].parts || []), "table")
    check("a table in an item is a table part", kinds(partsOf(blocks("- | a | b |\n  | - | - |\n  | 1 | 2 |\n")[0], 0)), "table")
    check("a heading in a quote is a heading part", kinds(blocks("> # Title\n> body\n")[0].parts || []), "heading,run")
    check("a quote in an item is a quote part", kinds(partsOf(blocks("- a\n  > b\n")[0], 0)), "run,quote")
    var itemQuote = partsOf(blocks("- a\n  > b\n  >\n  > c\n")[0], 0)[1]
    check("a second paragraph in a quote in an item stays in that quote", itemQuote !== undefined && itemQuote.type === "quote" && itemQuote.text.indexOf("c") >= 0, true)
    check("a list in a quote is a list part", kinds(blocks("> - a\n> - b\n> ```\n> x\n> ```\n")[0].parts || []), "list,fence")
    check("an empty fence in a quote is an empty fence part", JSON.stringify(blocks("> ```\n")[0].parts || []), JSON.stringify([{ type: "fence", text: "", info: "" }]))

    // Inline and display maths in an item or quote draw as in a paragraph: the run carries its formulas, a display formula is a figure part.
    var inlineItem = blocks("- see $x^2$ here\n")[0]
    check("an item with an inline formula holds a run with maths", JSON.stringify(partsOf(inlineItem, 0).map(function (p) { return [p.type, p.maths] })), JSON.stringify([["run", ["x^2"]]]))
    var inlineQuote = blocks("> see $y$ here\n")[0]
    check("a quote with an inline formula holds a run with maths", JSON.stringify((inlineQuote.parts || []).map(function (p) { return [p.type, p.maths] })), JSON.stringify([["run", ["y"]]]))
    var display = partsOf(blocks("- a\n  $$\n  y\n  $$\n")[0], 0)
    check("a display formula in an item is a figure part", JSON.stringify(display.map(function (p) { return p.type + ":" + (p.kind || "") + ":" + (p.display === true) })), JSON.stringify(["run::false", "figure:math:true"]))

    // Parts share the document's references and footnotes, so a link or a note cited inside one resolves.
    var linked = partsOf(blocks("- [a]\n  ```\n  x\n  ```\n\n[a]: /url\n")[0], 0)
    check("a link inside a part uses the document's definitions", linked.length > 0 && linked[0].text.indexOf("href=\"/url\"") >= 0, true)
    var noted = blocks("- a[^1]\n  ```\n  x\n  ```\n\n[^1]: the note\n")
    check("a note cited inside a part reaches the footnote list", noted.length > 1 && noted[noted.length - 1].items[0].indexOf("the note") >= 0, true)

    // A long run of fenced items stays a bounded number of blocks, one fence part each.
    var many = []
    for (var i = 0; i < 300; i++)
        many.push("- item " + i + "\n  ```\n  code " + i + "\n  ```")
    var long = blocks(many.join("\n") + "\n")
    var fences = 0
    for (var b = 0; b < long.length; b++)
        for (var k = 0; k < long[b].items.length; k++)
            fences += partsOf(long[b], k).filter(function (p) { return p.type === "fence" }).length
    check("a pathological list of fenced items keeps one fence part per item", fences, 300)

    // A chunk keeps each of its arrays on its own: a loose flat list keeps its gaps, a nested one without gaps does not throw.
    var gapsOnly = { type: "list", ordered: false, start: 0, items: [], gaps: [] }
    var depthsOnly = { type: "list", ordered: false, start: 0, items: [], depths: [], markers: [] }
    for (var n = 0; n < 40; n++) {
        gapsOnly.items.push("i" + n)
        gapsOnly.gaps.push(n % 2 === 0)
        depthsOnly.items.push("i" + n)
        depthsOnly.depths.push(0)
        depthsOnly.markers.push("•")
    }
    var gapChunks = Chunks.chunkList(gapsOnly)
    check("a loose flat list keeps its gaps in every chunk", JSON.stringify(gapChunks.map(function (c) { return c.gaps === undefined ? -1 : c.gaps.length })), "[32,8]")
    var thrown = ""
    var depthChunks = []
    try {
        depthChunks = Chunks.chunkList(depthsOnly)
    } catch (e) {
        thrown = String(e)
    }
    check("a nested list without gaps chunks without throwing", thrown, "")
    check("a nested list without gaps keeps its depths in every chunk", JSON.stringify(depthChunks.map(function (c) { return c.depths === undefined ? -1 : c.depths.length })), "[32,8]")

    // The nested bullet at the seam keeps the text column its parent has in the first chunk.
    var seam = []
    for (var s = 1; s <= 40; s++)
        seam.push(s + ". item" + (s === 32 ? "\n    - child" : ""))
    var seamChunks = blocks(seam.join("\n") + "\n")
    var firstCells = Lists.layout(seamChunks[0], advance, GAP)
    var parentCell = firstCells[firstCells.length - 1]
    var carried = Lists.layout(seamChunks[1], advance, GAP)
    check("the seam fixture's second chunk opens on the nested bullet", seamChunks[1].depths[0], 1)
    check("a nested entry at the seam starts at the parent's text column in the first chunk", carried[0].x, parentCell.x + parentCell.w + GAP)

    // A loose list keeps the paragraph gap before the first entry of a later chunk.
    var loose = []
    for (var l = 1; l <= 40; l++)
        loose.push("- item " + l + "\n")
    var looseChunks = blocks(loose.join("\n") + "\n")
    check("a loose list splits in chunks", looseChunks.length, 2)
    check("the first entry of the first chunk has no gap above it", Lists.layout(looseChunks[0], advance, GAP)[0].gap, false)
    check("the first entry of a later chunk keeps its gap above it", Lists.layout(looseChunks[1], advance, GAP)[0].gap, true)

    // An item or a quote gets what a top-level block gets from the HTML, picture and entity handling, so each form below lands the same as outside.
    function held(doc) {
        var first = blocks(doc)[0]
        return first.type === "quote" ? (first.parts || []) : partsOf(first, 0)
    }
    // The prose of an item or quote that holds only a text, so a form that was split into parts shows as empty.
    function textOf(doc) {
        var first = blocks(doc)[0]
        return first.type === "quote" ? first.text : first.items[0]
    }
    function kindsOf(doc) {
        return kinds(held(doc))
    }
    var HTML_FORMS = [["an item", function (doc) { return "- " + doc.split("\n").join("\n  ") }], ["a quote", function (doc) { return "> " + doc.split("\n").join("\n> ") }]]
    HTML_FORMS.forEach(function (form) {
        var at = form[0]
        var wrap = form[1]
        check(at + " holding only a picture draws an image part", JSON.stringify(held(wrap("![a](pic.png)")).map(function (p) { return [p.type, p.url] })), JSON.stringify([["image", "file:///home/gm/notes/pic.png"]]))
        var row = held(wrap('<p align="center"><img src="a.png"> <img src="b.png" width="40"></p>'))
        check(at + " holding a badge row draws one images part, centred", JSON.stringify(row.map(function (p) { return [p.type, p.align, p.items.length, p.items[1].width] })), JSON.stringify([["images", "center", 2, 40]]))
        check(at + " holding a raw picture keeps its width", JSON.stringify(held(wrap('<img src="a.png" width="40">')).map(function (p) { return [p.type, p.width] })), JSON.stringify([["image", 40]]))
        check(at + " collapses a soft break after a line break", textOf(wrap("one<br />\n  two")), "one<br />two")
        check(at + " starts a block-level raw tag after a blank line as its own run", kindsOf(wrap("Body.\n\n<div>x</div>")), "run,run")
        var figure = held(wrap("See text\n```mermaid\ngraph TD\n```"))
        check(at + " draws a mermaid fence as a display figure part", JSON.stringify(figure.map(function (p) { return [p.type, p.kind, p.display] })), JSON.stringify([["run", undefined, undefined], ["figure", "mermaid", true]]))
    })
}
