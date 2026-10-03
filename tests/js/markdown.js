.import "../../ui/js/Markdown.js" as Markdown
.import "sourcefixture.js" as Source

function run(check) {
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
        "&#91;docs&#93;(https://example.com/guide) and <https://example.com/raw>\n")
    var code = "```\n![demo](https://cdn.example.com/demo.png)\n```\n"
    check("a fenced image is shown, never resolved", Markdown.prepare(code, dir), code)
    var span = "Use `![demo](https://cdn.example.com/demo.png)` for art.\n"
    check("an inline-code image is shown, never resolved", Markdown.prepare(span, dir), span)
    var html = 'Before <img src="https://cdn.example.com/a.png" alt="art"> after\n'
    check("a remote img tag becomes the placeholder", Markdown.prepare(html, dir),
        "Before \n\nRemote image not loaded \u00b7 cdn&#46;example&#46;com\n\n after\n")
    check("no remote img tag survives", /<img[^>]*https?:/i.test(Markdown.prepare(html, dir)), false)
    var htmlLocal = 'See <img src="shot.png" alt="art"> here\n'
    check("a local img tag resolves", Markdown.prepare(htmlLocal, dir).indexOf('src="file:///home/gm/notes/shot.png"') >= 0, true)

    check("an empty file counts no lines", Markdown.lineCount(""), 0)
    check("a final newline ends the second line", Markdown.lineCount("a\nb\n"), 2)
    check("an unterminated second line still counts", Markdown.lineCount("a\nb"), 2)
    check("a newline alone is one empty line", Markdown.lineCount("\n"), 1)
    check("CRLF ends each line once", Markdown.lineCount("a\r\nb\r\n"), 2)
    var capture = Source.source("tests/ui-captures-markdown.sh")
    var fixture = capture.match(/cat > "\$dir\/listing\/notes\.md" <<'EOF'\n([\s\S]*?)\nEOF/)
    check("the native capture fixture exists", fixture !== null, true)
    var fixtureText = fixture ? fixture[1] + "\n" : ""
    // src/backend/linecount.rs: LF bytes plus an unterminated final line, with zero for an empty file.
    var backendCount = (fixtureText.match(/\n/g) || []).length + (fixtureText.length > 0 && !fixtureText.endsWith("\n") ? 1 : 0)
    check("the native capture backend count is 48", backendCount, 48)
    check("the capture header agrees with the backend", Markdown.countLine(Markdown.lineCount(fixtureText)), Markdown.countLine(backendCount))
    check("lines count the breaks plus one", Markdown.lineCount("a\nb\nc"), 3)
    check("one line reads singular", Markdown.countLine(1), "1 line")
    check("many lines read grouped", Markdown.countLine(1200), "1,200 lines")
    check("the board's count reads as drawn", Markdown.countLine(48), "48 lines")
    check("the file's folder is its folder", Markdown.dirOf("/home/gm/notes/notes.md"), "/home/gm/notes")

    function kinds(doc) {
        return Markdown.blocks(doc, dir).map(function (b) { return b.type }).join(",")
    }
    check("plain prose is one run", kinds("Some words.\n\nMore words.\n"), "run")
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
        styled("Use `load()` here.").indexOf('<code style="background-color:#181825">load&#40;&#41;</code>') >= 0, true)
    check("without chrome a span stays literal", Markdown.prepare("Use `load()` here.", dir).indexOf("`load()`") >= 0, true)
    check("a bad chrome leaves spans literal",
        Markdown.prepare("Use `load()` here.", dir, undefined, "red").indexOf("`load()`") >= 0, true)
    check("an unmatched run stays literal", styled("Use `load( here.").indexOf("`load(") >= 0, true)
    check("one space each end is stripped", styled("Use ` x ` here.").indexOf(">x</code>") >= 0, true)
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
        "See &#91;a&#93;(https://example.com/x) here.")
    check("emphasis cannot form inside a link label",
        linked("See [*hi*](https://example.com/x) here.").indexOf("&#42;hi&#42;") >= 0, true)

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
    check("a nested marker joins its item", nested.length === 1 && nested[0].items.length === 2, true)
    check("nested content survives", nested[0].items[0].indexOf("sub") >= 0, true)
    var lazy = lists("1. a\nlazy line\n2. b\n")
    check("a lazy line joins its item", lazy.length === 1 && lazy[0].items[0].indexOf("lazy") >= 0, true)
    check("a blank line between items keeps the list", lists("1. a\n\n2. b\n").length, 1)
    check("a blank line before prose ends the list",
        Markdown.blocks("1. a\n\nText\n", dir).map(function (b) { return b.type }).join(","), "list,run")
    check("a ragged table spans its widest row",
        Markdown.blocks("| a | b |\n|---|---|\n| 1 | 2 | 3 |\n", dir)[0].cols, 3)
}
