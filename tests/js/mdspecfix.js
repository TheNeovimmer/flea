.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MdInline.js" as Md
.import "../../ui/js/MdMath.js" as Maths
.import "sourcefixture.js" as Source
.import "../mdfence.js" as Fence

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
    check("an escaped dollar pair stays one text run", json("a \\$$x\\$$ b\n"), JSON.stringify([{ type: "run", text: "a &#36;$x&#36;$ b\n" }]))

    // The same run found these: fences, definitions, tables, autolinks and emphasis drawn against the spec.
    var fence = blocks("  ```\n  aaa\n aaa\n  ```\n")[0]
    check("a fence drops its opener's indent from each line", fence.text, "aaa\naaa")
    check("a fence left open holds no line for the final newline", blocks("```\naaa\n")[0].text, "aaa")
    check("a fence info string decodes escapes and references", blocks("``` f&ouml;o\\+bar\nx\n```\n")[0].info, "f\u00f6o+bar")
    check("a blank line inside indented code keeps its spaces", blocks("    a\n      \n    b\n")[0].text, "a\n  \nb")
    check("a fence in an item stays verbatim as a fence part", JSON.stringify(blocks("- a\n- ```sh\n  b *c*\n  ```\n")[0].parts[1]), JSON.stringify([{ type: "fence", text: "b *c*", info: "sh" }]))
    check("a quote inside an item is a quote part after its prose", JSON.stringify(blocks("- a\n  > q\n")[0].parts[0]), JSON.stringify([{ type: "run", text: "a" }, { type: "quote", text: "q" }]))
    check("a bullet change starts a list", blocks("- a\n+ b\n").length, 2)
    check("a delimiter change starts a list", blocks("1. a\n2) b\n").length, 2)
    check("a thematic break line keeps its marks", blocks("Foo\n***\nbar\n")[0].text, "Foo\n***\nbar\n")
    check("a table needs a delimiter row of the header's width", blocks("| a | b |\n| --- |\n| c |\n")[0].type, "run")
    check("a table row without a pipe stays in the table", blocks("| a |\n| --- |\n| b |\nc\n\nd\n")[0].rows.length, 2)
    check("a block start ends the table", blocks("| a |\n| --- |\n| b |\n> q\n").map(function (b) { return b.type }).join(","), "table,quote")
    check("a www address links through http", blocks("see www.example.com/x now\n")[0].text.indexOf("href=\"http://www.example.com/x\"") >= 0, true)
    check("an email autolink links through mailto", blocks("<a@b.example>\n")[0].text.indexOf("href=\"mailto:a@b.example\"") >= 0, true)
    check("a trailing entity stays out of a bare address", blocks("www.g.com/q?a=b&hl;\n")[0].text,
        "<a href=\"http://www.g.com/q?a=b\"><font color=\"#c0caf5\">www&#46;g&#46;com&#47;q&#63;a&#61;b</font></a>&hl;\n")
    check("a destination decodes escapes and references", blocks("[a](/f&ouml;\\*)\n")[0].text.indexOf("href=\"/f\u00f6*\"") >= 0, true)
    check("a label with an escaped bracket defines a reference", blocks("[a\\]b]: /u\n\n[a\\]b]\n")[0].text.indexOf("href=\"/u\"") >= 0, true)
    check("a title on the lines after a definition is hidden", blocks("[a]: /u\n  'title'\n\n[a]\n")[0].text.indexOf("title") < 0, true)
    check("an image alt reads its label as plain text", blocks("![foo *bar*][]\n\n[foo *bar*]: pic.png\n")[0].alt, "foo bar")
    check("a sharp s folds to ss in a label", blocks("[\u1e9e]\n\n[SS]: /u\n")[0].text.indexOf("href=\"/u\"") >= 0, true)
    check("emphasis follows the delimiter run rules", blocks("*foo **bar** baz*\n")[0].text, "<em>foo <strong>bar</strong> baz</em>\n")
    check("an unmatched mark stays literal as an entity", blocks("**foo*\n")[0].text, "&#42;<em>foo</em>\n")
    check("an underscore inside a word stays a plain character", blocks("R9_TAIL snake_case_name\n")[0].text, "R9_TAIL snake_case_name\n")
    check("an image in a link keeps the link syntax", blocks("[![m](pic.png)](/u)\n")[0].text, "[![m](file:///home/gm/notes/pic.png)](/u)\n")

    // Advloop round 1: code stays raw inside containers, footnotes number in reading order, the rest of the inline pass holds its edges.
    check("indented code in an item keeps its marks as a fence part", JSON.stringify(blocks("- item\n\n      def f(**kwargs): __init__\n")[0].parts[0]), JSON.stringify([{ type: "run", text: "item\n" }, { type: "fence", text: "def f(**kwargs): __init__", info: "" }]))
    check("indented code in an item keeps trailing spaces", blocks("- item\n\n      code  \n      more\n")[0].parts[0][1].text, "code  \nmore")
    check("indented code in a quote keeps its marks as a fence part", JSON.stringify(blocks("> quote\n>\n>     code **x**\n")[0].parts), JSON.stringify([{ type: "run", text: "quote\n" }, { type: "fence", text: "code **x**", info: "" }]))
    check("a citation before a link label numbers first", json("a[^x] and [b[^y]](https://e.x)\n\n[^x]: X\n[^y]: Y\n"), JSON.stringify([
        { type: "run", text: "a<sup>1</sup> and <a href=\"https://e.x\"><font color=\"#c0caf5\">b<sup>2</sup></font></a>\n\n" },
        { type: "run", text: "---" }, { type: "list", ordered: false, start: 0, items: ["<sup>1</sup> X", "<sup>2</sup> Y"] }]))
    check("an image alt never numbers a citation", json("![a[^x]](p.png) [^y]\n\n[^x]: X\n[^y]: Y\n").indexOf("<sup>2</sup> Y"), -1)
    check("the math span kind has one name", Md.MATH_SPAN, Md.spanIntervals("$x$")[3])
    check("an inline formula delimiter has a name", Maths.INLINE_DELIMITER_LENGTH, Md.spanIntervals("$x$")[2])
    check("a display formula delimiter is the interval's run length", Maths.DISPLAY_DELIMITER_LENGTH, Md.spanIntervals("$$x$$")[2])
    check("MdMath keeps no span kind of its own", /DISPLAY_KIND|MATH_KIND|spans\[k \+ 2\] === \d/.test(Source.source("ui/js/MdMath.js")), false)
    check("MdRun reads the span kind by name", /spans\[sp \+ 3\] === \d/.test(Source.source("ui/js/MdRun.js")), false)
    check("a formula's tail never opens a quote", json("$$x$$ > y\n"), JSON.stringify([
        { type: "figure", kind: "math", source: "x", display: true }, { type: "run", text: " &#62; y\n" }]))
    check("text after a mid-paragraph formula never opens a quote", json("a $$x$$ > b\n"), JSON.stringify([
        { type: "run", text: "a " }, { type: "figure", kind: "math", source: "x", display: true }, { type: "run", text: " &#62; b\n" }]))
    check("a quote mark in an item still opens a quote", JSON.stringify(blocks("- > q\n")[0].parts[0]), JSON.stringify([{ type: "quote", text: "q" }]))
    check("an angle destination never spans a line", blocks("[x](<a\\\nb>)\n")[0].text.indexOf("<a href"), -1)
    check("a destination with a backslash before a break is text", json("[x](<a\\\nb>)\n"), JSON.stringify([{ type: "run", text: "&#91;x&#93;(&#60;a<br />b&#62;)\n" }]))
    check("a title kept past a definition does not hide the next paragraph", json("intro\n\n[a]: /u\n'title'\n===\n"), JSON.stringify([{ type: "run", text: "intro\n\n===\n" }]))
    check("a link never spans a blank line", blocks("- [*x\n\n  y](u) *c*\n")[0].items[0], "&#91;&#42;x\n\ny&#93;(u) <em>c</em>")
    // A destination is decoded once, so the markdown written back for the renderer carries it escaped and never as a second decode.
    check("a linked image destination decodes exactly once", blocks("[![a](p.png)](a&amp;amp;b)\n")[0].text, "[![a](file:///home/gm/notes/p.png)](a&amp;amp;b)\n")
    var refused = ["&amp;#106;avascript:alert(1)", "javascript&amp;colon;alert(1)", "&amp;#x6a;avascript&amp;colon;alert(1)", "java&amp;Tab;script:alert(1)",
        "javascript&amp;amp;colon;alert(1)", "data&amp;colon;text/html,x"]
    for (var r = 0; r < refused.length; r++) {
        var hostile = blocks("[![a](p.png)](" + refused[r] + ")\n")
        check("a refused scheme never links through an image " + r, hostile.length === 1 && hostile[0].type === "run" && hostile[0].text.indexOf("](") < 0
            && hostile[0].text.indexOf("<a ") < 0, true)
    }

    // The security harness strips only what Qt draws as code, so an image beside a lookalike fence is still scanned.
    check("a backtick in the info string is no fence", Fence.withoutFences("```a`b\n![x](http://h/leak.png)\n```"), "```a`b\n![x](http://h/leak.png)\n")
    check("a closed fence is stripped whole", Fence.withoutFences("a\n```js\n![x](u)\n```\nb"), "a\n\nb")
    check("a longer fence closes only on a run as long", Fence.withoutFences("````\n```\n![x](u)\n````\nb"), "\nb")
    check("a tilde fence is stripped and holds backticks in its info", Fence.withoutFences("~~~ a`b\n![x](u)\n~~~\nb"), "\nb")
    check("an indented opener of three spaces is a fence", Fence.withoutFences("   ```\n![x](u)\n   ```\nb"), "\nb")
    check("a fence left open runs to the end", Fence.withoutFences("a\n```\n![x](u)"), "a\n")
    check("a closer with an info string is no closer", Fence.withoutFences("```\n```js\n![x](u)\n```\n![y](v)"), "\n![y](v)")
    check("a line that only starts with ticks is prose", Fence.withoutFences("```not a fence``` ![x](u)"), "```not a fence``` ![x](u)")

    // Part 2: no exception that is not a ruling. Front matter is a closed top block of YAML lines, and anything else is Markdown.
    check("a closed YAML block at the top is a code block", json("---\ntitle: A\ntags:\n  - b\n---\ntext\n"),
        JSON.stringify([{ type: "fence", text: "title: A\ntags:\n  - b", info: "" }, { type: "run", text: "text\n" }]))
    check("a dash line above a paragraph is a rule and a heading", json("---\nFoo\n---\nBar\n"), JSON.stringify([
        { type: "run", text: "---" }, { type: "heading", level: 2, text: "Foo" }, { type: "run", text: "Bar\n" }]))
    check("two dash lines are two rules", json("---\n---\n"), JSON.stringify([{ type: "run", text: "---\n---\n" }]))
    check("an unclosed YAML block is Markdown", json("---\ntitle: a\n"), JSON.stringify([{ type: "run", text: "---\ntitle: a\n" }]))
    check("a block with a line that is no YAML is Markdown", blocks("---\ntitle: a\nnot yaml\n---\n").map(function (b) { return b.type }).join(","), "run,heading")
    check("a thematic break ends the paragraph a setext underline closes", json("Foo\n***\nbar\n---\n"), JSON.stringify([
        { type: "run", text: "Foo\n***" }, { type: "heading", level: 2, text: "bar" }]))
    // A table keeps the header's width: extra cells go and short rows are padded.
    check("a ragged table drops extra cells and pads short rows", JSON.stringify(blocks("| a | b |\n| - | - |\n| 1 | 2 | 3 |\n| 4 |\n")[0].rows), JSON.stringify([["1", "2"], ["4", ""]]))
    // Character references decode here: Qt's own table is short and keeps a newline or a null reference as written.
    check("named, numeric, null and newline references decode", json("&copy; &#0; &#10;x &ngE; &nosuch; &amp;amp;\n"), JSON.stringify([
        { type: "run", text: "\u00a9 \ufffd  x \u2267\u0338 &nosuch; &#38;amp;\n" }]))
    check("a surrogate reference is the replacement character", blocks("&#xD800;\n")[0].text, "\ufffd\n")
    check("a reference in a destination decodes with the whole table", blocks("[a](/&Dcaron;)\n")[0].text.indexOf("href=\"/\u010e\"") >= 0, true)
    check("a raw del tag is written as the s tag Qt always draws struck", blocks("<del>*foo*</del> <strike>a</strike> <s>b</s>\n")[0].text, "<s><em>foo</em></s> <s>a</s> <s>b</s>\n")
    // A tab that only partly indents code inside a container leaves its remaining columns as spaces, whatever the importer counts.
    check("tabs in an item expand to their own stops", JSON.stringify(blocks("- foo\n\n\t\tbar\n")[0].parts[0]), JSON.stringify([{ type: "run", text: "foo\n" }, { type: "fence", text: "  bar", info: "" }]))
    check("tabs after a quote mark expand to their own stops", JSON.stringify(blocks(">\t\tfoo\n")[0].parts), JSON.stringify([{ type: "fence", text: "  foo", info: "" }]))
    check("tabs after a list marker expand to their own stops", JSON.stringify(blocks("-\t\tfoo\n")[0].parts[0]), JSON.stringify([{ type: "fence", text: "  foo", info: "" }]))
    // An item that opens on a blank line holds that one blank line and no more.
    check("a blank after an empty item ends its content", json("-\n\n  foo\n"), JSON.stringify([
        { type: "list", ordered: false, start: 0, items: [""] }, { type: "run", text: "  foo\n" }]))
    check("an empty item then a blank keeps the list going", blocks("-\n\n- b\n")[0].items.join("|"), "|b")
    check("a line right under an empty item still joins it", blocks("-\n  foo\n")[0].items[0], "foo")
    // A definition's label, destination and title may each spread over lines, and an inline destination may break after its parenthesis.
    check("a definition label spans two lines", blocks("[Foo\n  bar]: /url\n\n[Foo bar]\n")[0].text.indexOf("href=\"/url\"") >= 0, true)
    check("a definition title spans two lines", blocks("[foo]: /url '\ntitle\nline1\nline2\n'\n\n[foo]\n")[0].text.indexOf("line1"), -1)
    check("a definition with a title that breaks on a blank line is text", blocks("[foo]: /url 'title\n\nwith blank line'\n\n[foo]\n")[0].text.indexOf("&#91;foo&#93;: /url 'title") >= 0, true)
    check("a destination on the next line defines", blocks("[foo]:\n/url\n\n[foo]\n")[0].text.indexOf("href=\"/url\"") >= 0, true)
    check("an inline destination breaks after its parenthesis", blocks("[link](\n/uri\n\"title\")\n")[0].text.indexOf("href=\"/uri\"") >= 0, true)
    // A run of space references is one unit: dropped whole at a line start or end, otherwise one raw space, whatever its length.
    var spaceRef = "&#32;"
    var floodLength = 40
    check("a run of space references before a line break is no hard break", blocks("x" + spaceRef.repeat(3) + "\ny\n")[0].text, "x\ny\n")
    check("two space references before a line break are no hard break", blocks("a" + spaceRef.repeat(2) + "\nb\n")[0].text, "a\nb\n")
    check("a run of twelve space references opens no indented code", blocks(spaceRef.repeat(12) + "x\n")[0].text, "x\n")
    check("a run of forty space references opens no indented code", blocks(spaceRef.repeat(floodLength) + "x\n")[0].text, "x\n")
    check("a run of space references inside a line is one raw space", blocks("a" + spaceRef.repeat(floodLength) + "b\n")[0].text, "a b\n")
    check("a run of space references ends with the text", blocks("x" + spaceRef.repeat(floodLength))[0].text, "x")
    check("space and tab references join one run", blocks("x" + spaceRef + "&Tab;&#10;\ny\n")[0].text, "x\ny\n")
    // Literal spaces beside a run reach the parser too, so only the literal spaces after a line-end run decide a hard break.
    check("literal spaces before a line-end run are no hard break", blocks("x  " + spaceRef + "\ny\n")[0].text, "x\ny\n")
    check("one literal space after a line-end run is no hard break", blocks("x" + spaceRef + " \ny\n")[0].text, "x\ny\n")
    check("two literal spaces after a line-end run are a hard break", blocks("x" + spaceRef + "  \ny\n")[0].text, "x<br />y\n")
    check("a line-start run swallows the literal spaces after it", blocks(spaceRef + "    code\n")[0].text, "code\n")
    check("literal and reference spaces alternate into one line-end run", blocks("x " + (spaceRef + " ").repeat(floodLength) + "\ny\n")[0].text, "x\ny\n")
    // A line of only space references is not blank for Qt (it would split the paragraph), and draws nothing.
    var spaceLine = blocks("a\n" + spaceRef + "\nb\n")
    check("a line of one space reference keeps one paragraph", spaceLine.length + ":" + spaceLine[0].text.search(/\n[ \t]*\n/), "1:-1")
    var spaceBreak = blocks("a\n" + spaceRef + "  \nb\n")
    check("a space reference line with two spaces keeps one paragraph", spaceBreak.length + ":" + spaceBreak[0].text.search(/\n[ \t]*\n/), "1:-1")
    check("a space reference line with two spaces draws one line break", (spaceBreak[0].text.match(/<br \/>|\\\n|  \n/g) || []).length, 1)
    var spaceLines = blocks("a\n" + spaceRef.repeat(floodLength) + "\nb\n")
    check("a line of a space reference run keeps one paragraph", spaceLines.length + ":" + spaceLines[0].text.search(/\n[ \t]*\n/), "1:-1")
    // A paragraph continuation line keeps its leading spaces and is not code, so its space line stays whole however long its indent.
    var longIndent = 10
    var indentLine = blocks("a\n" + " ".repeat(longIndent) + spaceRef + "\nb\n")
    check("a long indented line of one space reference keeps one paragraph", indentLine.length + ":" + indentLine[0].text.search(/\n[ \t]*\n/), "1:-1")
    var indentFlood = blocks("a\n" + (" ".repeat(longIndent) + spaceRef.repeat(floodLength) + "\n").repeat(floodLength) + "b\n")
    check("long indented lines of a space reference run keep one paragraph", indentFlood.length + ":" + indentFlood[0].text.search(/\n[ \t]*\n/), "1:-1")
    // A label or an alt text is a fragment that starts mid-line, so its leading and trailing space references stay as one space.
    check("a space reference opens a link label", blocks("a[" + spaceRef + "b](u)\n")[0].text.indexOf("> b<") >= 0, true)
    check("a space reference closes a link label", blocks("[x" + spaceRef + "](u)\n")[0].text.indexOf(">x <") >= 0, true)
    check("a space reference opens an image alt text", blocks("![" + spaceRef + "b](u)\n")[0].alt, " b")
    check("a space reference closes an image alt text", blocks("![x" + spaceRef + "](u)\n")[0].alt, "x ")
    // An angle destination holds no unescaped "<", so the inline form is plain text like a definition's.
    check("an inline angle destination with a less-than is text", blocks("[a](<b<1>)\n")[0].text.indexOf("<a href"), -1)
}
