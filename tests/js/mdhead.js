.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MdHtmlBlock.js" as HtmlBlock
.import "sourcefixture.js" as Source

// HTML headings: inside a wrapper, with a picture, or beside another heading, each keeps its wrapper whole and its picture on the picture path.
function run(check) {
    var dir = "/home/u/docs"
    var ink = "#c0caf5"
    function blocks(text) { return Markdown.blocks(text, dir, "#181825", ink) }
    function json(text) { return JSON.stringify(blocks(text)) }
    // A run holds an opener its closer never reaches, or the other way round.
    function balanced(list) {
        return list.every(function (b) {
            var text = String(b.text === undefined ? "" : b.text)
            return (text.match(/<div\b/gi) || []).length === (text.match(/<\/div>/gi) || []).length
        })
    }
    var lone = blocks('<div align="center">\n<h1>Flea</h1>\n</div>')
    check("a heading in a lone centred wrapper is one heading block", lone.length, 1)
    check("a heading in a lone centred wrapper keeps its level", lone[0].type + lone[0].level, "heading1")
    check("a heading in a lone centred wrapper takes the wrapper's centre", lone[0].align, "center")
    check("a lone wrapper's heading leaves no unmatched div", balanced(lone), true)
    var tail = blocks('<div align="center">\n<h1>Title</h1>\n<p>x</p>\n</div>')
    check("a wrapper's heading is a centred heading block", tail[0].type + tail[0].level + tail[0].align, "heading1center")
    check("what the wrapper held after the heading stays centred in its wrapper", tail.length === 2 && tail[1].text, '<div align="center"><p>x</p></div>')
    check("a wrapper with a tail leaves no unmatched div", balanced(tail), true)
    check("a heading's own align wins over the wrapper's", blocks('<div align="center">\n<h2 align="right">T</h2>\n</div>')[0].align, "right")
    check("an own align left wins over a centred wrapper", blocks('<div align="center">\n<h2 align="left">T</h2>\n</div>')[0].align, undefined)
    check("a plain wrapper gives its heading no alignment", blocks('<div>\n<h1>T</h1>\n</div>')[0].align, undefined)
    var table = blocks('<table>\n<tr><td>\n<h1>x</h1>\n</td></tr>\n</table>')
    check("a heading in an open table stays in its run", table.every(function (b) { return b.type !== "heading" }), true)
    var open = blocks('<div>\n<span>a\n<h1>x</h1>\n</div>')
    check("a heading in other open HTML stays in its run", open.every(function (b) { return b.type !== "heading" }) && balanced(open), true)

    var logo = blocks('<h1 align="center"><img src="logo.png" width="120"><br>Flea</h1>')
    check("a heading's leading picture draws as an image block", logo[0].type + logo[0].url + logo[0].width, "imagefile:///home/u/docs/logo.png120")
    check("the picture takes the heading's centre", logo[0].align, "center")
    check("the text left over is the heading", logo.length === 2 && logo[1].type + logo[1].text + logo[1].align, "headingFleacenter")
    check("a picture only heading leaves no heading", blocks('<h1 align="center"><img src="logo.png"></h1>').map(function (b) { return b.type }).join(), "image")
    check("a heading picture in a link keeps its link", blocks('<h1><a href="https://x.dev/"><img src="logo.png"></a> Flea</h1>')[0].link, "https://x.dev/")
    // A picture the lift cannot take leaves its heading in its run, where the picture path sizes it at its width; no heading text ever holds one.
    function noPictureInHeading(list) {
        return list.every(function (b) { return b.type !== "heading" || (b.text.indexOf("<img") < 0 && b.text.indexOf("![") < 0) })
    }
    var rightLogo = blocks('<h1 align="right"><img src="logo.png" width="120">Flea</h1>')
    check("a right aligned heading with a picture stays in its run, the picture sized by the picture path", rightLogo.every(function (b) { return b.type !== "heading" }) && rightLogo.some(function (b) { return b.type === "image" && b.width === 120 }), true)
    check("a right aligned heading's picture is in no heading block", noPictureInHeading(rightLogo), true)
    var lateLogo = blocks('<h1>Flea <img src="logo.png" width="120"></h1>')
    check("a heading with a picture after its text stays in its run, the picture sized by the picture path", lateLogo.every(function (b) { return b.type !== "heading" }) && lateLogo.some(function (b) { return b.type === "image" && b.width === 120 }), true)
    check("a heading's late picture is in no heading block", noPictureInHeading(lateLogo), true)
    var wrappedLate = blocks('<div align="center">\n<h1>Flea <img src="logo.png" width="120"></h1>\n</div>')
    check("a wrapped heading with a late picture is in no heading block", noPictureInHeading(wrappedLate) && balanced(wrappedLate), true)
    var twoLogos = blocks('<h1><img src="a.png"><img src="b.png">Flea</h1>')
    check("a heading with a second picture after the first stays in its run", twoLogos.every(function (b) { return b.type !== "heading" }) && noPictureInHeading(twoLogos), true)
    var markdownLogo = blocks('<h1>Flea ![logo](logo.png)</h1>')
    check("a heading holding a Markdown image stays in its run", markdownLogo.every(function (b) { return b.type !== "heading" }) && noPictureInHeading(markdownLogo), true)

    function head(line) { return HtmlBlock.htmlHeading(line) }
    check("two headings on one line are no heading", head("<h1>a</h1><h1>b</h1>"), null)
    check("two headings on one line with a space are no heading", head("<h1>a</h1> <h1>b</h1>"), null)
    check("text after the closer is no heading", head("<h2>x</h2> tail"), null)
    check("an uppercase heading is a heading", head("<H1>Flea</H1>").level, 1)
    check("an uppercase heading keeps its inner", head("<H1>Flea</H1>").inner, "Flea")
    check("align left answers no align", head('<h1 align="left">x</h1>').align, null)
    check("align centre answers centre", head('<h1 align="center">x</h1>').align, "center")

    // MarkdownText has no preview to ask, so its board body is its own line; it must stay the number the preview's recipe is drawn at.
    var previewBody = /readonly property int boardBody: (\d+)/.exec(Source.source("ui/PreviewMarkdown.qml"))
    var textBody = /readonly property real boardBodyPx: (\d+)/.exec(Source.source("ui/MarkdownText.qml"))
    check("the chip pad's board body is the preview's", previewBody !== null && textBody !== null && previewBody[1] === textBody[1], true)

    // The hosts hand the figure the preview's fence pads: the display figure and the maths block bind them from view.preview, the maths text forwards them.
    var view = Source.source("ui/MarkdownBlockView.qml")
    var figureHost = Source.slice(view, "id: figureItem", "bodyPx: view.preview.bodyPx")
    var mathsHost = Source.slice(view, "id: mathsBlock", "font.pixelSize: view.preview.bodyPx")
    var forward = Source.slice(Source.source("ui/MarkdownMathsText.qml"), "delegate: MarkdownFigure", "onSvgChanged")
    check("the display figure binds fencePadX from the preview", figureHost.indexOf("fencePadX: view.preview.fencePadX") >= 0, true)
    check("the display figure binds fencePadY from the preview", figureHost.indexOf("fencePadY: view.preview.fencePadY") >= 0, true)
    check("the maths block binds fencePadX from the preview", mathsHost.indexOf("fencePadX: view.preview.fencePadX") >= 0, true)
    check("the maths block binds fencePadY from the preview", mathsHost.indexOf("fencePadY: view.preview.fencePadY") >= 0, true)
    check("the maths text forwards fencePadX to its figures", forward.indexOf("fencePadX: root.fencePadX") >= 0, true)
    check("the maths text forwards fencePadY to its figures", forward.indexOf("fencePadY: root.fencePadY") >= 0, true)
}
