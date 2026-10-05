.pragma library

// MarkdownPictures: a Markdown text's inline pictures, read for their addresses and capped at the width the text has.
var PICTURE = /!\[[^\]]*\]\(([^)\s]*)[^)]*\)/g

// Sample input: "a ![x](file:///d/p.png) b ![y](file:///d/q.png)" answers ["file:///d/p.png", "file:///d/q.png"].
function urls(source) {
    var found = []
    String(source).replace(PICTURE, function (whole, url) {
        found.push(url)
        return whole
    })
    return found
}

// Sample input: ("a ![x](file:///p.png) b", { "file:///p.png": { w: 160, h: 40 } }, 100) answers text 'a <img src="file:///p.png" width="100" height="25" /> b' and tallest 25.
// A picture wider than the limit is written as an img tag scaled to it with its ratio kept, and one that fits (or is not decoded yet) stays as it is.
function fit(source, sizes, limit) {
    var tallest = 0
    var text = String(source).replace(PICTURE, function (whole, url) {
        var size = sizes[url]
        if (size === undefined || size.w <= 0)
            return whole
        var capped = limit > 0 && size.w > limit
        var tall = capped ? Math.max(1, Math.round(size.h * limit / size.w)) : size.h
        tallest = Math.max(tallest, tall)
        return capped ? '<img src="' + url.replace(/"/g, "%22").replace(/&/g, "&amp;") + '" width="' + limit + '" height="' + tall + '" />' : whole
    })
    return { text: text, tallest: tallest }
}
