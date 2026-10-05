.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MdHtmlImage.js" as HtmlImage

// GitHub's sanitized raw HTML subset and the nesting cap, as the parser hands them to the pane.
function run(check) {
    var dir = "/home/u/docs"
    var chrome = "#181825"
    var ink = "#c0caf5"
    var logoUrl = "file://" + dir + "/img/logo.png"
    function blocks(source, withChrome) { return Markdown.blocks(source, dir, withChrome === undefined ? chrome : withChrome, ink) }
    // A missing block reads as an empty one, so a parser that drops it fails the check instead of throwing.
    function at(list, index) { return list[index] === undefined ? {} : list[index] }
    function types(source) { return blocks(source).map(function (b) { return b.type }).join(",") }
    function runs(source, withChrome) {
        return blocks(source, withChrome).filter(function (b) { return b.type === "run" })
            .map(function (b) { return b.text }).join("|")
    }
    var logo = blocks('<p align="center"><img src="img/logo.png" width="64" alt="logo"></p>\n<p align="center"><b>A centred title</b></p>\n\nLine one<br>line two')
    check("H1 logo line is an image block between heading and text", logo.map(function (b) { return b.type }).join(","), "image,run,run")
    check("H1 logo keeps its width attribute", at(logo, 0).width, 64)
    check("H1 logo is centred by its paragraph", at(logo, 0).align, "center")
    check("H1 logo points beside the document", at(logo, 0).url, logoUrl)
    check("H1 logo keeps its alt", at(logo, 0).alt, "logo")
    check("H1 title stays a centred bold paragraph", String(at(logo, 1).text).indexOf('<p align="center"><b>A centred title</b></p>') >= 0, true)
    check("H1 line break survives", String(at(logo, 2).text).indexOf("Line one<br />line two") >= 0, true)
    var wrapped = blocks('<p align="center">\n  <img src="img/logo.png" width="128">\n</p>\n\ntext')
    check("H2 a wrapper on its own lines leaves only the image and the text", wrapped.map(function (b) { return b.type }).join(","), "image,run")
    check("H2 wrapped image is centred at its width", at(wrapped, 0).align + ":" + at(wrapped, 0).width, "center:128")
    check("H2 no wrapper tag is left drawn", String(at(wrapped, 1).text).indexOf("<p") < 0 && String(at(wrapped, 1).text).indexOf("</p") < 0, true)
    var bare = blocks('<img src="img/logo.png" width="64">')
    check("H3 a bare image keeps its width and sits at the left", JSON.stringify(bare), JSON.stringify([{ type: "image", url: logoUrl, alt: "", width: 64 }]))
    var widths = { abc: 0, "0": 0, "-5": 0, "50%": 0, "12.5": 0, "99999": 0, "64px": 64, " 48 ": 48 }
    for (var attr in widths) {
        var shown = at(blocks('<img src="img/logo.png" width="' + attr + '">'), 0)
        check("H4 width attribute '" + attr + "'", shown.width === undefined ? 0 : shown.width, widths[attr])
    }
    var inlineImage = runs('text <img src="img/logo.png" alt="x"> tail')
    check("H5 an inline raw image never reaches the importer as HTML", inlineImage.indexOf("<img"), -1)
    check("H5 an inline raw image becomes a Markdown image", inlineImage.indexOf("![x](" + logoUrl + ")") >= 0, true)
    check("H5 a picture never reaches the importer as HTML", runs('a <picture><source srcset="img/logo.png"><img src="img/logo.png"></picture> b').indexOf("<img"), -1)
    var keys = runs("Press <kbd>Ctrl</kbd>+<kbd>C</kbd> to copy.")
    check("H6 kbd draws as the inline code chip", keys,
        'Press <code style="background-color:#181825">Ctrl</code>+<code style="background-color:#181825">C</code> to copy.')
    check("H6 a raw code tag wears the same chip", runs("a <code>x</code> b"), 'a <code style="background-color:#181825">x</code> b')
    check("H6 without chrome kbd stays a plain code tag", runs("a <kbd>x</kbd> b", ""), "a <code>x</code> b")
    check("H6 a hostile chrome never reaches the tag", runs("a <kbd>x</kbd> b", 'red;"><b>'), "a <code>x</code> b")
    check("H7 sub and sup pass through", runs("H<sub>2</sub>O and mc<sup>2</sup>."), "H<sub>2</sub>O and mc<sup>2</sup>.")
    var details = runs("<details>\n<summary>Click to expand</summary>\n\nHidden body.\n\n</details>")
    check("H8 the summary is a bold line with the open disclosure mark", details.indexOf("<b>▾ Click to expand</b>") >= 0, true)
    check("H8 the body is drawn open", details.indexOf("Hidden body.") >= 0, true)
    check("H8 no details or summary tag is left", details.indexOf("<details") < 0 && details.indexOf("summary") < 0, true)
    var div = runs('<div style="color: red" class="x" id="y">A div</div>')
    check("H9 a div keeps its text and loses its attributes", div, "<div>A div</div>")
    var inert = ['<script>alert(1)</script>', "<style>p{color:red}</style>", '<iframe src="https://x.example/">frame</iframe>',
        '<object data="x.swf">obj</object>', '<embed src="x"></embed>', "<template>tmpl</template>", "<noscript>ns</noscript>"]
    for (var i = 0; i < inert.length; i++)
        check("H10 inert " + inert[i], runs("before " + inert[i] + " after").replace(/\s+/g, " "), "before after")
    check("H10 an on* attribute is dropped", runs('<p onclick="steal()" align="center">hi</p>'), '<p align="center">hi</p>')
    check("H10 a javascript: link loses its target", runs('<a href="javascript:alert(1)">x</a>').indexOf("javascript"), -1)
    check("H10 an onerror attribute never survives on an image", JSON.stringify(blocks('<img src="img/logo.png" onerror="alert(1)">')).indexOf("onerror"), -1)
    check("H12 a block-level raw tag after a paragraph starts its own run", types("Body text.\n\n<div>A div</div>"), "run,run")
    check("H12 a raw table keeps its rows in one run", types("<table>\n<tr>\n<td>x</td>\n</tr>\n</table>"), "run")
    check("H12 a paragraph after an HTML block stays with it", types('<p align="center"><b>T</b></p>\n\nafter'), "run,run")
    var url = "https://example.com/x"
    var linked = blocks('<p align="center">\n<a href="' + url + '"><img src="img/logo.png" width="64" alt="logo"></a>\n</p>\n\nAfter')
    check("H14 a linked centred logo is an image block then the text", linked.map(function (b) { return b.type }).join(","), "image,run")
    check("H14 the logo is centred, sized and linked", [at(linked, 0).align, at(linked, 0).width, at(linked, 0).link].join(","), "center,64," + url)
    check("H14 the text after it is untouched", String(at(linked, 1).text).trim(), "After")
    check("H14 a javascript: link leaves the logo unlinked", at(blocks('<p align="center">\n<a href="javascript:alert(1)"><img src="img/logo.png"></a>\n</p>'), 0).link, undefined)
    var cell = blocks('<table><tr><td><img src="img/logo.png" width="64"></td></tr></table>\n\nAfter')
    check("H14 an image in a table cell leaves the HTML block as an image block", cell.map(function (b) { return b.type }).join(","), "image,run")
    check("H14 no Markdown image text is left in an HTML block", JSON.stringify(cell).indexOf("!["), -1)
    var badges = blocks('<p align="center">\n<a href="' + url + '"><img src="img/logo.png" alt="a"></a>\n<a href="' + url + 'y"><img src="img/logo.png" alt="b"></a>\n</p>')
    check("H14 two linked badges in one block are one row, each linked", badges.map(function (b) { return b.type }).join(",") + ":" + (at(badges, 0).items || []).map(function (i) { return i.link }).join(","),
        "images:" + url + "," + url + "y")
    var open = blocks('<p align="center"><img src="img/logo.png" width="64" alt="logo">\n<br><b>Name</b>\n</p>\n\nAfter')
    check("H15 an opener with the image and the closer later is the image then a centred run", open.map(function (b) { return b.type }).join(","), "image,run,run")
    check("H15 the rest of the wrapper is a centred paragraph with no leading break", at(open, 1).text, '<p align="center"><b>Name</b></p>')
    check("H15 the text after the wrapper is its own run", String(at(open, 2).text), "After")
    var empty = blocks('<p align=center><img src="img/logo.png" width="64">\n</p>\n\nAfter')
    check("H15 a wrapper holding only the image leaves no empty or closer-only run", empty.map(function (b) { return b.type + ":" + String(b.text).trim() }).join(","), "image:undefined,run:After")
    var noCloser = ['<p align="center"><img src="img/logo.png">', "", "After"]
    check("H15 an opener with no closer is no unit", HtmlImage.imageUnit(noCloser, 0, dir), null)
    check("H15 and draws no closer of its own", JSON.stringify(blocks(noCloser.join("\n"))).indexOf("</p>"), -1)
    // The closer shares a line with text, so the unit declines and the importer path draws one balanced paragraph.
    var shared = ['<p align="center"><img src="img/logo.png">', "<b>Name</b></p>", "", "After"]
    check("H15 a closer that shares its line with text is no unit", HtmlImage.imageUnit(shared, 0, dir), null)
    check("H15 the stray closer is drawn once, balanced with its centring wrapper", runs(shared.join("\n")), '<p align="center"><b>Name</b></p>|After')
    check("H16 an inline image in a paragraph stays inline", types('text <a href="' + url + '"><img src="img/logo.png"></a> tail'), "run")
    check("H4 a width past the pane is kept for the pane to clamp", at(blocks('<img src="img/logo.png" width="5000">'), 0).width, 5000)
    check("H17 a heading and a paragraph on adjacent lines are two runs", types('<h1 align="center">Flea</h1>\n<p align="center"><b>A file manager</b> for <i>Omarchy</i></p>'), "run,run")
    check("H17 each keeps its own centring", runs('<h1 align="center">Flea</h1>\n<p align="center">x</p>'), '<h1 align="center">Flea</h1>|<p align="center">x</p>')
    check("H17 nested blocks inside one div stay one run", types("<div>\n<p>a</p>\n<p>b</p>\n</div>"), "run")
    check("H17 a details summary line stays with its details", types("<details>\n<summary>S</summary>\n\nbody\n\n</details>"), "run")
    check("H18 a soft break after br collapses", runs("one<br>\ntwo"), "one<br />two")
    check("H18 a break before a blank line keeps the paragraph break", runs("one<br>\n\ntwo"), "one<br />|two")
    check("H13 a lone angle bracket stays text", runs("1 < 2 and <3 here"), "1 &#60; 2 and &#60;3 here")
    check("H13 HTML in a code span stays literal", runs("use `<b>x</b>` here"),
        'use <code style="background-color:#181825">&#60;b&#62;x&#60;&#47;b&#62;</code> here')
    check("H13 HTML in a fence stays verbatim", JSON.stringify(blocks('```html\n<div onclick="x">hi</div>\n```')),
        JSON.stringify([{ type: "fence", text: '<div onclick="x">hi</div>', info: "html" }]))
    // The parser spells every escaped punctuation as a numeric reference (mdspec), so the entity stays text in that form.
    check("H13 an escaped entity stays text", runs("x &lt;b&gt; y"), "x &#60;b&#62; y")
    function quote(depth) {
        var lines = []
        for (var d = 1; d <= depth; d++)
            lines.push("> ".repeat(d) + "level " + d)
        return lines.join("\n")
    }
    function list(depth) {
        var lines = []
        for (var d = 0; d < depth; d++)
            lines.push("  ".repeat(d) + "- item " + d)
        return lines.join("\n")
    }
    check("H11 the nesting limit is 32", Markdown.NESTING_LIMIT, 32)
    // Each nesting level is one quote block (mdspec), so a quote at the limit renders as 32 of them.
    check("H11 a quote at the limit still renders", types(quote(32)), new Array(32 + 1).join("quote,").slice(0, -1))
    check("H11 a quote past the limit is the nesting sentinel", JSON.stringify(blocks(quote(33))), JSON.stringify([{ type: "deep", limit: 32 }]))
    check("H11 400 nested quotes are the sentinel", types(quote(400)), "deep")
    check("H11 a list at the limit still renders", types(list(32)), "list")
    check("H11 a list past the limit is the sentinel", types(list(33)), "deep")
    check("H11 markers on one line count", types("- ".repeat(33) + "x"), "deep")
    check("H11 deep indentation inside a fence is code, never nesting", types("```\n" + list(60) + "\n```"), "fence")
    check("H11 deep indentation of plain text is not nesting", types(" ".repeat(200) + "word") !== "deep", true)
    check("H11 a heading before the deep part is not drawn", types("# Title\n\n" + quote(40)), "deep")
    check("H11 the notice names the limit", typeof Markdown.deepNotice === "function" ? Markdown.deepNotice() : "", "Rendered preview skipped: nesting is deeper than 32 levels. Showing the source.")
}
