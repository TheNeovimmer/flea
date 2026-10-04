.import "../../ui/js/Markdown.js" as Markdown
.import "../../ui/js/MdHtmlImage.js" as HtmlImage

// A badge row draws as one wrapping row of images, and a wrapper unit ends at its own closer.
function run(check) {
    var dir = "/home/u/docs"
    var url = "https://example.com/"
    function blocks(source) { return Markdown.blocks(source, dir, "#181825", "#c0caf5") }
    function at(list, index) { return list[index] === undefined ? {} : list[index] }
    function types(source) { return blocks(source).map(function (b) { return b.type }).join(",") }
    function badge(name, link) {
        var img = '<img src="img/' + name + '.png" alt="' + name + '">'
        return link === false ? img : '<a href="' + url + name + '">' + img + "</a>"
    }
    var names = ["build", "release", "license", "downloads"]
    var lines = names.map(function (n) { return badge(n) })
    var row = blocks('<p align="center">\n' + lines.join("\n") + "\n</p>")
    check("B1 four linked badges in one centred block are one images block", types('<p align="center">\n' + lines.join("\n") + "\n</p>"), "images")
    check("B1 the row lists its badges in order", (at(row, 0).items || []).map(function (i) { return i.alt }).join(","), names.join(","))
    check("B1 each badge keeps its own link", (at(row, 0).items || []).map(function (i) { return i.link }).join(","),
        names.map(function (n) { return url + n }).join(","))
    check("B1 the row is centred when its block is", at(row, 0).align, "center")
    check("B1 each badge points beside the document", (at(row, 0).items || []).every(function (i) { return i.url === "file://" + dir + "/img/" + i.alt + ".png" }), true)
    check("B2 the same badges on one line are one images block", types('<p align="center">' + lines.join(" ") + "</p>"), "images")
    var plain = blocks("<p>\n" + lines.join("\n") + "\n</p>")
    check("B3 a left block draws its row at the left", at(plain, 0).type + ":" + at(plain, 0).align, "images:undefined")
    check("B4 a break between badges starts a new row", types('<p align="center">\n' + lines[0] + "<br>\n" + lines[1] + "\n</p>"), "image,image")
    check("B5 badges in separate paragraphs stay stacked", types('<p align="center">' + lines[0] + '</p>\n<p align="center">' + lines[1] + "</p>"), "image,image")
    check("B6 one badge stays a plain image block", types('<p align="center">\n' + lines[0] + "\n</p>"), "image")
    check("B7 text between two badges keeps them apart", types('<p align="center">\n' + lines[0] + "\nBuilt on CI\n" + lines[1] + "\n</p>"), "image,run,image")
    check("B8 bare images on lines of a div are one row", types("<div>\n" + badge("a", false) + "\n" + badge("b", false) + "\n</div>"), "images")
    check("B9 no closer is left drawn after a row", JSON.stringify(row).indexOf("</"), -1)
    var wide = blocks('<p align="center">\n' + badge("a") + "\n" + badge("b") + "\n</p>\n\nAfter")
    check("B10 the text after a row is untouched", String(at(wide, 1).text).trim(), "After")
    var widths = blocks('<p align="center">\n<img src="img/a.png" width="40">\n<img src="img/b.png" width="900">\n</p>')
    check("B11 each badge keeps its own width", (at(widths, 0).items || []).map(function (i) { return i.width }).join(","), "40,900")
    check("B12 a remote badge never joins the row of local ones", types('<p align="center">\n' + badge("a") + '\n<img src="https://img.shields.io/x.svg">\n</p>'), "image,run")

    // A letter that grows when lower-cased (U+0130) must not shift where the image is cut.
    var grown = blocks('<p align="center">\u0130 <img src="img/logo.png"> end</p>')
    check("B13 text that grows in lower case leaves the image where it is", grown.map(function (b) { return b.type }).join(",") + "|" + JSON.stringify(grown).indexOf("<img"), "run,image,run|-1")
    var many = []
    for (var m = 0; m < 150; m++)
        many.push(badge("n" + m, false))
    check("B14 a row of 150 pictures continues in blocks of 64", blocks('<p align="center">\n' + many.join("\n") + "\n</p>").map(function (b) { return b.type + ":" + b.items.length }).join(","), "images:64,images:64,images:22")
    check("B14 a row cut at the cap leaves no lone picture as a row", types('<p align="center">\n' + many.slice(0, 65).join("\n") + "\n</p>"), "images,image")
    var nested = ['<div align="center">', '<img src="img/logo.png">', "<p>", "note", "</p>", "</div>", "", "After"]
    var unit = HtmlImage.imageUnit(nested, 0, dir)
    check("R2-1 a nested paragraph closer does not end a div wrapper", unit === null ? -1 : unit.end, 5)
    check("R2-1 the wrapper keeps the nested paragraph whole", unit === null ? "" : unit.wrapper.join("|"), '<div align="center"><p>\nnote\n</p></div>')
    var same = HtmlImage.imageUnit(['<div align="center">', '<img src="img/logo.png">', "<div>", "x", "</div>", "</div>"], 0, dir)
    check("R2-1 a nested div is counted, the wrapper ends at its own closer", same === null ? -1 : same.end, 5)
    check("R2-1 a closer of another tag never ends the wrapper",
        HtmlImage.imageUnit(['<div align="center">', '<img src="img/logo.png">', "</p>"], 0, dir), null)
    check("R2-1 a one-line closer of another tag is no unit",
        HtmlImage.imageUnit(['<p align="center"><img src="img/logo.png"></div>'], 0, dir), null)
    var doc = blocks('<div align="center">\n<img src="img/logo.png">\n<p>\nnote\n</p>\n</div>\n\nAfter')
    check("R2-1 the wrapper's rest is one balanced run, then the text", doc.map(function (b) { return b.type }).join(",") + "|" + String(at(doc, 1).text), 'image,run|<div align="center"><p>\nnote\n</p></div>\n\nAfter')
}
