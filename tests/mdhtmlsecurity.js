.pragma library

// Raw HTML spelled through character references: refused addresses stay refused and marks stay entity-escaped.
.import "flea/js/MdBlocks.js" as Blocks

var CHROME_BACKGROUND = "#181825"
var CHROME_INK = "#c0caf5"

function blocksOf(input, dir) {
    return Blocks.blocks(input + "\n", dir, CHROME_BACKGROUND, CHROME_INK)
}

function runText(blocks) {
    return blocks.map(function (block) { return block.text === undefined ? "" : block.text }).join("")
}

// Sample input: '<a href="https://a.example/">x</a>' answers ["https://a.example/"], the address as Qt reads it back.
function emittedHrefs(blocks) {
    var hrefs = []
    var re = /<a href="([^"]*)"/g
    var found = null
    var runs = runText(blocks)
    while ((found = re.exec(runs)) !== null)
        hrefs.push(found[1].replace(/&#38;/g, "&").replace(/&#34;/g, '"').replace(/&#60;/g, "<"))
    return hrefs
}

var SPELLED_ADDRESSES = ["jav&#97;script:alert(1)", "&#106;avascript:alert(1)", "java&#9;script:alert(1)", "java&#x0A;script:alert(1)",
    "java&Tab;script:alert(1)", "java&NewLine;script:alert(1)", "&amp;#106;avascript:alert(1)", "javascript&colon;alert(1)",
    "&#x6a;avascript&#58;alert(1)", "data&colon;text/html,x"]
var ANCHOR_WRAPPERS = ['<a href="H">LTX</a>', '<p align="center"><a href="H">LTX</a></p>', '<div><a href="H">LTX</a></div>',
    '<details><summary><a href="H">LTX</a></summary>b</details>', "<a href='H'>LTX</a>"]
var MARK_TEXT = "&ast;a&ast; &#91;x&#93; &#96;c&#96; &#42;&#42;b&#42;&#42; &lbrack;y&rbrack; &grave;g&grave;"
var MARK_WRAPPERS = ['<p align="center">T</p>', "<div>T</div>", "<h2>T</h2>", "<p><b>T</b></p>", "<kbd>T</kbd>", "<code>T</code>",
    '<a href="https://a.example/">T</a>', "<details><summary>T</summary>T</details>", "<div>\nT\n</div>"]

// The failure messages for one document folder; an empty list means every case held.
function failures(dir) {
    var out = []
    var plain = emittedHrefs(blocksOf('<a href="https://a.example/">LTK</a>', dir))
    if (plain.length !== 1 || plain[0] !== "https://a.example/")
        out.push("the anchor check does not see a plain raw HTML link")
    for (var s = 0; s < SPELLED_ADDRESSES.length; s++) {
        // Every spelled address is hostile, so none may be emitted as an href, and the anchor's text stays unlinked.
        for (var w = 0; w < ANCHOR_WRAPPERS.length; w++) {
            var anchored = blocksOf(ANCHOR_WRAPPERS[w].replace("H", SPELLED_ADDRESSES[s]), dir)
            var hrefs = emittedHrefs(anchored)
            if (hrefs.length !== 0 || JSON.stringify(anchored).indexOf("LTX") < 0)
                out.push("raw HTML anchor spelled through references kept a refused address " + s + "/" + w + " " + JSON.stringify(hrefs))
        }
        var pictured = blocksOf('<img src="' + SPELLED_ADDRESSES[s] + '">\n\n<p align="center"><img src="' + SPELLED_ADDRESSES[s] + '"></p>', dir)
        var urls = pictured.filter(function (block) { return block.type === "image" }).map(function (block) { return block.url })
        if (/javascript:|data:/i.test(JSON.stringify(pictured)) || !urls.every(function (url) { return url.indexOf("file://" + dir + "/") === 0 }))
            out.push("raw HTML image spelled through references left the document folder " + s + " " + JSON.stringify(urls))
    }
    for (var m = 0; m < MARK_WRAPPERS.length; m++) {
        var drawn = runText(blocksOf(MARK_WRAPPERS[m].split("T").join(MARK_TEXT), dir)).replace(/<a href="[^"]*"/g, "<a")
        if (/[\[\]*`]/.test(drawn))
            out.push("a reference-spelled mark inside an HTML wrapper reached Qt as syntax " + m + " " + drawn)
    }
    return out
}
