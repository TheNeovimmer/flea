.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MdInline.js" as MdInline

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

    var front = Markdown.blocks("---\ntitle: Hi\n---\n\nText\n", dir, chrome, ink)
    check("front matter draws as a fence", front.length === 2 && front[0].type === "fence", true)
    check("front matter keeps its lines", front[0].text, "title: Hi")
    check("no front matter means no fence", kinds("---\n"), "run")
    check("a setext underline stays a run", kinds("Title\n=====\n"), "run")
    check("a level-two setext stays a run", kinds("Title\n---\n"), "run")
    check("a thematic break stays prose", kinds("Text\n\n***\n\nMore\n"), "run")
    check("dashes break too", kinds("Text\n\n---\n\nMore\n"), "run")
    check("underscores break too", kinds("Text\n\n___\n\nMore\n"), "run")
    check("spaced stars stay a thematic break", kinds("Text\n\n* * *\n\nMore\n"), "run")
    check("spaced dashes stay a thematic break", kinds("Text\n\n- - -\n\nMore\n"), "run")
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
    check("a double-dollar span takes the inline math literal rendering",
        styled("See $$x^2$$ here.").indexOf('data-math="inline"') >= 0, true)
    check("a math span never resolves a URL",
        styled("See $![a](https://h.example.com/x.png)$ here.").indexOf("Remote image") < 0, true)
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
    var scanCorpora = { backtickRun: "`a`b", nestedRuns: "`a``b```c` ", mixedMath: "`a`$b$ " }
    for (var corpusName in scanCorpora) {
        var corpus = scanCorpora[corpusName]
        var smallReads = countedScan(corpus.repeat(Math.ceil(scanSmall / corpus.length)))
        var largeReads = countedScan(corpus.repeat(Math.ceil(scanSmall * scanFactor / corpus.length)))
        check("the " + corpusName + " span scan is linear in reads", largeReads <= scanFactor * smallReads + scanMargin, true)
    }
}
