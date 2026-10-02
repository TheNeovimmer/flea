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
    check("indented code draws verbatim", kinds("Text\n\n    var a = 1;\n\nMore\n"), "run,fence,run")
    var indented = Markdown.blocks("Text\n\n    var a = 1;\n", dir, chrome, ink)[1]
    check("indented code strips its indent", indented.text, "var a = 1;")
    check("indented code carries no info", indented.info, "")

    var mermaid = Markdown.blocks("```mermaid\ngraph TD\n```\n", dir, chrome, ink)[0]
    check("a mermaid fence keeps its info", mermaid.info, "mermaid")
    var math = Markdown.blocks("```math\nx^2\n```\n", dir, chrome, ink)[0]
    check("a math fence keeps its info", math.info, "math")
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
}
