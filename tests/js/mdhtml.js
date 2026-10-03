.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MdHtml.js" as Html
.import "../../ui/js/MdResolve.js" as Resolve
.import "../../ui/js/MdBlocks.js" as Blocks
.import "../../ui/js/MdRun.js" as Run
.import "../../ui/js/MdRefs.js" as Refs
.import "../../ui/js/MdLeaf.js" as Leaf

function run(check) {
    var dir = "/home/u/docs"
    var ink = "#c0caf5"
    function inline(s, color) { return Run.parseInline(s, dir, {}, {}, "#181825", color, []) }
    function tag(s) { return Html.sanitizeTag(s, dir, []).emit }
    var customOpen = Html.tagHead("<svg-icon>")
    var customClose = Html.tagHead("</svg-icon>")
    check("R10 md2a svg-icon opening name", customOpen.name, "svg-icon")
    check("R10 md2a svg-icon opening is not closing", customOpen.closing, false)
    check("R10 md2a svg-icon opening has valid attributes", customOpen.validAttrs, true)
    check("R10 md2a svg-icon closing matches opening name", customClose.name, customOpen.name)
    check("R10 md2a svg-icon closing is closing", customClose.closing, true)
    check("R10 md2a svg-icon closing has valid attributes", customClose.validAttrs, true)
    check("R10 md2a svg-icon inline keeps tail", inline("<svg-icon>x</svg-icon> tail", ink), "x tail")
    check("R10 md2a svg-icon document keeps tail",
        JSON.stringify(Markdown.blocks("<svg-icon>x</svg-icon> tail", dir, "#181825", ink)),
        JSON.stringify([{ type: "run", text: "x tail" }]))
    check("F1 HTML host has no tag", tag('<img src="http://a%3Cb%3Ex/x">').indexOf("<b>"), -1)
    check("F1 Markdown host has no tag", inline('![x](http://a%3Cb%3Ex/x)', ink).indexOf("<b>"), -1)
    check("F2 forbidden target has no live brackets", inline('[x](javascript:alert(1))', ink).indexOf("["), -1)
    check("F2 refused https has no live brackets", Resolve.resolvePair("x", "https://x", false, dir, "", []).indexOf("["), -1)
    check("F3 empty ink escapes link opener", inline('[x](file:///etc)', "").indexOf("["), -1)
    check("F3 dropped tag cannot join image", inline('!<bogus>[x](http://x/a)', "").indexOf("!["), -1)
    check("F3 comment cannot join image", inline('!<!--gap-->[x](http://x/a)', "").indexOf("!["), -1)
    var unsafeTargets = [" javascript:alert(1)", "\tjavascript:alert(1)\t", "\njavascript:alert(1)\r",
        " \u0001JaVaScRiPt:alert(1)\u001f ", " java\tscript:alert(1) ", " java\nscript:alert(1) ",
        " data:text/html,hi ", " file:///etc/passwd ", "&#32;javascript:alert(1)&#32;"]
    for (var targetIndex = 0; targetIndex < unsafeTargets.length; targetIndex++) {
        var unsafeTarget = unsafeTargets[targetIndex]
        check("R12 md2b F46 HTML allowlist " + targetIndex, Html.attrKept("href", unsafeTarget, "a"), false)
        check("R12 md2b F46 link allowlist " + targetIndex, Resolve.isLinkTarget(unsafeTarget), false)
        check("R12 md2b F46 HTML emits no href " + targetIndex, tag('<a href="' + unsafeTarget + '">'), "<a>")
        check("R12 md2b F46 Markdown emits no href " + targetIndex,
            typeof Resolve.resolvePair("x", unsafeTarget, false, dir, ink, []), "string")
    }
    check("R12 md2b F46 https control", tag('<a href="https://example.com/x">'), '<a href="https://example.com/x">')
    check("R12 md2b F46 HTML stripped target", tag('<a href=" \thttps://example.com/x\n ">'), '<a href="https://example.com/x">')
    check("R12 md2b F46 Markdown stripped target", Resolve.resolvePair("x", " \thttps://example.com/x\n ", false,
        dir, ink, []), -1)
    var strippedTokens = []
    Resolve.resolvePair("x", " \thttps://example.com/x\n ", false, dir, ink, strippedTokens)
    check("R12 md2b F46 Markdown href value", strippedTokens[0].indexOf('href="https://example.com/x"') >= 0, true)
    var imageInLink = "http://a/![x](http://host/p.png)"
    check("R12 md2b F47 empty ink bare no image opener", inline(imageInLink, "").indexOf("!["), -1)
    check("R12 md2b F47 empty ink bare label", inline(imageInLink, ""),
        "http&#58;&#47;&#47;a&#47;&#33;&#91;x&#93;&#40;http&#58;&#47;&#47;host&#47;p&#46;png&#41;")
    check("R12 md2b F47 empty ink autolink label", inline("<" + imageInLink + ">", ""), inline(imageInLink, ""))
    var paths = ['file://' + dir + '/../x.png', dir + '/notes/../../x.png',
        'file://' + dir + '/%2e%2e/x.png', dir + '/notes/%2e%2e/%2e%2e/x.png']
    for (var p = 0; p < paths.length; p++)
        check("F4 traversal " + p, Markdown.classifyImage(paths[p], dir).kind, "dropped")
    var doublePaths = ["%252e%252e/x.png", "file://" + dir + "/%252e%252e/x.png",
        dir + "/notes/%252e%252e/%252e%252e/x.png"]
    var doubleUrls = ["file://" + dir + "/%252e%252e/x.png", "file://" + dir + "/%252e%252e/x.png",
        "file://" + dir + "/notes/%252e%252e/%252e%252e/x.png"]
    for (var doubleIndex = 0; doubleIndex < doublePaths.length; doubleIndex++)
        check("R12 md2b F51 double encoded F4 literal " + doubleIndex,
            Markdown.classifyImage(doublePaths[doubleIndex], dir).url, doubleUrls[doubleIndex])
    check("F4 unknown directory absolute", Markdown.classifyImage('/etc/x.png', 'relative').kind, "dropped")
    check("F4 unknown directory file", Markdown.classifyImage('file:///etc/x.png', 'relative').kind, "dropped")
    check("F4 unknown directory relative", Markdown.classifyImage("x.png", "relative").kind, "dropped")
    check("F4 normalized local", Markdown.classifyImage(dir + '/notes/../x.png', dir).url, 'file://' + dir + '/x.png')
    check("F8 nested link alt local", inline('![a [b](http://x) c](pic.png)', ink).indexOf('](file://' + dir + '/pic.png)') >= 0, true)
    check("F8 link-only alt local", inline('![[l](a)](pic.png)', ink).indexOf('](file://' + dir + '/pic.png)') >= 0, true)
    var code = ['```\n[a]: b\n```', '```\n[^1]: a\n```', '    [a]: b']
    for (var c = 0; c < code.length; c++) {
        var blocks = Markdown.blocks(code[c], dir, '#181825', ink)
        check("F9 code preserved " + c, blocks.length > 0 && blocks[0].type === "fence" && blocks[0].text === (c === 1 ? "[^1]: a" : "[a]: b"), true)
    }
    check("F12 absent src alt has no image opener", tag('<img alt="![x](http://x/alt.png)">').indexOf("!["), -1)
    check("F12 rejected src alt has no image opener", tag('<img src="x:y" alt="![x](http://x/alt2.png)">').indexOf("!["), -1)
    check("F15 unquoted image classifies remote", tag('<img src=http://h/x.png>').indexOf('Remote image not loaded') >= 0, true)
    check("F15 unquoted href retained", tag('<a href=https://x.com/p>'), '<a href="https://x.com/p">')
    check("R2 unquoted trailing slash retained", tag('<a href=https://x.com/p/>'), '<a href="https://x.com/p/">')
    check("R2 bare host slash retained", tag('<a href=https://x.com/>'), '<a href="https://x.com/">')
    check("R2 separated slash closes", tag('<a href=https://x.com/p/ />'), '<a href="https://x.com/p/" />')
    check("R2 quoted slash closes", tag('<a href="https://x.com/p/"/>'), '<a href="https://x.com/p/" />')
    var slashForms = [
        { tail: " a=b/", selfClose: false },
        { tail: ' a="b"/', selfClose: true },
        { tail: " a='b'/", selfClose: true },
        { tail: " a /", selfClose: true },
        { tail: " a/", selfClose: true },
        { tail: "/", selfClose: true },
        { tail: " a=b/ ", selfClose: false },
        { tail: " a=b /", selfClose: true },
        { tail: " a / ", selfClose: false }
    ]
    var dropNames = ["script", "style", "svg"]
    for (var n = 0; n < dropNames.length; n++) {
        var name = dropNames[n]
        for (var s = 0; s < slashForms.length; s++) {
            var form = slashForms[s]
            var opening = "<" + name + form.tail + ">"
            var closing = "</" + name + ">"
            var label = "R8 " + opening
            check(label + " tokenizer flag", Html.tagHead(opening).selfClose, form.selfClose)
            check(label + " drop guard", Html.sanitizeTag(opening, dir, []).drop, form.selfClose ? null : name)
            check(label + " body", inline("before " + opening + "hidden" + closing + " tail", ink),
                form.selfClose ? "before hidden tail" : "before  tail")
            check(label + " block body", JSON.stringify(Markdown.blocks("before " + opening + "hidden" + closing + " tail", dir,
                "#181825", ink)), JSON.stringify([{ type: "run", text: form.selfClose ? "before hidden tail" : "before  tail" }]))
            var nested = opening + "hidden" + closing + (form.selfClose ? "" : "hidden" + closing) + " tail"
            check(label + " skip depth", Refs.skipDropContent(nested, 0, name, { tagDead: -1 }),
                nested.indexOf(" tail"))
        }
    }
    for (var dropped in Html.DROP_CONTENT)
        check("R8 every drop name " + dropped, inline("before <" + dropped + " a=b/>hidden</" + dropped + "> tail", ink),
            "before  tail")
    check("R8 shared scanner retains unquoted slash", tag('<a title=b/ >'), '<a title="b/">')
    check("R8 slash before attributes is not final", tag('<a / title="b">'), '<a title="b">')
    var nonHtmlWhitespace = ["\u00A0", "\u000B", "\u2003", "\uFEFF"]
    var htmlWhitespace = ["\t", "\n", "\f", "\r", " "]
    var htmlForms = [{ tail: " ==/", selfClose: false }, { tail: " =a/", selfClose: false }]
    for (var w = 0; w < nonHtmlWhitespace.length; w++) {
        htmlForms.push({ tail: " a=b" + nonHtmlWhitespace[w] + "/", selfClose: false })
        htmlForms.push({ tail: nonHtmlWhitespace[w] + "a=b/", selfClose: false })
        check("R9 unquoted value retains non-HTML whitespace " + w,
            Html.scanAttributes(" a=b" + nonHtmlWhitespace[w] + "/").attributes[0].value,
            "b" + nonHtmlWhitespace[w] + "/")
        check("R9 non-HTML delimiter refuses allowed tag " + w,
            Html.tagHead("<b" + nonHtmlWhitespace[w] + "a=b/>").name, "")
        check("R9 standalone image rejects non-HTML attribute whitespace " + w,
            Leaf.standaloneImage('<img src' + nonHtmlWhitespace[w] + '="pic.png">', dir, {}), null)
    }
    for (var h = 0; h < htmlWhitespace.length; h++) {
        htmlForms.push({ tail: " a=b" + htmlWhitespace[h] + "/", selfClose: true })
        htmlForms.push({ tail: htmlWhitespace[h] + "a=b /", selfClose: true })
    }
    check("R9 initial equals starts attribute name", JSON.stringify(Html.scanAttributes(" ==/").attributes),
        JSON.stringify([{ name: "=", value: "/" }]))
    check("R9 equals stays in attribute name", JSON.stringify(Html.scanAttributes(" =a/").attributes),
        JSON.stringify([{ name: "=a", value: null }]))
    check("R9 invalid attribute name still records HTML slash syntax", Html.scanAttributes(" =a/").selfClose, true)
    check("R9 standalone image does not read data-src",
        Leaf.standaloneImage('<img data-src="pic.png">', dir, {}), null)
    check("R9 standalone image normalizes unquoted slash",
        Leaf.standaloneImage('<img src=pic.png/>', dir, {}).url, "file://" + dir + "/pic.png")
    var firstImage = { type: "image", url: "file://" + dir + "/a.png", alt: "" }
    var firstAlt = { type: "image", url: firstImage.url, alt: "first" }
    var duplicateImages = [
        { label: "first src", tag: '<img src="a.png" src="b.png">', expected: firstImage },
        { label: "first unquoted src", tag: '<img src=a.png src=b.png>', expected: firstImage },
        { label: "first empty src", tag: '<img src="" src="b.png">', expected: null },
        { label: "first valueless src", tag: '<img src src="b.png">', expected: null },
        { label: "first local src", tag: '<img src="a.png" src="https://later.example/b.png">', expected: firstImage },
        { label: "first remote src", tag: '<img SRC="https://first.example/a.png" src="b.png">',
            expected: { type: "remote", host: "first.example" } },
        { label: "first alt", tag: '<img src="a.png" alt="first" alt="last">', expected: firstAlt },
        { label: "first unquoted alt", tag: '<img src=a.png alt=first alt=last>', expected: firstAlt },
        { label: "first empty alt", tag: '<img src="a.png" alt="" alt="last">', expected: firstImage },
        { label: "first valueless alt", tag: '<img src="a.png" alt alt="last">', expected: firstImage },
        { label: "first mixed-case src and alt", tag: "<img SRC='a.png' src='b.png' ALT='first' alt='last'>",
            expected: firstAlt }
    ]
    for (var duplicateIndex = 0; duplicateIndex < duplicateImages.length; duplicateIndex++) {
        var duplicate = duplicateImages[duplicateIndex]
        check("R10 md2b F45 md2c F38 standalone image keeps " + duplicate.label,
            JSON.stringify(Leaf.standaloneImage(duplicate.tag, dir, {})), JSON.stringify(duplicate.expected))
    }
    var inlineDuplicates = [
        { tag: '<img src="a.png" src="b.png" alt="first" alt="last">', output: '<img src="file://' + dir + '/a.png" alt="first">' },
        { tag: '<img src="a.png" src="https://later.example/b.png">', output: '<img src="file://' + dir + '/a.png" alt="">' },
        { tag: '<img srcset="a.png 1x" srcset="b.png 1x">', output: '<img src="file://' + dir + '/a.png" alt="">' },
        { tag: '<img srcset="a.png 1x" srcset="https://later.example/b.png 1x">', output: '<img src="file://' + dir + '/a.png" alt="">' },
        { tag: '<img src="" src="b.png" alt="first" alt="last">', output: "first" },
        { tag: '<img src src="b.png" alt alt="last">', output: "" },
        { tag: '<img srcset srcset="b.png 1x" alt="first">', output: "first" }
    ]
    for (var inlineDuplicateIndex = 0; inlineDuplicateIndex < inlineDuplicates.length; inlineDuplicateIndex++) {
        var inlineDuplicate = inlineDuplicates[inlineDuplicateIndex]
        check("R12 md2b F49 inline first attributes " + inlineDuplicateIndex,
            inline("prefix " + inlineDuplicate.tag, ink), "prefix " + inlineDuplicate.output)
    }
    var tagSizes = [8192, 16384, 32768]
    var tagWorkFactor = 2
    var previousTagWork = 0
    function searchedTagCharacters(source) {
        var searched = 0
        var countedText = {
            length: source.length,
            charAt: function (at) { return source.charAt(at) },
            slice: function (from, to) { return source.slice(from, to) },
            indexOf: function (needle, from) {
                var start = from === undefined ? 0 : from
                var found = source.indexOf(needle, start)
                searched += (found < 0 ? source.length : found + needle.length) - start
                return found
            }
        }
        var dead = { tagDead: -1 }
        for (var opener = 0; opener < source.length - 1; opener++)
            Html.readTag(countedText, opener, dead)
        return searched
    }
    for (var sizeIndex = 0; sizeIndex < tagSizes.length; sizeIndex++) {
        var size = tagSizes[sizeIndex]
        var tagWork = searchedTagCharacters("<".repeat(size) + ">")
        check("R12 md2b F48 tag work bounded " + size, tagWork <= tagWorkFactor * size, true)
        if (previousTagWork > 0)
            check("R12 md2b F48 doubling search work " + size, tagWork <= tagWorkFactor * previousTagWork, true)
        previousTagWork = tagWork
    }
    check("R10 md2b F45 md2c F38 document keeps first src and alt",
        JSON.stringify(Markdown.blocks("<img SRC='a.png' src='b.png' ALT='first' alt='last'>", dir, "#181825", ink)),
        JSON.stringify([firstAlt]))
    for (var dropName in Html.DROP_CONTENT) {
        for (var nw = 0; nw < nonHtmlWhitespace.length; nw++)
            check("R9 malformed closer cannot end " + dropName + " body " + nw,
                inline("before <" + dropName + ">hidden</" + dropName + nonHtmlWhitespace[nw]
                    + ">hidden</" + dropName + "> tail", ink), "before  tail")
        for (var hf = 0; hf < htmlForms.length; hf++) {
            var htmlForm = htmlForms[hf]
            var open = "<" + dropName + htmlForm.tail + ">"
            var endTag = "</" + dropName + ">"
            var input = "before " + open + "hidden" + endTag + " tail"
            var expected = htmlForm.selfClose ? "before hidden tail" : "before  tail"
            var htmlLabel = "R9 " + dropName + " form " + hf
            check(htmlLabel + " tokenizer flag", Html.tagHead(open).selfClose, htmlForm.selfClose)
            check(htmlLabel + " drop guard", Html.sanitizeTag(open, dir, []).drop,
                htmlForm.selfClose ? null : dropName)
            check(htmlLabel + " body and tail", inline(input, ink), expected)
            check(htmlLabel + " block body and tail", JSON.stringify(Markdown.blocks(input, dir, "#181825", ink)),
                JSON.stringify([{ type: "run", text: expected }]))
            var nestedInput = open + "hidden" + endTag + (htmlForm.selfClose ? "" : "hidden" + endTag) + " tail"
            check(htmlLabel + " nested drop depth", Refs.skipDropContent(nestedInput, 0, dropName, { tagDead: -1 }),
                nestedInput.indexOf(" tail"))
        }
    }
    check("R3 thematic break ends a reference paragraph",
        Markdown.definitions("Text\n\n***\n[img]: pic.png").img, "pic.png")
    check("R3 quoted thematic break ends a reference paragraph",
        Markdown.definitions("> - - -\n> [img]: pic.png").img, "pic.png")
    var continued = ["- parent\n\n    [img]: pic.png", "10. parent\n\n    [img]: pic.png",
        "1.  item\n\n    [img]: pic.png"]
    for (var l = 0; l < continued.length; l++) {
        check("R2 list definition " + l, Blocks.collectReferences(continued[l]).defs.img, "pic.png")
        check("R2 list image " + l, Markdown.prepare(continued[l] + "\n\n![x][img]", dir,
            undefined, "#181825", ink).indexOf("file://" + dir + "/pic.png") >= 0, true)
    }
    var endedFences = ["> ```\n> code\n\n[img]: pic.png", "- ```\n  code\n\n[img]: pic.png"]
    for (var f = 0; f < endedFences.length; f++)
        check("R2 container fence ends " + f, Blocks.collectReferences(endedFences[f]).defs.img, "pic.png")
    check("R2 lookahead fence never a destination", JSON.stringify(Blocks.collectReferences(
        "[foo]:\n```\n[a]: b\n```").defs), "{}")
    check("R2 lookahead code never a destination", JSON.stringify(Blocks.collectReferences(
        "[foo]:\n    pic.png").defs), "{}")
    check("F16 prose not consumed", Blocks.collectReferences("[foo]:\nHello world").dropped.length, 0)
    check("F16 title accepted", Blocks.collectReferences('[foo]:\nbar "title"').defs.foo, 'bar')
    check("F17 four spaces", Blocks.collectReferences("[^1]: a\n    more").notes['1'].text, 'a\nmore')
    check("F17 eight spaces", Blocks.collectReferences("[^1]: a\n        more").notes['1'].text, 'a\nmore')
}
