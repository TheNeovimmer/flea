.import "../../ui/js/Markdown.js" as Markdown

// Block-tree structure against CommonMark's rules: front matter, setext,
// breaks, indented code, alerts, footnotes, task items, math/mermaid hooks,
// reference variants, autolinks and the list-indent trick.
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
    check("display math styles as code",
        styled("See $$x^2$$ here.").indexOf('data-math="inline"') >= 0, true)
    check("a math span never resolves a URL",
        styled("See $[a](https://h.example.com/x.png)$ here.").indexOf("Remote image") < 0, true)

    var tasks = Markdown.blocks("- [ ] todo\n- [x] done\n", dir, chrome, ink)
    check("task items are one list", tasks.length === 1 && tasks[0].type === "list", true)
    check("an open task draws its box", tasks[0].items[0].indexOf("☐ todo") >= 0, true)
    check("a closed task draws its box", tasks[0].items[1].indexOf("☑ done") >= 0, true)
    var alert = Markdown.blocks("> [!NOTE]\n> Read this.\n", dir, chrome, ink)[0]
    check("an alert stays a quote", alert.type, "quote")
    check("an alert titles itself", alert.text.indexOf("**Note**") === 0, true)
    var warn = Markdown.blocks("> [!WARNING] Careful.\n", dir, chrome, ink)[0]
    check("a warning titles itself", warn.text.indexOf("**Warning**") === 0, true)

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

    check("an escaped bracket alt resolves",
        styled("![a\\]b](shot.png)").indexOf("![a&#93;b](file:///home/gm/notes/shot.png)") >= 0, true)
    check("nested brackets resolve",
        styled("![a [b] c](shot.png)").indexOf("![a &#91;b&#93; c](file:///home/gm/notes/shot.png)") >= 0, true)
    var multi = Markdown.prepare("![p][m]\n\n[m]:\n  shot.png\n", dir, undefined, chrome, ink)
    check("a multi-line definition resolves", multi.indexOf("![p](file:///home/gm/notes/shot.png)") >= 0, true)
    check("a multi-line definition leaves no line", multi.indexOf("[m]:") < 0, true)
    var spaced = Markdown.prepare("![p][q]\n\n[My  Id]: shot.png\n", dir, undefined, chrome, ink)
    check("labels fold case and whitespace", spaced.indexOf("![p](file:///home/gm/notes/shot.png)") < 0, true)
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
}
