.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MdHtml.js" as Html
.import "../../ui/js/MdResolve.js" as Resolve
.import "../../ui/js/MdBlocks.js" as Blocks
.import "../../ui/js/MdRun.js" as Run
.import "../../ui/js/MdRefs.js" as Refs

function run(check) {
    var dir = "/home/u/docs"
    var ink = "#c0caf5"
    function inline(s, color) { return Run.parseInline(s, dir, {}, {}, "#181825", color, []) }
    function tag(s) { return Html.sanitizeTag(s, dir, []).emit }
    check("F1 HTML host has no tag", tag('<img src="http://a%3Cb%3Ex/x">').indexOf("<b>"), -1)
    check("F1 Markdown host has no tag", inline('![x](http://a%3Cb%3Ex/x)', ink).indexOf("<b>"), -1)
    check("F2 forbidden target has no live brackets", inline('[x](javascript:alert(1))', ink).indexOf("["), -1)
    check("F2 refused https has no live brackets", Resolve.resolvePair("x", "https://x", false, dir, "", []).indexOf("["), -1)
    check("F3 empty ink escapes link opener", inline('[x](file:///etc)', "").indexOf("["), -1)
    check("F3 dropped tag cannot join image", inline('!<bogus>[x](http://x/a)', "").indexOf("!["), -1)
    check("F3 comment cannot join image", inline('!<!--gap-->[x](http://x/a)', "").indexOf("!["), -1)
    var paths = ['file://' + dir + '/../x.png', dir + '/notes/../../x.png',
        'file://' + dir + '/%2e%2e/x.png', dir + '/notes/%2e%2e/%2e%2e/x.png']
    for (var p = 0; p < paths.length; p++)
        check("F4 traversal " + p, Markdown.classifyImage(paths[p], dir).kind, "dropped")
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
