.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MdInline.js" as Inline
.import "../../ui/js/MdLink.js" as Link
.import "../../ui/js/MdLeaf.js" as Leaf
.import "sourcefixture.js" as Source
.import "../markdown-board.js" as Board

function run(check) {
    var quickLook = Source.slice(Source.source("ui/Preview.qml"), "id: markdownLoader", "item.closeRequested.connect")
    var activeAt = quickLook.indexOf("item.active =")
    check("Quick Look Markdown activation exists", activeAt >= 0, true)
    var readerInputs = ["path", "size", "maxBytes", "truncate"]
    for (var inputIndex = 0; inputIndex < readerInputs.length; inputIndex++) {
        var input = readerInputs[inputIndex]
        var bindingAt = quickLook.indexOf("item." + input + " =")
        check("Quick Look Markdown binds " + input + " before activation",
            bindingAt >= 0 && bindingAt < activeAt, true)
    }

    var loadBody = Source.slice(Source.source("tests/markdown-render.qml"),
        "if (shell.loadStep < shell.loadCases.length) {", "if (shell.fixture.length === 0)")
    var settleLoad = new Function("shell", "md", "settle", "Board", loadBody)
    function loadMock(text, fresh) {
        var before = 7
        var shell = { loadStep: 1, loadSeq: before, fixture: "/notes.md", loadFailures: [],
            loadCases: [{ text: "", suffix: ".empty" }, { text: text, suffix: ".second" }, { text: "", suffix: ".last" }],
            log: function () {}, fail: function (why) { this.failure = why }, failure: "" }
        var md = { contentReady: true, rawText: text, status: "ready", parseSeq: before + (fresh ? 1 : 0),
            appliedSeq: before + (fresh ? 1 : 0), path: "/notes.md.first" }
        settleLoad(shell, md, { restart: function () {} }, Board)
        return shell
    }
    check("stale identical load is rejected", loadMock("# Identical\n", false).failure.length > 0, true)
    check("stale empty load is rejected", loadMock("", false).failure.length > 0, true)
    check("stale load is not counted as a completion", loadMock("", false).loadStep, 1)
    check("fresh identical load is counted", loadMock("# Identical\n", true).loadStep, 2)
    check("fresh empty load is counted", loadMock("", true).loadStep, 2)

    check("rendered and source are the only views", Markdown.isView("rendered") && Markdown.isView("source"), true)
    check("a hand edit is not a view", Markdown.isView("html"), false)
    check("an empty stored value is not a view", Markdown.isView(""), false)
    check("rendered toggles to source", Markdown.toggled("rendered"), "source")
    check("source toggles to rendered", Markdown.toggled("source"), "rendered")

    check("https is remote", Markdown.isRemoteUrl("https://cdn.example.com/a.png"), true)
    check("http is remote", Markdown.isRemoteUrl("http://cdn.example.com/a.png"), true)
    check("a protocol-relative URL is remote", Markdown.isRemoteUrl("//cdn.example.com/a.png"), true)
    check("a bare filename is not remote", Markdown.isRemoteUrl("shot.png"), false)
    check("a data URI is not remote", Markdown.isRemoteUrl("data:image/png;base64,AAA"), false)
    check("the host is the host alone", Markdown.hostOf("https://cdn.example.com:8080/a.png?x=1"), "cdn.example.com")
    check("a userinfo is not the host", Markdown.hostOf("https://user@cdn.example.com/a.png"), "cdn.example.com")
    check("the placeholder names the host", Markdown.placeholder("cdn.example.com"),
        "Remote image not loaded \u00b7 cdn.example.com")

    var dir = "/home/gm/notes"
    var local = Markdown.classifyImage("shot.png", dir)
    check("a bare filename loads beside the file", local.kind, "local")
    check("a bare filename resolves under the file", local.url, "file:///home/gm/notes/shot.png")
    check("a ./ filename loads beside the file", Markdown.classifyImage("./shot.png", dir).kind, "local")
    check("a remote URL never loads", Markdown.classifyImage("https://cdn.example.com/a.png", dir).kind, "remote")
    check("a remote URL keeps its host", Markdown.classifyImage("https://cdn.example.com/a.png", dir).host, "cdn.example.com")
    check("an absolute path never loads", Markdown.classifyImage("/etc/passwd", dir).kind, "dropped")
    check("a subfolder beside the file loads", Markdown.classifyImage("img/shot.png", dir).kind, "local")
    check("a subfolder resolves under the file", Markdown.classifyImage("img/shot.png", dir).url,
        "file:///home/gm/notes/img/shot.png")
    check("a dotted subpath stays inside", Markdown.classifyImage("img/../shot.png", dir).kind, "local")
    check("a parent escape never loads", Markdown.classifyImage("../shot.png", dir).kind, "dropped")
    check("a data URI never loads", Markdown.classifyImage("data:image/png;base64,AAA", dir).kind, "dropped")
    check("an empty target never loads", Markdown.classifyImage("", dir).kind, "dropped")

    check("R2 root parent clamps and refuses outside", Markdown.classifyImage("/etc/x.png", "/../docs").kind, "dropped")
    check("R2 root parent clamps private outside", Markdown.classifyImage("/etc/private.png", "/../docs").kind, "dropped")
    check("R2 root parent allows inside", Markdown.classifyImage("/docs/a.png", "/../docs").url, "file:///docs/a.png")
    check("R2 root folder contains children", Markdown.classifyImage("/pic.png", "/").url, "file:///pic.png")
    check("R2 empty folder means root", Markdown.classifyImage("pic.png", "").url, "file:///pic.png")
    var rootImage = Markdown.blocks("![x](pic.png)", Markdown.dirOf("/README.md"))
    check("R2 root document renders image", rootImage[0].type, "image")
    check("R2 root document image URL", rootImage[0].url, "file:///pic.png")
    check("R2 invalid folder fails closed", Markdown.classifyImage("/pic.png", "/docs\\bad").kind, "dropped")

    var spare = "# Notes\n\n![demo](https://cdn.example.com/demo.png)\n\n![local](shot.png)\n"
    var prepared = Markdown.prepare(spare, dir)
    check("a remote image becomes the placeholder", prepared,
        "# Notes\n\n\n\nRemote image not loaded \u00b7 cdn&#46;example&#46;com\n\n\n\n![local](file:///home/gm/notes/shot.png)\n")
    check("no remote image syntax survives", /!\[[^\]]*\]\(https?:/i.test(prepared), false)
    check("a local image resolves to its file URL", prepared.indexOf("![local](file:///home/gm/notes/shot.png)") >= 0, true)
    check("prose around images is untouched", prepared.indexOf("# Notes") === 0, true)

    var refs = "![demo][logo]\n\n[logo]: https://cdn.example.com/logo.png\n"
    var preparedRefs = Markdown.prepare(refs, dir)
    check("a remote reference image becomes the placeholder", preparedRefs,
        "\n\nRemote image not loaded \u00b7 cdn&#46;example&#46;com\n\n\n\n")
    var kept = "![demo][logo]\n\n[logo]: shot.png\n"
    check("a local reference image resolves", Markdown.prepare(kept, dir).indexOf("![demo](file:///home/gm/notes/shot.png)") >= 0, true)
    var links = "[docs](https://example.com/guide) and <https://example.com/raw>\n"
    check("links without ink escape brackets", Markdown.prepare(links, dir),
        "&#91;docs&#93;(https&#58;&#47;&#47;example&#46;com&#47;guide) and https&#58;&#47;&#47;example&#46;com&#47;raw\n")
    var code = "```\n![demo](https://cdn.example.com/demo.png)\n```\n"
    check("a fenced image is shown, never resolved", Markdown.prepare(code, dir), code)
    var span = "Use `![demo](https://cdn.example.com/demo.png)` for art.\n"
    check("an inline-code image is shown, never resolved", Markdown.prepare(span, dir), span)
    var html = 'Before <img src="https://cdn.example.com/a.png" alt="art"> after\n'
    check("a remote img tag becomes the placeholder", Markdown.prepare(html, dir),
        "Before \n\nRemote image not loaded \u00b7 cdn&#46;example&#46;com\n\n after\n")
    check("no remote img tag survives", /<img[^>]*https?:/i.test(Markdown.prepare(html, dir)), false)
    var htmlLocal = 'See <img src="shot.png" alt="art"> here\n'
    check("a local img tag resolves to a Markdown image", Markdown.prepare(htmlLocal, dir).indexOf("![art](file:///home/gm/notes/shot.png)") >= 0, true)
    check("no local img tag survives", Markdown.prepare(htmlLocal, dir).indexOf("<img"), -1)

    check("an empty file counts no lines", Markdown.lineCount(""), 0)
    check("a final newline ends the second line", Markdown.lineCount("a\nb\n"), 2)
    check("an unterminated second line still counts", Markdown.lineCount("a\nb"), 2)
    check("a newline alone is one empty line", Markdown.lineCount("\n"), 1)
    check("CRLF ends each line once", Markdown.lineCount("a\r\nb\r\n"), 2)
    var capture = Source.source("tests/ui-captures-markdown.sh")
    // The fixture is a head heredoc, one blank line and one text line per note, then a tail heredoc.
    var fixture = capture.match(/cat > "\$dir\/listing\/notes\.md" <<'EOF'\n([\s\S]*?)\nEOF\n[\s\S]*?cat >> "\$dir\/listing\/notes\.md" <<'EOF'\n([\s\S]*?)\nEOF/)
    var notes = capture.match(/^capmarkdown_notes=(\d+)/m)
    check("the native capture fixture exists", fixture !== null && notes !== null, true)
    var fixtureText = fixture && notes ? fixture[1] + "\n" + "\nNote\n".repeat(Number(notes[1])) + fixture[2] + "\n" : ""
    // src/backend/linecount.rs: LF bytes plus an unterminated final line, with zero for an empty file.
    var backendCount = (fixtureText.match(/\n/g) || []).length + (fixtureText.length > 0 && !fixtureText.endsWith("\n") ? 1 : 0)
    check("the native capture backend count is 170", backendCount, 170)
    check("the capture header agrees with the backend", Markdown.countLine(Markdown.lineCount(fixtureText)), Markdown.countLine(backendCount))
    check("lines count the breaks plus one", Markdown.lineCount("a\nb\nc"), 3)
    check("one line reads singular", Markdown.countLine(1), "1 line")
    check("many lines read grouped", Markdown.countLine(1200), "1,200 lines")
    check("the board's count reads as drawn", Markdown.countLine(48), "48 lines")
    check("the file's folder is its folder", Markdown.dirOf("/home/gm/notes/notes.md"), "/home/gm/notes")

    function kinds(doc) {
        return Markdown.blocks(doc, dir).map(function (b) { return b.type }).join(",")
    }
    check("plain prose splits into runs", kinds("Some words.\n\nMore words.\n"), "run,run")
    check("a heading splits out ahead of its prose", kinds("# Hi\n\nSome words.\n"), "heading,run")
    check("a fence splits out verbatim", kinds("Before\n\n```js\nvar a = 1;\n```\n\nAfter\n"), "run,fence,run")
    var fence = Markdown.blocks("```js\nvar a = 1;\n```\n", dir)[0]
    check("a fence carries no ticks", fence.text, "var a = 1;")
    check("an unterminated fence runs to the end",
        kinds("Text\n\n```\nvar a = 1;\nvar b = 2;\n"), "run,fence")
    check("a quote splits out", kinds("Before\n\n> quoted words\n\nAfter\n"), "run,quote,run")
    var quote = Markdown.blocks("> first\n> second\n", dir)[0]
    check("a quote strips one mark per line", quote.text, "first\nsecond")
    check("a fence inside a quote stays a quote", kinds("> look\n> ```\n> code\n"), "quote")
    check("a remote image is its own block",
        kinds("Text\n\n![demo](https://cdn.example.com/demo.png)\n\nMore\n"), "run,remote,run")
    var remote = Markdown.blocks("![demo](https://cdn.example.com/demo.png)\n", dir)[0]
    check("a remote block names the host", remote.host, "cdn.example.com")
    check("a local image is its own block",
        kinds("Text\n\n![shot](shot.png)\n\nMore\n"), "run,image,run")
    var image = Markdown.blocks("![shot](shot.png)\n", dir)[0]
    check("a local block resolves beside the file", image.url, "file:///home/gm/notes/shot.png")
    check("a mid-text image stays a run", kinds("See ![demo](https://cdn.example.com/a.png) here.\n"), "run")
    var mixed = Markdown.blocks("# T\n\n> q\n\n```\nc\n```\n\n![a](https://h.example.com/a.png)\n\n![b](b.png)\n\nEnd\n", dir)
    check("a mixed document splits in order",
        mixed.map(function (b) { return b.type }).join(","), "heading,quote,fence,remote,image,run")
    check("no remote image syntax survives any run",
        mixed.every(function (b) { return b.type !== "run" || !/!\[[^\]]*\]\(https?:/i.test(b.text) }), true)

    var chrome = "#181825"
    function styled(doc) {
        return Markdown.prepare(doc, dir, undefined, chrome)
    }
    check("a code span becomes the chrome chip",
        styled("Use `load()` here.").indexOf('<code style="background-color:#181825"><span style="font-size:chippad">&nbsp;</span>load&#40;&#41;<span style="font-size:chippad">&nbsp;</span></code>') >= 0, true)
    check("without chrome a span stays literal", Markdown.prepare("Use `load()` here.", dir).indexOf("`load()`") >= 0, true)
    check("a bad chrome leaves spans literal",
        Markdown.prepare("Use `load()` here.", dir, undefined, "red").indexOf("`load()`") >= 0, true)
    check("an unmatched run stays literal", styled("Use `load( here.").indexOf("`load(") >= 0, true)
    check("one space each end is stripped", styled("Use ` x ` here.").indexOf('><span style="font-size:chippad">&nbsp;</span>x<span style="font-size:chippad">&nbsp;</span></code>') >= 0, true)
    check("emphasis cannot form inside a span", styled("Use `*hi*` here.").indexOf("&#42;hi&#42;") >= 0, true)
    check("an ampersand escapes once", styled("Use `a & b` here.").indexOf("a &#38; b") >= 0, true)
    check("a URL inside backticks never resolves",
        styled("Use `![a](https://h.example.com/x.png)` here.").indexOf("Remote image") < 0, true)
    check("a URL inside backticks never resolves",
        styled("Use `![a](https://h.example.com/x.png)` here.").indexOf("Remote image") < 0, true)
    check("matching lengths pair inward", styled("Use `` `tick` `` here.").indexOf("&#96;tick&#96;") >= 0, true)
    check("backticks inside a tag stay in the tag",
        styled('See <a href="`x`">y</a> here.').indexOf('href="`x`"') >= 0, true)
    check("a fenced span never styles", styled("```\n`x`\n```\n").indexOf("<code") < 0, true)

    var table = "| Kind | Asks for | Cached |\n| :--- | ---: | :---: |\n| a | b | c |\n| d \\| e | f | g |\n"
    var tabled = Markdown.blocks(table, dir)
    check("a delimiter row makes a table", tabled.length === 1 && tabled[0].type === "table", true)
    check("a table carries its header", tabled[0].head.join("|"), "Kind|Asks for|Cached")
    check("a table carries alignments", tabled[0].aligns.join(","), "left,right,center")
    check("a table carries its rows", tabled[0].rows.length === 2 && tabled[0].rows[0].join("|") === "a|b|c", true)
    check("an escaped pipe stays cell text", tabled[0].rows[1][0], "d &#124; e")
    check("a cell cannot form markup", tabled[0].rows[0][0].indexOf("<") < 0
        && tabled[0].head[0].indexOf("|") < 0, true)
    check("pipes without a delimiter stay a run", kinds("a | b\nc | d\n"), "run")

    // GFM example 200: escaped pipes remain cell text in prose, code spans and strong emphasis.
    var escapedTable = Markdown.blocks("| f\\|oo |\n| ------ |\n| b `\\|` az |\n| b **\\|** im |\n", dir, chrome)[0]
    check("GFM 200 header unescapes pipe", escapedTable.head[0], "f&#124;oo")
    check("GFM 200 code span unescapes pipe", escapedTable.rows[0][0],
        'b <code style="background-color:#181825"><span style="font-size:chippad">&nbsp;</span>&#124;<span style="font-size:chippad">&nbsp;</span></code> az')
    check("GFM 200 strong row unescapes pipe", escapedTable.rows[1][0], "b <strong>&#124;</strong> im")
    // The backtick sends prose down the scan path, where only a table cell turns its pipe into an entity.
    check("a pipe outside a table stays prose", Markdown.prepare("a | `b`", dir, undefined, chrome),
        'a | <code style="background-color:#181825"><span style="font-size:chippad">&nbsp;</span>b<span style="font-size:chippad">&nbsp;</span></code>')
    check("table splitting keeps other backslash pairs", Leaf.splitRow("| \\*literal\\* | \\`code\\` |").join("|"),
        "\\*literal\\*|\\`code\\`")
    var missingInlineRejected = false
    try {
        Leaf.tableBlock(["head"], ["left"], [["cell"]])
    } catch (error) {
        missingInlineRejected = true
    }
    check("tableBlock requires the document inline callback", missingInlineRejected, true)
    check("unused public tableBlock wrapper is absent", typeof Markdown.tableBlock, "undefined")
    var callbackTable = Leaf.tableBlock(["head"], ["left"], [["cell"]], function (text) { return "inline:" + text })
    check("table callback renders header and body", callbackTable.head[0] + "|" + callbackTable.rows[0][0], "inline:head|inline:cell")
    // The column is sized for the widest cell as drawn, so a link's long URL never outweighs a wider plain cell.
    var linkBeside = Markdown.blocks("| h |\n| --- |\n| [a](https://a-very-long-url.example/path) |\n| wider plain cell |\n", dir, chrome, "#c0caf5")[0]
    check("a link cell does not win the column by its source length", linkBeside.measure.join(), "wider plain cell")
    var markBeside = Markdown.blocks("| h |\n| --- |\n| **bo** |\n| abcd |\n", dir, chrome, "#c0caf5")[0]
    check("emphasis markers do not count toward the drawn width", markBeside.measure.join(), "abcd")
    var longList = Markdown.blocks(Array.apply(null, Array(70)).map(function (x, i) { return "- item " + i }).join("\n") + "\n", dir, chrome, "#c0caf5")
    check("a long list becomes chunks that cover every item once", longList.map(function (b) { return b.items.length }).join(","), "32,32,6")
    check("list chunks continue the numbering", Markdown.blocks(Array.apply(null, Array(40)).map(function (x, i) { return (i + 5) + ". x" }).join("\n") + "\n", dir, chrome, "#c0caf5")
        .map(function (b) { return b.start + "/" + b.last + "/" + (b.joined === true) }).join(","), "5/44/false,37/44/true")
    var rows = Array.apply(null, Array(50)).map(function (x, i) { return "| r" + i + " |" }).join("\n")
    var longTable = Markdown.blocks("| h |\n| --- |\n" + rows + "\n", dir, chrome, "#c0caf5")
    check("a long table becomes chunks with one header and shared widths", longTable.map(function (b) { return b.head.length + ":" + b.rows.length + ":" + b.measure[0] }).join(","), "1:24:r10,0:24:r10,0:2:r10")
    check("short list and table stay one block with no chunk fields", [Markdown.blocks("- a\n- b\n", dir, chrome, "#c0caf5")[0].joined,
        Markdown.blocks("| h |\n| --- |\n| a |\n", dir, chrome, "#c0caf5")[0].joined].map(String).join(), "undefined,undefined")
    check("only http, https and mailto count as external links", ["https://a.example", "HTTP://a.example", "mailto:a@b.example", "./x.md", "#top",
        "ftp://h/f", "javascript:alert(1)", "java\tscript:alert(1)", "file:///etc/passwd", "//a.example", ""].map(function (u) { return Markdown.isExternalLink(u) }).join(), "true,true,true,false,false,false,false,false,false,false,false")

    var cellSources = ["**bold**", "*emphasis*", "`a & <b>`", "[guide](https://example.com/?a=1&b=2)",
        "\\*literal\\*", "a \\| b", "\\`literal\\`", "\\[literal\\]", "<script>secret</script>safe",
        "a &amp; b", "&#42;literal&#42;"]
    var inlineTable = Markdown.blocks("| " + cellSources.join(" | ") + " |\n| "
        + cellSources.map(function () { return "---" }).join(" | ") + " |\n| "
        + cellSources.join(" | ") + " |\n", dir, chrome, "#c0caf5")[0]
    for (var cellIndex = 0; cellIndex < cellSources.length; cellIndex++) {
        var cellProse = Markdown.prepare(cellSources[cellIndex], dir, undefined, chrome, "#c0caf5")
        check("table header uses paragraph inline semantics: " + cellSources[cellIndex], inlineTable.head[cellIndex], cellProse)
        check("table body uses paragraph inline semantics: " + cellSources[cellIndex], inlineTable.rows[0][cellIndex], cellProse)
    }

    var ink = "#c0caf5"
    function linked(doc) {
        return Markdown.prepare(doc, dir, undefined, chrome, ink)
    }
    check("a link wraps in the ink",
        linked("See [a guide](https://example.com/x) here.").indexOf(
            '<a href="https://example.com/x"><font color="#c0caf5">a guide</font></a>') >= 0, true)
    check("an image never becomes a link",
        linked("See ![a](https://h.example.com/x.png) here.").indexOf('<a href="https://h.example.com/x.png"') < 0, true)
    check("a titled link keeps its target",
        linked('See [a](https://example.com/x "t") here.').indexOf('<a href="https://example.com/x">') >= 0, true)
    check("a query ampersand escapes",
        linked("See [a](https://example.com/?x=1&y=2) here.").indexOf("x=1&#38;y=2") >= 0, true)
    check("an autolink wraps", linked("See <https://example.com/x> here.").indexOf("<font") >= 0, true)
    check("a bad ink escapes link brackets",
        Markdown.prepare("See [a](https://example.com/x) here.", dir, undefined, chrome, "red"),
        "See &#91;a&#93;(https&#58;&#47;&#47;example&#46;com&#47;x) here.")
    check("emphasis forms inside a link label",
        linked("See [*hi*](https://example.com/x) here.").indexOf("<font color=\"#c0caf5\"><em>hi</em></font></a>") >= 0, true)

    var barelinks = [
        { text: "See https://example.com/x. here.", url: "https://example.com/x" },
        { text: "See https://example.com/a(b)). here.", url: "https://example.com/a(b)" },
        { text: "See http://example.com/x?!.,;: here.", url: "http://example.com/x" },
        { text: "See www.example.com/x)). here.", url: "www.example.com/x" }
    ]
    for (var bareIndex = 0; bareIndex < barelinks.length; bareIndex++) {
        var bare = barelinks[bareIndex]
        var bareStart = "See ".length
        var read = Link.readBarelink(bare.text, bareStart)
        check("barelink URL and end offset " + bareIndex,
            read && read.url === bare.url && read.end === bareStart + bare.url.length, true)
    }

    function lists(doc) {
        return Markdown.blocks(doc, dir).filter(function (b) { return b.type === "list" })
    }
    var ordered = lists("1. First\n2. Second\n")
    check("an ordered list is one block", ordered.length, 1)
    check("an ordered block counts its items", ordered[0].items.length, 2)
    check("an ordered block keeps its start", ordered[0].start, 1)
    check("an ordered block keeps item text", ordered[0].items[0].indexOf("First") >= 0, true)
    var bullets = lists("- Alpha\n- Beta\n")
    check("bullets are unordered", bullets.length === 1 && bullets[0].ordered === false, true)
    check("a later start survives", lists("3. a\n4. b\n")[0].start, 3)
    check("a marker kind change splits", lists("1. a\n- b\n").length, 2)
    var nested = lists("1. a\n   - sub\n2. b\n")
    check("a nested marker joins its list", nested.length === 1 && nested[0].items.length === 3, true)
    check("a nested item is its own entry one level down", JSON.stringify(nested[0].depths) + " " + nested[0].items[1], "[0,1,0] sub")
    var lazy = lists("1. a\nlazy line\n2. b\n")
    check("a lazy line joins its item", lazy.length === 1 && lazy[0].items[0].indexOf("lazy") >= 0, true)
    check("a blank line between items keeps the list", lists("1. a\n\n2. b\n").length, 1)
    check("a blank line before prose ends the list",
        Markdown.blocks("1. a\n\nText\n", dir).map(function (b) { return b.type }).join(","), "list,run")
    check("a ragged table keeps the header's width",
        Markdown.blocks("| a | b |\n|---|---|\n| 1 | 2 | 3 |\n", dir)[0].cols, 2)
}
