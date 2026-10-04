.import "../../ui/js/Markdown.js" as Markdown

// The parser defects the CommonMark and GFM conformance run (tests/markdown-spec.qml) found in GM's audit documents.
function run(check) {
    var dir = "/home/gm/notes"
    var chrome = "#181825"
    var ink = "#c0caf5"
    function blocks(doc) {
        return Markdown.blocks(doc, dir, chrome, ink)
    }
    function json(doc) {
        return JSON.stringify(blocks(doc))
    }

    // Setext headings are heading blocks, level 1 for "=" and 2 for "-", so they size like ATX headings.
    check("setext equals is a level 1 heading", json("Title\n=====\n"), JSON.stringify([{ type: "heading", level: 1, text: "Title" }]))
    check("setext dash is a level 2 heading", json("Title\n-----\n"), JSON.stringify([{ type: "heading", level: 2, text: "Title" }]))
    check("setext levels follow the underline", blocks("Title\n=====\n\nSub\n---\n").map(function (b) { return b.level }).join(","), "1,2")
    check("a setext heading spans its paragraph", json("a\nb\n===\n"), JSON.stringify([{ type: "heading", level: 1, text: "a\nb" }]))
    check("a quoted setext stays inside the quote", blocks("> Title\n> ---\n").map(function (b) { return b.type }).join(","), "quote")
    check("a setext heading follows a paragraph break", blocks("text\n\nTitle\n---\n").map(function (b) { return b.type }).join(","), "run,heading")

    // A nested quote is a block of its own at its depth, so the renderer never sees a literal marker.
    check("a nested quote splits by depth", json("> outer\n> > inner\n"),
        JSON.stringify([{ type: "quote", text: "outer" }, { type: "quote", text: "inner", depth: 2, joined: true }]))
    check("a three deep quote carries its depth", blocks("> > > deep\n")[0].depth, 3)
    check("no quote text keeps a literal marker", json("> a\n> > b\n> > > c\n").indexOf("&#62;"), -1)

    // A nested task item is an entry with the same box glyph a top-level item has.
    var tasks = blocks("- a\n  - [ ] open\n  - [x] done\n- [ ] top\n")[0]
    check("nested task items draw their boxes", JSON.stringify(tasks.items), JSON.stringify(["a", "☐ open", "☑ done", "☐ top"]))
    check("nested task items sit one level down", JSON.stringify(tasks.depths), "[0,1,1,0]")

    // A tight list has no gap at any depth; a blank line between items, or inside an item, loosens its own list only.
    var tight = blocks("- one\n- two\n  - nested\n    - deeper\n- three\n")[0]
    check("a tight nested list has no gap", (tight.gaps || []).indexOf(true), -1)
    check("a tight nested list flattens by depth", JSON.stringify([tight.items, tight.depths]),
        JSON.stringify([["one", "two", "nested", "deeper", "three"], [0, 0, 1, 2, 0]]))
    check("a blank between items loosens the list", JSON.stringify(blocks("- a\n\n- b\n")[0].gaps), "[true,true]")
    check("a blank inside an item loosens its list", JSON.stringify(blocks("- a\n\n  more\n- b\n")[0].gaps), "[true,true]")
    var loosenest = blocks("- a\n  - b\n\n  - c\n- d\n")[0]
    check("a loose nested list leaves its parent tight", JSON.stringify(loosenest.gaps), "[false,true,true,false]")
    check("a blank before a nested list loosens the parent", JSON.stringify(blocks("- a\n\n  - b\n- c\n")[0].gaps), "[true,false,true]")
    check("a simple list adds no model fields", json("- a\n- b\n"), JSON.stringify([{ type: "list", ordered: false, start: 0, items: ["a", "b"] }]))
    var mixed = blocks("1. a\n   - b\n   - c\n2. d\n")[0]
    check("a nested bullet list keeps the ordered numbering", JSON.stringify(mixed.markers), JSON.stringify(["1.", "•", "•", "2."]))
    check("a returning item continues without a marker", JSON.stringify(blocks("- a\n  - b\n\n  tail\n")[0].markers), JSON.stringify(["•", "•", ""]))

    // Inline maths: $..$ stays in the text as a marked span and is listed in order; $$..$$ inside a paragraph stands as a display figure.
    var inline = blocks("The identity $e^{i\\pi} + 1 = 0$ and $a^2$.\n")[0]
    check("inline maths are listed in order", JSON.stringify(inline.maths), JSON.stringify(["e^{i\\pi} + 1 = 0", "a^2"]))
    check("inline maths keep their marked spans", (inline.text.match(/data-math="inline"/g) || []).length, 2)
    check("costs in dollars are prose", blocks("costs $5 and $10\n")[0].maths, undefined)
    check("a display pair inside a paragraph is a figure", json("A sum: $$\\sum k$$ end.\n"), JSON.stringify([
        { type: "run", text: "A sum: " }, { type: "figure", kind: "math", source: "\\sum k", display: true }, { type: "run", text: " end.\n" }]))
    check("an escaped dollar pair stays text", blocks("a \\$$x\\$$ b\n")[0].type, "run")

    // The same run found these: fences, definitions, tables, autolinks and emphasis drawn against the spec.
    var fence = blocks("  ```\n  aaa\n aaa\n  ```\n")[0]
    check("a fence drops its opener's indent from each line", fence.text, "aaa\naaa")
    check("a fence left open holds no line for the final newline", blocks("```\naaa\n")[0].text, "aaa")
    check("a fence info string decodes escapes and references", blocks("``` f&ouml;o\\+bar\nx\n```\n")[0].info, "f\u00f6o+bar")
    check("a blank line inside indented code keeps its spaces", blocks("    a\n      \n    b\n")[0].text, "a\n  \nb")
    check("a fence in an item stays verbatim for the renderer", blocks("- a\n- ```sh\n  b *c*\n  ```\n")[0].items[1], "```sh\nb *c*\n```")
    check("a quote inside an item keeps its mark", blocks("- a\n  > q\n")[0].items[0], "a\n> q")
    check("a bullet change starts a list", blocks("- a\n+ b\n").length, 2)
    check("a delimiter change starts a list", blocks("1. a\n2) b\n").length, 2)
    check("a thematic break line keeps its marks", blocks("Foo\n***\nbar\n")[0].text, "Foo\n***\nbar\n")
    check("a table needs a delimiter row of the header's width", blocks("| a | b |\n| --- |\n| c |\n")[0].type, "run")
    check("a table row without a pipe stays in the table", blocks("| a |\n| --- |\n| b |\nc\n\nd\n")[0].rows.length, 2)
    check("a block start ends the table", blocks("| a |\n| --- |\n| b |\n> q\n").map(function (b) { return b.type }).join(","), "table,quote")
    check("a www address links through http", blocks("see www.example.com/x now\n")[0].text.indexOf("href=\"http://www.example.com/x\"") >= 0, true)
    check("an email autolink links through mailto", blocks("<a@b.example>\n")[0].text.indexOf("href=\"mailto:a@b.example\"") >= 0, true)
    check("a trailing entity stays out of a bare address", blocks("www.g.com/q?a=b&hl;\n")[0].text.indexOf("&hl</font>") >= 0, false)
    check("a destination decodes escapes and references", blocks("[a](/f&ouml;\\*)\n")[0].text.indexOf("href=\"/f\u00f6*\"") >= 0, true)
    check("a label with an escaped bracket defines a reference", blocks("[a\\]b]: /u\n\n[a\\]b]\n")[0].text.indexOf("href=\"/u\"") >= 0, true)
    check("a title on the lines after a definition is hidden", blocks("[a]: /u\n  'title'\n\n[a]\n")[0].text.indexOf("title") < 0, true)
    check("an image alt reads its label as plain text", blocks("![foo *bar*][]\n\n[foo *bar*]: pic.png\n")[0].alt, "foo bar")
    check("a sharp s folds to ss in a label", blocks("[\u1e9e]\n\n[SS]: /u\n")[0].text.indexOf("href=\"/u\"") >= 0, true)
    check("emphasis follows the delimiter run rules", blocks("*foo **bar** baz*\n")[0].text, "<em>foo <strong>bar</strong> baz</em>\n")
    check("an unmatched mark stays literal as an entity", blocks("**foo*\n")[0].text, "&#42;<em>foo</em>\n")
    check("an underscore inside a word stays a plain character", blocks("R9_TAIL snake_case_name\n")[0].text, "R9_TAIL snake_case_name\n")
    check("an image in a link keeps the link syntax", blocks("[![m](pic.png)](/u)\n")[0].text.indexOf("<a ") < 0, true)
}
