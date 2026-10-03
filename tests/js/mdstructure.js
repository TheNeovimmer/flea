.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MdInline.js" as MdInline
.import "../../ui/js/MdBlocks.js" as MdBlocks
.import "../../ui/js/MdContainer.js" as MdContainer
.import "../../ui/js/MdLeaf.js" as MdLeaf
.import "../../ui/js/MdRefs.js" as MdRefs

// Block-tree structure against CommonMark: fences, breaks, lists, footnotes, math, references and inline spans.
function run(check) {
    var dir = "/home/gm/notes"
    var chrome = "#181825"
    var ink = "#c0caf5"
    function kinds(doc) {
        return Markdown.blocks(doc, dir, chrome, ink).map(function (b) { return b.type }).join(",")
    }
    function styled(doc) {
        return Markdown.prepare(doc, dir, undefined, chrome, ink)
    }

    // R5 samples follow CommonMark 4.3 examples 92-94: lazy underlines are text unless they start a break.
    var r5Lazy = [
        { name: "example 92", source: "> Foo\n---", blocks: [{ type: "quote", text: "Foo" }, { type: "run", text: "---" }] },
        { name: "example 93", source: "> foo\nbar\n===", blocks: [{ type: "quote", text: "foo\nbar\n===" }] },
        { name: "example 94", source: "- Foo\n---", blocks: [{ type: "list", ordered: false, start: 0, items: ["Foo"] }, { type: "run", text: "---" }] },
        { name: "list equals", source: "- foo\nbar\n===", blocks: [{ type: "list", ordered: false, start: 0, items: ["foo\nbar\n==="] }] },
        { name: "quote short dash", source: "> foo\n--", blocks: [{ type: "quote", text: "foo\n--" }] },
        { name: "list short dash", source: "- foo\n--", blocks: [{ type: "list", ordered: false, start: 0, items: ["foo\n--"] }] }
    ]
    for (var lazyIndex = 0; lazyIndex < r5Lazy.length; lazyIndex++) {
        var lazyCase = r5Lazy[lazyIndex]
        check("R5 G1 " + lazyCase.name, JSON.stringify(Markdown.blocks(lazyCase.source, dir, chrome, ink)),
            JSON.stringify(lazyCase.blocks))
    }

    // R5 samples follow CommonMark 4.7: "[cover]:\n[cover].png" accepts the whole destination line.
    var r5Destinations = [
        { name: "bracket image", key: "cover", tail: "[cover].png", target: "[cover].png" },
        { name: "bracket label", key: "a", tail: "[b]", target: "[b]" },
        { name: "definition-shaped tail", key: "foo", tail: "[bar]: /url", target: "" },
        { name: "optional title", key: "cover", tail: '[cover].png "Cover"', target: "[cover].png" },
        { name: "trailing whitespace", key: "cover", tail: "[cover].png \t", target: "[cover].png" },
        { name: "text after title", key: "cover", tail: '[cover].png "Cover" extra', target: "" }
    ]
    var definitionSeparators = [" ", "\n"]
    for (var destinationIndex = 0; destinationIndex < r5Destinations.length; destinationIndex++) {
        var destinationCase = r5Destinations[destinationIndex]
        for (var separatorIndex = 0; separatorIndex < definitionSeparators.length; separatorIndex++) {
            var definitionSource = "[" + destinationCase.key + "]:" + definitionSeparators[separatorIndex] + destinationCase.tail
            var expectedDefinitions = {}
            if (destinationCase.target !== "")
                expectedDefinitions[destinationCase.key] = destinationCase.target
            var definitionLabel = "R5 G2 " + destinationCase.name + (definitionSeparators[separatorIndex] === "\n" ? " next line" : " same line")
            check(definitionLabel, JSON.stringify(Markdown.definitions(definitionSource)), JSON.stringify(expectedDefinitions))
            var definitionImage = Markdown.blocks(definitionSource + "\n\n![x][" + destinationCase.key + "]", dir, chrome, ink)
            check(definitionLabel + " image", definitionImage.some(function (block) { return block.type === "image" }), destinationCase.target !== "")
            if (destinationCase.target === "")
                check(definitionLabel + " stays paragraph", Markdown.blocks(definitionSource, dir, chrome, ink)[0].text,
                    definitionSource.replace(/\[/g, "&#91;").replace(/\]/g, "&#93;"))
        }
    }

    // R3 samples pin each container transition through the public block path for links and footnotes.
    var refCases = [
        { name: "document fence after list", source: "- parent\n```\n[img]: pic.png\n```", resolves: false },
        { name: "quoted list blank", source: "> - parent\n>\n>     [img]: pic.png", resolves: true },
        { name: "nested quote", source: "> > [img]: pic.png", resolves: true },
        { name: "list fence enters indented quote", source: "- ```\n  > code\n\n[img]: pic.png", resolves: true },
        { name: "list fence enters outside quote", source: "- ```\n> quote\n\n[img]: pic.png", resolves: true },
        { name: "quoted ordered item blank", source: "> 1.  item\n>\n>     [img]: pic.png", resolves: true },
        { name: "quoted list fence ends at sibling", source: "> - ```\n>   code\n> - [img]: pic.png", resolves: true },
        { name: "ordered tab continuation", source: "10. parent\n\n\t[img]: pic.png", resolves: true },
        { name: "unordered tab paragraph", source: "- parent\n\t[img]: pic.png", resolves: false },
        { name: "unordered tab continuation", source: "- parent\n\n\t[img]: pic.png", resolves: true },
        { name: "fence inside quoted list item", source: "- > ```\n  > [img]: pic.png\n  > ```", resolves: false },
        { name: "definition inside paragraph", source: "paragraph\n[img]: pic.png", resolves: false }
    ]
    for (var r = 0; r < refCases.length; r++) {
        var sample = refCases[r]
        var rendered = Markdown.blocks(sample.source + "\n\n![x][img]", dir, chrome, ink)
        check("R3 link " + sample.name, rendered.some(function (b) { return b.type === "image" }), sample.resolves)
        var noteSource = sample.source.replace("[img]: pic.png", "[^img]: Note.")
        var notes = Markdown.blocks(noteSource + "\n\nsee[^img]", dir, chrome, ink)
        check("R3 footnote " + sample.name,
            JSON.stringify(notes).indexOf("<sup>1</sup> Note.") >= 0, sample.resolves)
        if (sample.name === "document fence after list")
            check("R3 document fence keeps definition literal", rendered[1].text, "[img]: pic.png")
    }

    // R4 premise inputs share root mechanisms across md2a, md2b and md2c.
    var r4References = [
        { name: "md2a F31 md2c F23 unclosed pic angle", source: "[img]: <pic.png", target: "" },
        { name: "md2c F23 unclosed photo angle", source: "[img]: <photo.png", target: "" },
        { name: "angle control", source: "[img]: <pic.png>", target: "pic.png" },
        { name: "md2a F32 md2c F26 bare bracket", source: "[img]: [cover].png", target: "[cover].png" },
        { name: "bracket control", source: "[img]: <[cover].png>", target: "[cover].png" },
        { name: "bracket continuation destination", source: "[img]:\n  [cover].png", target: "[cover].png" },
        { name: "angle continuation rejection", source: "[img]:\n  <pic.png", target: "" },
        { name: "md2a F33 md2b F28 equals", source: "Title\n===\n[img]: pic.png", target: "pic.png" },
        { name: "md2a F33 single equals", source: "Title\n=\n[img]: pic.png", target: "pic.png" },
        { name: "md2c F24 equals", source: "Heading\n=======\n[img]: pic.png", target: "pic.png" },
        { name: "setext dash control", source: "Title\n---\n[img]: pic.png", target: "pic.png" },
        { name: "setext short dash", source: "Title\n--\n[img]: pic.png", target: "pic.png" },
        { name: "setext single dash", source: "Title\n-\n[img]: pic.png", target: "pic.png" },
        { name: "md2a F34 md2b F29 quote tab", source: "> \t> [img]: pic.png", target: "pic.png" },
        { name: "md2b F29 list tab", source: "> \t- [img]: pic.png", target: "pic.png" },
        { name: "quote space control", source: ">   > [img]: pic.png", target: "pic.png" },
        { name: "list space control", source: ">   - [img]: pic.png", target: "pic.png" },
        { name: "md2b F31 md2c F25 dash tab rule", source: "> -\t-\t-\n> [img]: pic.png", target: "pic.png" },
        { name: "md2b F31 star tab rule", source: "> *\t*\t*\n> [img]: pic.png", target: "pic.png" },
        { name: "underscore tab rule", source: "> _\t_\t_\n> [img]: pic.png", target: "pic.png" },
        { name: "tab rule trailing tab", source: "> -\t-\t-\t\n> [img]: pic.png", target: "pic.png" },
        { name: "tab rule space control", source: "> - - -\n> [img]: pic.png", target: "pic.png" }
    ]
    for (var referenceIndex = 0; referenceIndex < r4References.length; referenceIndex++) {
        var referenceCase = r4References[referenceIndex]
        var referenceSource = referenceCase.source + "\n\n![x][img]"
        check("R4 " + referenceCase.name + " definition",
            Markdown.definitions(referenceSource).img || "", referenceCase.target)
        var referenceBlocks = Markdown.blocks(referenceSource, dir, chrome, ink)
        check("R4 " + referenceCase.name + " image",
            referenceBlocks.some(function (block) { return block.type === "image" }), referenceCase.target !== "")
        if (referenceCase.name.indexOf("unclosed") >= 0)
            check("R4 " + referenceCase.name + " stays literal",
                (referenceBlocks[0].text || "").indexOf(referenceCase.source.slice("[img]: ".length).replace("<", "&#60;")) >= 0, true)
    }
    check("R4 angle cannot close on another line", MdRefs.readDefinitionTarget("<pic.png\n>"), "")
    var r4Underlines = ["=", "===", "--", "---"]
    for (var underlineIndex = 0; underlineIndex < r4Underlines.length; underlineIndex++) {
        var underline = r4Underlines[underlineIndex]
        // CommonMark example 93 keeps lazy underline text; examples 92 and 94 put the break outside.
        var expectedLazyText = underline === "---" ? "Title" : "Title\n" + underline
        var quoteUnderline = Markdown.blocks("> Title\n" + underline, dir, chrome, ink)
        check("R4 md2a F33 lazy quote " + underline, quoteUnderline[0].text, expectedLazyText)
        var listUnderline = Markdown.blocks("- Title\n" + underline, dir, chrome, ink)
        check("R4 md2a F33 lazy list " + underline, listUnderline[0].items[0], expectedLazyText)
    }
    var markerView = { at: 2, padding: 0, column: 2 }
    check("R4 md2a F34 quote uses absolute tab columns", MdContainer.quoteAt("> \t> text", markerView), 2)
    var tabListMarker = MdContainer.listAt("> \t- text", markerView)
    check("R4 md2b F29 list uses absolute tab columns", tabListMarker === null ? -1 : tabListMarker.indent, 2)
    check("R4 tab above marker indent stays code", MdContainer.quoteAt("\t> text", { at: 0, padding: 0, column: 0 }), -1)
    var ruleMarks = ["-", "*", "_"]
    var thematicMarkCount = 3
    for (var ruleIndex = 0; ruleIndex < ruleMarks.length; ruleIndex++) {
        var ruleText = ruleMarks[ruleIndex] + "\t" + ruleMarks[ruleIndex] + "\t" + ruleMarks[ruleIndex]
        check("R4 md2b F31 md2c F25 suffix " + ruleMarks[ruleIndex], MdBlocks.ruleSuffix("> " + ruleText).count, thematicMarkCount)
        check("R4 md2b F31 md2c F25 thematic " + ruleMarks[ruleIndex], MdLeaf.isThematic(ruleText), true)
    }
    var r4EmptyItems = [
        { name: "md2a F30 hidden first", source: "1. [img]: pic.png\n2. Visible", start: 1, ordered: true, items: ["", "Visible"] },
        { name: "md2b F30 empty first", source: "1. \n2. shown", start: 1, ordered: true, items: ["", "shown"] },
        { name: "md2b F30 second", source: "1. \n2. second", start: 1, ordered: true, items: ["", "second"] },
        { name: "md2c F27 hidden first", source: "5. [img]: pic.png\n6. next", start: 5, ordered: true, items: ["", "next"] },
        { name: "hidden bullet", source: "- [img]: pic.png\n- Visible", start: 0, ordered: false, items: ["", "Visible"] },
        { name: "empty bullet", source: "- \n- Visible", start: 0, ordered: false, items: ["", "Visible"] },
        { name: "bare ordered marker", source: "1.\n2. shown", start: 1, ordered: true, items: ["", "shown"] },
        { name: "bare bullet marker", source: "-\n- shown", start: 0, ordered: false, items: ["", "shown"] },
        { name: "hidden only item", source: "- [img]: pic.png", start: 0, ordered: false, items: [""] }
    ]
    for (var emptyIndex = 0; emptyIndex < r4EmptyItems.length; emptyIndex++) {
        var emptyCase = r4EmptyItems[emptyIndex]
        check("R4 " + emptyCase.name + " keeps authored rows",
            JSON.stringify(Markdown.blocks(emptyCase.source, dir, chrome, ink)),
            JSON.stringify([{ type: "list", ordered: emptyCase.ordered, start: emptyCase.start, items: emptyCase.items }]))
    }
    var lazyDefinitionSource = "- [img]:\npic.png\n  visible"
    check("R4 md2a F35 lazy hidden destination stays in item",
        JSON.stringify(Markdown.blocks(lazyDefinitionSource, dir, chrome, ink)),
        JSON.stringify([{ type: "list", ordered: false, start: 0, items: ["visible"] }]))
    var lazyState = MdBlocks.referenceState()
    var collectMembership = []
    var renderMembership = []
    function memberships(into) {
        return function (event) {
            into.push({ index: event.index, outer: event.outer === null ? null : event.outer.type })
        }
    }
    MdBlocks.blockPass(lazyDefinitionSource.split("\n"), lazyState, memberships(collectMembership), true)
    MdBlocks.blockPass(lazyDefinitionSource.split("\n"), lazyState, memberships(renderMembership), false)
    check("R4 md2a F35 collect render membership agrees", JSON.stringify(renderMembership), JSON.stringify(collectMembership))
    var continuedNote = "[^a]: first\n    second  \n    third\n\nsee[^a]"
    var expectedNote = "first\nsecond  \nthird"
    check("R4 md2a F36 continuation keeps hard break",
        MdBlocks.collectReferences(continuedNote).notes.a.text, expectedNote)
    var continuedNoteBlocks = Markdown.blocks(continuedNote, dir, chrome, ink)
    check("R4 md2a F36 rendered note keeps hard break", continuedNoteBlocks[2].items[0], "<sup>1</sup> " + expectedNote)

    var front = Markdown.blocks("---\ntitle: Hi\n---\n\nText\n", dir, chrome, ink)
    check("front matter draws as a fence", front.length === 2 && front[0].type === "fence", true)
    check("front matter keeps its lines", front[0].text, "title: Hi")
    check("no front matter means no fence", kinds("---\n"), "run")
    check("a setext underline stays a run", kinds("Title\n=====\n"), "run")
    check("a level-two setext stays a run", kinds("Title\n---\n"), "run")
    check("a thematic break stays prose", kinds("Text\n\n***\n\nMore\n"), "run")
    check("dashes break too", kinds("Text\n\n---\n\nMore\n"), "run")
    check("underscores break too", kinds("Text\n\n___\n\nMore\n"), "run")
    // RenderedPreviews draws a heading at its own size, so an ATX heading is a block of its own.
    var h2 = Markdown.blocks("## Second level ##\n", dir, chrome, ink)[0]
    check("an ATX heading is a heading block", h2.type, "heading")
    check("it carries its level", h2.level, 2)
    check("it drops the marker and the closing hashes", h2.text, "Second level")
    check("six hashes is the deepest heading", Markdown.blocks("###### Six\n", dir, chrome, ink)[0].level, 6)
    check("seven hashes is prose", kinds("####### Seven\n"), "run")
    check("a hash tag is prose", kinds("#hashtag\n"), "run")
    check("four spaces make code, not a heading", kinds("Text\n\n    # code\n"), "run,fence")
    check("an empty heading draws nothing", kinds("#\n\nText\n"), "run")
    check("a closing run glued to the text stays text",
        Markdown.blocks("# foo#\n", dir, chrome, ink)[0].text, "foo#")
    check("a heading ends a list it follows", kinds("- a\n- b\n# Next\n"), "list,heading")
    check("an indented hash inside an item stays item text", kinds("- a\n  # sub\n"), "list")
    check("a quoted hash stays in its quote", kinds("> # quoted\n"), "quote")
    check("a fenced hash stays code", kinds("```\n# not a heading\n```\n"), "fence")
    check("a heading keeps its inline code chip",
        Markdown.blocks("# The `foo` command\n", dir, chrome, ink)[0].text.indexOf('<code style="background-color:#181825">') >= 0, true)
    check("a numbered title stays literal text",
        Markdown.blocks("# 1. Intro\n", dir, chrome, ink)[0].text, "1&#46; Intro")
    check("a bullet-looking title stays literal text",
        Markdown.blocks("# - dash\n", dir, chrome, ink)[0].text, "&#45; dash")
    check("an emphasis title keeps its emphasis",
        Markdown.blocks("# _Hi_\n", dir, chrome, ink)[0].text, "_Hi_")
    check("spaced stars stay a thematic break", kinds("Text\n\n* * *\n\nMore\n"), "run")
    check("spaced dashes stay a thematic break", kinds("Text\n\n- - -\n\nMore\n"), "run")
    check("indented code draws verbatim", kinds("Text\n\n    var a = 1;\n\nMore\n"), "run,fence,run")
    var indented = Markdown.blocks("Text\n\n    var a = 1;\n", dir, chrome, ink)[1]
    check("indented code strips its indent", indented.text, "var a = 1;")
    check("indented code carries no info", indented.info, "")

    var mermaid = Markdown.blocks("```mermaid\ngraph TD\n```\n", dir, chrome, ink)[0]
    check("a mermaid fence becomes a figure", mermaid.type, "figure")
    check("a mermaid figure names its kind", mermaid.kind, "mermaid")
    var math = Markdown.blocks("```math\nx^2\n```\n", dir, chrome, ink)[0]
    check("a math fence becomes a figure", math.type, "figure")
    check("a math figure names its kind", math.kind, "math")
    check("a mermaid figure keeps its source", mermaid.source, "graph TD")
    check("a math figure keeps its source", math.source, "x^2")
    check("inline math styles as code",
        styled("See $x^2$ here.").indexOf('data-math="inline"') >= 0, true)
    check("a double-dollar span takes the inline math literal rendering",
        styled("See $$x^2$$ here.").indexOf('data-math="inline"') >= 0, true)
    check("a math span never resolves a URL",
        styled("See $![a](https://h.example.com/x.png)$ here.").indexOf("Remote image") < 0, true)
    check("a math span never resolves a link",
        styled("See $[a](https://h.example.com/x.png)$ here.").indexOf("<a") < 0, true)
    check("currency dollars stay prose", styled("costs $5 and $10 total"), "costs $5 and $10 total")
    check("math cannot open before whitespace", styled("$ x$"), "$ x$")
    check("math cannot close after whitespace", styled("$x $"), "$x $")
    check("math cannot close before a digit", styled("$x$2"), "$x$2")
    check("valid math still styles", styled("$x+1$"),
        '<code data-math="inline" style="background-color:#181825">x&#43;1</code>')
    check("math cannot pair across code", styled("$a `code` b$"),
        '$a <code style="background-color:#181825">code</code> b$')
    var codeDollars = MdInline.spanIntervals("x `$a` y `$b`")
    check("dollars inside code produce no math intervals", codeDollars.join(","), "2,6,1,0,9,13,1,0")
    check("math after code still styles", styled("`$x` then $y$"),
        '<code style="background-color:#181825">&#36;x</code> then '
        + '<code data-math="inline" style="background-color:#181825">y</code>')
    check("a closing run swallows the spans inside it", MdInline.spanIntervals("`a ``b`` c`").join(","), "0,11,1,0")
    check("math pairs on both sides of a code span", styled("$x$ `c` $y$"),
        '<code data-math="inline" style="background-color:#181825">x</code> '
        + '<code style="background-color:#181825">c</code> '
        + '<code data-math="inline" style="background-color:#181825">y</code>')
    check("backticks inside a closed span cannot open the next span", styled("`` ` `` and `x`"),
        '<code style="background-color:#181825">&#96;</code> and <code style="background-color:#181825">x</code>')
    check("an escaped dollar cannot open math", MdInline.spanIntervals("\\$x$").length, 0)
    check("an escaped dollar cannot close math", MdInline.spanIntervals("$x\\$").length, 0)
    check("an even backslash run leaves the dollar active", MdInline.spanIntervals("\\\\$x$").join(","), "2,5,1,1")
    check("an escaped opener stays literal", styled("\\$x$"), "&#36;x$")
    check("an escaped closer stays literal", styled("$x\\$"), "$x&#36;")

    var longContentLength = 1024
    var longTail = "&#;"
    var longContent = "a".repeat(longContentLength - longTail.length) + longTail
    var longEscaped = "a".repeat(longContentLength - longTail.length) + "&#38;&#35;&#59;"
    check("a 1024-character code span escapes each input character once", styled("`" + longContent + "`"),
        '<code style="background-color:#181825">' + longEscaped + '</code>')
    var shortTail = "a".repeat(longContentLength - 1 - longTail.length) + longTail
    check("a code span just under the long-text length escapes each input character once",
        styled("`" + shortTail + "`"), '<code style="background-color:#181825">'
        + "a".repeat(longContentLength - 1 - longTail.length) + "&#38;&#35;&#59;</code>")
    var everyAscii = ""
    for (var ascii = 1; ascii < 128; ascii++)
        everyAscii += String.fromCharCode(ascii)
    function entityOracle(text) {
        return text.replace(/[\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]/g, function (c) { return "&#" + c.charCodeAt(0) + ";" })
    }
    for (var padTo = longContentLength - 1; padTo <= longContentLength + 1; padTo++) {
        var padded = "a".repeat(padTo - everyAscii.length) + everyAscii
        check("every ASCII character escapes alike at length " + padTo,
            MdInline.escapeHtmlText(padded), entityOracle(padded))
    }
    var longTable = Markdown.blocks("| " + longContent + " |\n| --- |\n| " + longContent + " |\n", dir, chrome, ink)[0]
    check("a long table header escapes each input character once", longTable.head[0], longEscaped)
    check("a long table cell escapes each input character once", longTable.rows[0][0], longEscaped)

    // R5 F11 samples pin escaped final pipes with an optional closing delimiter and an even-backslash control.
    var finalPipeCases = [
        { name: "escaped without closing delimiter", source: "| a | b \\|", cells: ["a", "b |"], rendered: ["a", "b &#124;"] },
        { name: "escaped with closing delimiter", source: "| a | b \\| |", cells: ["a", "b |"], rendered: ["a", "b &#124;"] },
        { name: "even backslashes before delimiter", source: "| a | b \\\\|", cells: ["a", "b \\\\"], rendered: ["a", "b &#92;"] }
    ]
    for (var finalPipeIndex = 0; finalPipeIndex < finalPipeCases.length; finalPipeIndex++) {
        var finalPipeCase = finalPipeCases[finalPipeIndex]
        check("R5 F11 split " + finalPipeCase.name,
            JSON.stringify(MdLeaf.splitRow(finalPipeCase.source)), JSON.stringify(finalPipeCase.cells))
        var finalPipeTable = Markdown.blocks(finalPipeCase.source + "\n| --- | --- |\n" + finalPipeCase.source, dir, chrome, ink)[0]
        check("R5 F11 header " + finalPipeCase.name,
            JSON.stringify(finalPipeTable.head), JSON.stringify(finalPipeCase.rendered))
        check("R5 F11 body " + finalPipeCase.name,
            JSON.stringify(finalPipeTable.rows[0]), JSON.stringify(finalPipeCase.rendered))
    }

    var tasks = Markdown.blocks("- [ ] todo\n- [x] done\n", dir, chrome, ink)
    check("task items are one list", tasks.length === 1 && tasks[0].type === "list", true)
    check("an open task draws its box", tasks[0].items[0].indexOf("☐ todo") >= 0, true)
    check("a closed task draws its box", tasks[0].items[1].indexOf("☑ done") >= 0, true)
    var alert = Markdown.blocks("> [!NOTE]\n> Read this.\n", dir, chrome, ink)[0]
    check("an alert stays a quote", alert.type, "quote")
    check("an alert titles itself", alert.text.indexOf("**Note**") === 0, true)
    var warn = Markdown.blocks("> [!WARNING] Careful.\n", dir, chrome, ink)[0]
    check("a warning titles itself", warn.text.indexOf("**Warning**") === 0, true)

    check("R12 md2a F49 lowercase note title", Markdown.blocks("> [!note] Read this.", dir, chrome, ink)[0].text, "**Note** Read this.")
    check("R12 md2a F49 mixed warning title", Markdown.blocks("> [!wARNING] Careful.", dir, chrome, ink)[0].text, "**Warning** Careful.")

    var interruptionCases = [
        { source: "The year was\n1986. A great season.", expected: [{ type: "run", text: "The year was\n1986. A great season." }] },
        { source: "foo\n-", expected: [{ type: "run", text: "foo\n-" }] },
        { source: "foo\n1. item", expected: [{ type: "run", text: "foo" }, { type: "list", ordered: true, start: 1, items: ["item"] }] },
        { source: "foo\n1.", expected: [{ type: "run", text: "foo\n1." }] },
        { source: "foo\n+", expected: [{ type: "run", text: "foo\n+" }] },
        { source: "> foo\n1986. season", expected: [{ type: "quote", text: "foo\n1986. season" }] },
        { source: "- foo\n-", expected: [{ type: "list", ordered: false, start: 0, items: ["foo", ""] }] }
    ]
    for (var interruptIndex = 0; interruptIndex < interruptionCases.length; interruptIndex++) {
        var interruption = interruptionCases[interruptIndex]
        check("R12 md2a F50 paragraph interruption " + interruptIndex,
            JSON.stringify(Markdown.blocks(interruption.source, dir, chrome, ink)), JSON.stringify(interruption.expected))
    }
    var bareCases = [
        { source: "(see https://example.com/x.)", url: "https://example.com/x" },
        { source: "https://example.com/x).", url: "https://example.com/x" },
        { source: "https://example.com/x(foo).", url: "https://example.com/x(foo)" },
        { source: "(https://example.com/x(foo).)", url: "https://example.com/x(foo)" },
        { source: "https://example.com/x(foo)).)", url: "https://example.com/x(foo)" }
    ]
    for (var bareIndex = 0; bareIndex < bareCases.length; bareIndex++) {
        var bareCase = bareCases[bareIndex]
        check("R12 md2a F51 punctuation and parens " + bareIndex,
            MdInline.readBarelink(bareCase.source, bareCase.source.indexOf("https://")).url, bareCase.url)
        check("R12 md2a F51 emitted href " + bareIndex,
            styled(bareCase.source).indexOf('href="' + bareCase.url + '"') >= 0, true)
    }
    var citationCases = [
        { source: "Text[^b]\n\n[^a]: unused\n[^b]: used", body: "Text<sup>1</sup>\n", items: ["<sup>1</sup> used"] },
        { source: "Text[^b] then[^a] again[^b]\n\n[^a]: first definition\n[^b]: second definition",
            body: "Text<sup>1</sup> then<sup>2</sup> again<sup>1</sup>\n",
            items: ["<sup>1</sup> second definition", "<sup>2</sup> first definition"] },
        { source: "![x[^a]](pic.png) then[^b]\n\n[^a]: discarded\n[^b]: used",
            body: "![x&#91;&#94;a&#93;](file:///home/gm/notes/pic.png) then<sup>1</sup>\n", items: ["<sup>1</sup> used"] }
    ]
    for (var citationIndex = 0; citationIndex < citationCases.length; citationIndex++) {
        var citationCase = citationCases[citationIndex]
        var citationBlocks = Markdown.blocks(citationCase.source, dir, chrome, ink)
        check("R12 md2a F55 citation body " + citationIndex, citationBlocks[0].text, citationCase.body)
        check("R12 md2a F55 citation order " + citationIndex,
            JSON.stringify(citationBlocks[citationBlocks.length - 1].items), JSON.stringify(citationCase.items))
    }

    var foot = Markdown.blocks("Text[^a] here.\n\n[^a]: The note.\n", dir, chrome, ink)
    check("a footnote appends its list",
        foot.map(function (b) { return b.type }).join(","), "run,run,list")
    check("a footnote ref superscripts",
        foot[0].text.indexOf("<sup>1</sup>") >= 0, true)
    check("a footnote lists its number",
        foot[2].items[0].indexOf("<sup>1</sup> The note.") >= 0, true)
    var unused = Markdown.blocks("Text.\n\n[^b]: Never cited.\n", dir, chrome, ink)
    check("an uncited note renders nothing",
        unused.map(function (b) { return b.type }).join(","), "run")
    check("R2 raw list superscript never cites note",
        kinds("- x<sup>1</sup>\n\n[^a]: Unused note."), "list")
    check("R2 raw run superscript never cites note",
        kinds("x<sup>1</sup>\n\n[^a]: Unused note."), "run")
    check("R2 discarded image alt citation never adds note",
        kinds("- ![x[^a]](pic.png)\n\n[^a]: Unused note."), "list")
    var noteChain = Markdown.blocks("see[^a]\n\n[^a]: inner[^b]\n[^b]: child", dir, chrome, ink)
    check("R2 notes retain body-only citation selection", noteChain[2].items.length, 1)
    var listFoot = Markdown.blocks("- see[^a]\n\n[^a]: The note.\n", dir, chrome, ink)
    check("a note cited only in a list gets its definition",
        listFoot.map(function (b) { return b.type }).join(","), "list,run,list")
    check("a list-only note keeps its number and text",
        listFoot.length === 3 ? listFoot[2].items[0] : "", "<sup>1</sup> The note.")
    var nestedFoot = Markdown.blocks("1. parent\n   - see[^a]\n\n[^a]: Nested note.\n", dir, chrome, ink)
    check("a note cited only in a nested item gets its definition",
        nestedFoot.length === 3 ? nestedFoot[2].items[0] : "", "<sup>1</sup> Nested note.")
    var quoteFoot = Markdown.blocks("> see[^a]\n\n[^a]: Quote note.\n", dir, chrome, ink)
    check("a quote still includes its cited definition",
        quoteFoot.length === 3 ? quoteFoot[2].items[0] : "", "<sup>1</sup> Quote note.")
    var headingFoot = Markdown.blocks("# see[^a]\n\n[^a]: Heading note.\n", dir, chrome, ink)
    check("a note cited only in a heading gets its definition",
        headingFoot.map(function (b) { return b.type }).join(","), "heading,run,list")
    check("a heading-only note keeps its number and text",
        headingFoot.length === 3 ? headingFoot[2].items[0] : "", "<sup>1</sup> Heading note.")
    check("a literal superscript in a fence never cites a note",
        kinds("```\n<sup>1</sup>\n```\n\n[^a]: Never cited.\n"), "fence")

    check("an escaped bracket alt resolves",
        styled("![a\\]b](shot.png)").indexOf("![a&#93;b](file:///home/gm/notes/shot.png)") >= 0, true)
    check("nested brackets resolve",
        styled("![a [b] c](shot.png)").indexOf("![a &#91;b&#93; c](file:///home/gm/notes/shot.png)") >= 0, true)
    var multi = Markdown.prepare("![p][m]\n\n[m]:\n  shot.png\n", dir, undefined, chrome, ink)
    check("a multi-line definition resolves", multi.indexOf("![p](file:///home/gm/notes/shot.png)") >= 0, true)
    check("a multi-line definition leaves no line", multi.indexOf("[m]:") < 0, true)
    var spaced = Markdown.prepare("![p][q]\n\n[My  Id]: shot.png\n", dir, undefined, chrome, ink)
    check("an undefined label leaves its image unresolved", spaced.indexOf("![p](file:///home/gm/notes/shot.png)") < 0, true)
    var spacedHit = Markdown.prepare("![p][my id]\n\n[My  Id]: shot.png\n", dir, undefined, chrome, ink)
    check("a folded label resolves", spacedHit.indexOf("![p](file:///home/gm/notes/shot.png)") >= 0, true)
    var qdef = Markdown.prepare("> [qid]: shot.png\n\n![x][qid]\n", dir, undefined, chrome, ink)
    check("a definition in a quote resolves", qdef.indexOf("![x](file:///home/gm/notes/shot.png)") >= 0, true)
    var ldef = Markdown.prepare("- [lid]: shot.png\n\n![x][lid]\n", dir, undefined, chrome, ink)
    check("a definition in a list resolves", ldef.indexOf("![x](file:///home/gm/notes/shot.png)") >= 0, true)
    check("an angle target resolves",
        styled("![p](<my shot.png>)").indexOf("![p](file:///home/gm/notes/my%20shot.png)") >= 0, true)
    check("a titled target resolves",
        styled('![p](shot.png "t")').indexOf("![p](file:///home/gm/notes/shot.png)") >= 0, true)
    var targetScanLimit = 8192
    check("a title beyond the target scan limit stays literal",
        MdInline.readInlineTarget('(b "' + "x".repeat(targetScanLimit) + '")', 0), null)
    var titleUnit = "[a](b ("
    var titleRepeats = 3000
    var titleSamples = 16
    var titleReadsPerCharacter = 3
    var titleReadOverhead = 32
    var titleReadBudget = titleSamples * (titleReadsPerCharacter * targetScanLimit + titleReadOverhead)
    var titleCorpus = titleUnit.repeat(titleRepeats)
    var titleReads = 0
    var readLimitHit = {}
    var countedTitles = {
        length: titleCorpus.length,
        charAt: function (at) {
            titleReads++
            if (titleReads > titleReadBudget)
                throw readLimitHit
            return titleCorpus.charAt(at)
        },
        slice: function (from, to) { return titleCorpus.slice(from, to) }
    }
    try {
        for (var titleSample = 0; titleSample < titleSamples; titleSample++)
            MdInline.readInlineTarget(countedTitles, titleSample * titleUnit.length + "[a]".length)
    } catch (error) {
        if (error !== readLimitHit)
            throw error
    }
    check("repeated unclosed titles stay within the target operation budget", titleReads <= titleReadBudget, true)
    check("an entity URL resolves beside the file",
        styled("![p](sh&#111;t.png)").indexOf("file:///home/gm/notes/shot.png") >= 0, true)
    check("a percent URL resolves beside the file",
        styled("![p](%73hot.png)").indexOf("file:///home/gm/notes/shot.png") >= 0, true)

    check("a subfolder image stays local",
        styled("![p](img/shot.png)").indexOf("file:///home/gm/notes/img/shot.png") >= 0, true)
    check("a dotted path stays inside",
        styled("![p](img/../shot.png)").indexOf("file:///home/gm/notes/shot.png") >= 0, true)
    check("an escape above the folder drops to alt",
        styled("![p](../../shot.png)"), "p")
    check("an absolute path inside loads",
        styled("![p](/home/gm/notes/shot.png)").indexOf("file:///home/gm/notes/shot.png") >= 0, true)
    check("an absolute path outside drops to alt",
        styled("![p](/etc/passwd)"), "p")
    check("a file URL inside loads",
        styled("![p](file:///home/gm/notes/shot.png)").indexOf("file:///home/gm/notes/shot.png") >= 0, true)
    check("a file URL outside drops to alt",
        styled("![p](file:///etc/passwd)"), "p")
    check("a javascript URL never becomes a link",
        styled("See [x](javascript:alert(1)) here.").indexOf("<a") < 0, true)
    check("a data URL never becomes a link",
        styled("See [x](data:text/html,hi) here.").indexOf("<a") < 0, true)

    check("a www autolink wraps",
        styled("See www.example.com/x here.").indexOf("<a href=\"www.example.com/x\">") >= 0, true)
    check("a bare https autolink wraps",
        styled("See https://example.com/x here.").indexOf("<a href=\"https://example.com/x\">") >= 0, true)
    check("strikethrough passes through",
        styled("~~gone~~ here.").indexOf("~~gone~~") >= 0, true)

    check("script goes with its content",
        styled('A <script>alert(1)</script> B').indexOf("alert") < 0, true)
    check("style goes with its content",
        styled('A <style>p{color:red}</style> B').indexOf("color") < 0, true)
    check("bold survives", styled("A <b>loud</b> B").indexOf("<b>loud</b>") >= 0, true)
    check("a safe anchor keeps http",
        styled('A <a href="https://example.com/x">y</a> B').indexOf('href="https://example.com/x"') >= 0, true)
    check("an anchor loses javascript",
        styled('A <a href="javascript:alert(1)">y</a> B').indexOf("javascript") < 0, true)
    check("a table loses its background",
        styled('<table background="https://h.example.com/x.png"><tr><td>hi</td></tr></table>').indexOf("h.example.com") < 0, true)
    check("a style url never loads",
        styled('<div style="background:url(https://h.example.com/x.png)">hi</div>').indexOf("h.example.com") < 0, true)
    check("a comment never shows",
        styled("A <!-- secret --> B").indexOf("secret") < 0, true)
    check("a data image drops to alt",
        styled('A <img src="data:image/png;base64,AAA" alt="pic"> B').indexOf("data:") < 0, true)

    var trick = Markdown.blocks("1.  item\n\n    continued\n", dir, chrome, ink)
    check("a four-space continuation joins its item", trick.length === 1 && trick[0].type === "list", true)
    check("the trick keeps one item", trick[0].items.length, 1)
    check("the trick keeps both lines", trick[0].items[0].indexOf("continued") >= 0, true)
    check("an ordered list keeps its start", Markdown.blocks("3. a\n4. b\n", dir, chrome, ink)[0].start, 3)
    var lazy = Markdown.blocks("1. a\nlazy line\n2. b\n", dir, chrome, ink)[0]
    check("a lazy line joins its item", lazy.items[0].indexOf("lazy") >= 0, true)

    var latexFig = Markdown.blocks("```latex\nx^2\n```\n", dir, chrome, ink)[0]
    check("a latex fence becomes a figure", latexFig.type, "figure")
    check("a latex figure renders as math", latexFig.kind, "math")
    var loudFig = Markdown.blocks("```Mermaid\ngraph TD\n```\n", dir, chrome, ink)[0]
    check("a loud info still becomes a figure", loudFig.type, "figure")
    var jsFence = Markdown.blocks("```js\nvar a = 1;\n```\n", dir, chrome, ink)[0]
    check("a js fence stays a fence", jsFence.type, "fence")
    check("a figure kind reads off the info", Markdown.figureKind("mermaid"), "mermaid")
    check("latex reads as math", Markdown.figureKind("latex"), "math")
    check("an unknown info is no figure", Markdown.figureKind("js"), "")

    var dispOne = Markdown.blocks("$$\nx^2\n$$\n", dir, chrome, ink)[0]
    check("a display block becomes a figure", dispOne.type, "figure")
    check("a display block renders as math", dispOne.kind, "math")
    check("a display block keeps its source", dispOne.source, "x^2")
    var dispSolo = Markdown.blocks("$$x^2$$\n", dir, chrome, ink)[0]
    check("a solo display line becomes a figure", dispSolo.type, "figure")
    var displayTail = ["$$x$$ trailing text", "$$\nx\n$$ trailing text"]
    for (var tailIndex = 0; tailIndex < displayTail.length; tailIndex++) {
        check("md3u F1 display tail " + tailIndex,
            JSON.stringify(Markdown.blocks(displayTail[tailIndex], dir, chrome, ink)),
            JSON.stringify([{ type: "figure", kind: "math", source: "x", display: true },
                { type: "run", text: " trailing text" }]))
    }
    check("md3u F3 backtick heading stays literal", MdLeaf.headingSafe("```python"), "\\```python")
    check("md3u F3 tilde heading stays literal", MdLeaf.headingSafe("~~~python"), "\\~~~python")
    check("md3u F6 prices before maths pair only x", MdInline.spanIntervals("$5 and $10; $x$").join(","), "12,15,1,1")
    check("md3u F6 prices stay prose before maths", styled("$5 and $10; $x$"),
        '$5 and $10; <code data-math="inline" style="background-color:#181825">x</code>')
    var dispOpen = Markdown.blocks("$$\nx^2\n", dir, chrome, ink)
    check("an unterminated display stays prose", dispOpen.map(function (b) { return b.type }).join(","), "run")
    check("a figure source stays raw",
        Markdown.blocks("```mermaid\n$a [b](c)\n```\n", dir, chrome, ink)[0].source, "$a [b](c)")

    check("a spaced opener is no maths",
        styled("See $ x$ here.").indexOf('data-math="inline"') < 0, true)
    check("a spaced closer is no maths",
        styled("See $x $ here.").indexOf('data-math="inline"') < 0, true)
    check("a closer before a digit is no maths",
        styled("See $x$5 here.").indexOf('data-math="inline"') < 0, true)
    check("prices never become maths",
        styled("It costs $5 and $10 here.").indexOf('data-math="inline"') < 0, true)
    check("a lone dollar stays literal",
        styled("It costs $5 here.").indexOf('data-math="inline"') < 0, true)
    check("a tight pair stays maths",
        styled("See $x^2$ here.").indexOf('data-math="inline"') >= 0, true)
    var shallow = Markdown.blocks("1. a\n  - b", dir, chrome, ink)
    check("a marker below the content column starts another list",
        shallow.length === 2 && shallow[0].ordered && !shallow[1].ordered, true)
    check("a shallow marker keeps its item text", shallow.length === 2 ? shallow[1].items[0] : "", "b")
    var sibling = Markdown.blocks("- a\n - b\n  - c", dir, chrome, ink)
    check("a same-type marker below the content column is a sibling", sibling.length === 1 ? sibling[0].items.length : -1, 3)
    var outdent = Markdown.blocks("  1. a\n2. b", dir, chrome, ink)
    check("an outdented same-type marker stays in the list", outdent.length === 1 ? outdent[0].items.join("|") : "", "a|b")
    var child = Markdown.blocks("1. a\n   - b", dir, chrome, ink)
    check("a marker at the content column stays nested", child.length, 1)
    check("a nested marker keeps its dash", child[0].items[0], "a\n- b")

    // Reads are counted per character scanned, so the check holds on any machine and needs no clock.
    function countedScan(source) {
        var reads = 0
        var text = {
            length: source.length,
            charAt: function (at) { reads++; return source.charAt(at) },
            indexOf: function (needle, from) {
                var start = from === undefined ? 0 : from
                var hit = source.indexOf(needle, start)
                reads += (hit < 0 ? source.length - start : hit - start) + 1
                return hit
            }
        }
        MdInline.spanIntervals(text)
        return reads
    }
    var scanSmall = 65536
    var scanFactor = 8
    var scanMargin = 64
    var scanCorpora = { backtickRun: "`a`b", nestedRuns: "`a``b```c` ", mixedMath: "`a`$b$ ", escapedMath: "\\$a\\$ \\\\$b$ " }
    for (var corpusName in scanCorpora) {
        var corpus = scanCorpora[corpusName]
        var smallReads = countedScan(corpus.repeat(Math.ceil(scanSmall / corpus.length)))
        var largeReads = countedScan(corpus.repeat(Math.ceil(scanSmall * scanFactor / corpus.length)))
        check("the " + corpusName + " span scan is linear in reads", largeReads <= scanFactor * smallReads + scanMargin, true)
    }
}
