.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MdLeaf.js" as Leaf
.import "../../ui/js/MdInline.js" as Inline
.import "../../ui/js/MdLink.js" as Link
.import "../../ui/js/MdUrl.js" as Url
.import "../../ui/js/MdRun.js" as Run
.import "sourcefixture.js" as Source

function run(assert) {
    function check(label, actual, expected) {
        assert(label, JSON.stringify(actual), JSON.stringify(expected))
    }
    var dir = "/doc"
    var chrome = "#181825"
    var ink = "#c0caf5"
    function blocks(text) { return Markdown.blocks(text, dir, chrome, ink) }
    var invalidFence = "```foo``` is inline code\nfollowing prose\nstill prose"
    check("md2a F40 backtick info refused", Leaf.fenceOpen("```foo``` is inline code"), null)
    check("md2a F40 following prose stays paragraph", blocks(invalidFence)[0].type, "run")
    check("md2a F40 paragraph retains prose", blocks(invalidFence)[0].text.indexOf("following prose\nstill prose") >= 0, true)
    check("md2a F40 valid fence control", blocks("```js\ncode\n```\nfollowing prose"),
        [{ type: "fence", text: "code", info: "js" }, { type: "run", text: "following prose" }])
    check("md2a F40 tilde info allows backticks", Leaf.fenceOpen("~~~foo`bar").info, "foo`bar")

    var inlineSource = Source.source("ui/js/MdInline.js")
    check("R12 md2a F48 dead escape helper removed", /function escapeChar\(/.test(inlineSource), false)
    check("R12 md2a F52 dead fence closer removed", /function fenceClose\(/.test(Source.source("ui/js/MdLeaf.js")), false)
    check("R12 md2a F53 named punctuation bounds", /code\s*[<>]=\s*\d/.test(Source.source("ui/js/MdEscape.js")), false)
    check("R12 md2a F53 named prefix lengths", /text\.slice\(i, i \+ \d+\)/.test(Source.slice(Source.source("ui/js/MdLink.js"), "function readBarelink(", "return url.length")), false)
    check("R12 md2b F53 named driver stride", /sp \+= \d/.test(Source.source("ui/js/MdRun.js")), false)
    var strideSites = ["out[out.length - INTERVAL_STRIDE]", "out.length -= INTERVAL_STRIDE",
        "codeAt += INTERVAL_STRIDE", "ai += fromA ? INTERVAL_STRIDE : 0", "bi += fromA ? 0 : INTERVAL_STRIDE"]
    check("md2a F41 tuple stride named", inlineSource.indexOf("var INTERVAL_STRIDE = 4") >= 0, true)
    for (var s = 0; s < strideSites.length; s++)
        check("md2a F41 stride site " + s, inlineSource.indexOf(strideSites[s]) >= 0, true)
    check("md2a F41 mixed interval control", Inline.spanIntervals("`a` $b$"), [0, 3, 1, 0, 4, 7, 1, 1])

    var lineEnds = ["\n", "\r", "\r\n"]
    for (var e = 0; e < lineEnds.length; e++) {
        check("md2a F42 escaped destination line ending " + e,
            Link.readInlineTarget("(a\\" + lineEnds[e] + "b.png)", 0), null)
        var spanning = '(a "title\\' + lineEnds[e] + 'continued")'
        check("md2a F42 a title spans a line ending after a backslash " + e,
            Link.readInlineTarget(spanning, 0), { url: "a", end: spanning.length })
        check("md2a F42 a title never spans a blank line " + e,
            Link.readInlineTarget('(a "title' + lineEnds[e] + lineEnds[e] + 'continued")', 0), null)
    }
    check("md2a F42 escaped destination control", Link.readInlineTarget("(a\\)b.png)", 0).url, "a\\)b.png")
    check("md2a F42 escaped title control", Link.readInlineTarget('(a "title\\\"continued")', 0).url, "a")

    check("md2b F34 comparison keeps text", blocks("a < b > c"), [{ type: "run", text: "a &#60; b &#62; c" }])
    check("md2b F34 digit-led keeps text", blocks("I <3 you > them"), [{ type: "run", text: "I &#60;3 you &#62; them" }])
    check("md2b F34 malformed tag keeps text", blocks("before <b?x> tail"), [{ type: "run", text: "before &#60;b?x&#62; tail" }])
    check("md2b F34 refused valid tag control", blocks("before <bogus>body</bogus> tail"), [{ type: "run", text: "before body tail" }])
    check("md2b F34 allowed tag control", blocks("before <b>body</b> tail"), [{ type: "run", text: "before <b>body</b> tail" }])

    var colors = ["", "red"]
    for (var c = 0; c < colors.length; c++) {
        var math = Run.parseInline('$![x](http://host/math.png)$', dir, {}, {}, colors[c], ink, [])
        check("md2b F35 invalid chrome placeholder " + c, math.indexOf("Remote image not loaded") >= 0, true)
        check("md2b F35 invalid chrome no image " + c, math.indexOf("!["), -1)
    }
    check("md2b F35 valid chrome math control", Run.parseInline("$x+1$", dir, {}, {}, chrome, ink, []).indexOf('data-math="inline"') >= 0, true)

    var paths = [["caf%C3%A9.png", "caf\u00e9.png"], ["100%25.png", "100%.png"], ["%2541.png", "%41.png"]]
    for (var p = 0; p < paths.length; p++) {
        check("md2b F36 UTF-8 canonical " + p, Url.canonicalUrl(paths[p][0]), paths[p][1])
        check("md2b F36 relative path " + p, decodeURIComponent(Url.classifyImage(paths[p][0], dir).url), "file:///doc/" + paths[p][1])
        check("md2b F36 file path " + p, decodeURIComponent(Url.classifyImage("file:///doc/" + paths[p][0], dir).url), "file:///doc/" + paths[p][1])
    }
    check("md2b F36 malformed UTF-8 stays literal", Url.canonicalUrl("x%C3%28.png"), "x%C3%28.png")
    check("md2b F36 incomplete escape stays literal", Url.canonicalUrl("x%2.png"), "x%2.png")
    check("md2b F36 encoded traversal control", Url.classifyImage("file:///doc/%2e%2e/x.png", dir).kind, "dropped")
    check("md2b F37 astral scalar", Url.canonicalUrl("&#65583;"), "\uD800\uDC2F")
    check("md2b F37 astral path", decodeURIComponent(Url.classifyImage("foo&#65583;bar.png", dir).url), "file:///doc/foo\uD800\uDC2Fbar.png")

    var splice = '<img src="pic.png"><span title="\uE0020\uE003">tail</span>'
    var safeSplice = '<img src="file:///doc/pic.png" alt=""><span title="\uFFFD0\uFFFD">tail</span>'
    check("md2b F38 title cannot splice token", blocks(splice), [{ type: "run", text: safeSplice }])
    check("md2b F38 direct inline boundary", Run.parseInline(splice, dir, {}, {}, chrome, ink, []), safeSplice)
    check("md2b F38 fenced document boundary", blocks("```\n\uE0020\uE003\n```")[0].text, "\uFFFD0\uFFFD")
    check("md2b F39 quote-balanced attribute rejected",
        blocks('<table \' title="\' background=http://host/bg.png \'" \' ><tr><td>hi</td></tr></table>')[0].text.indexOf("background"), -1)
    check("md2b F42 self-closing dropped tag keeps tail", blocks("before <svg/> rest of paragraph"),
        [{ type: "run", text: "before  rest of paragraph" }])
    check("md2b F42 nested self-closing tag keeps tail", blocks("before <svg><svg/></svg> tail"),
        [{ type: "run", text: "before  tail" }])
    check("md2b F42 nested content control", blocks("before <svg><svg>hidden</svg>hidden</svg> tail"),
        [{ type: "run", text: "before  tail" }])

    var corpus = Source.source("tests/markdown-security.sh")
    check("R12 md2b F52 dead delayed zero branch removed", corpus.indexOf('if [ "$delayed_count" -eq 0 ]'), -1)
    check("md2b F41 remote badge corpus", corpus.indexOf("[![b]({H}/{p}/badge.png)](local.md)") >= 0, true)
    check("md2b F41 HTML badge corpus", corpus.indexOf('[<img src="{H}/{p}/badge.png">](local.md)') >= 0, true)
    var parsers = [
        ["md2a F44", "ui/js/MdLeaf.js", ["isThematic", "fenceOpen", "alertTitle", "taskText"]],
        ["md2a F44", "ui/js/MdLink.js", ["normalizeLabel"]],
        ["md2b F43", "ui/js/MdHtml.js", ["tagHead"]],
        ["md2b F43", "ui/js/MdRefs.js", ["readFootnoteRef"]],
        ["md2b F43", "ui/js/MdResolve.js", ["parseAngle"]],
        ["md2b F43", "ui/js/MdUrl.js", ["numericRef", "canonicalUrl"]]
    ]
    for (var g = 0; g < parsers.length; g++) {
        var source = Source.source(parsers[g][1])
        for (var f = 0; f < parsers[g][2].length; f++) {
            var name = parsers[g][2][f]
            var before = source.slice(0, source.indexOf("function " + name + "(")).split("\n")
            check(parsers[g][0] + " sample " + name, before[before.length - 2].indexOf("// Sample input:") === 0, true)
        }
    }
}
