.pragma library

// Raw HTML spelled through character references: refused addresses stay refused and marks stay entity-escaped.
.import "flea/js/MdBlocks.js" as Blocks
.import "flea/js/MdResolve.js" as Resolve

var CHROME_BACKGROUND = "#181825"
var CHROME_INK = "#c0caf5"

function blocksOf(input, dir) {
    return Blocks.blocks(input + "\n", dir, CHROME_BACKGROUND, CHROME_INK)
}

// Every text the blocks draw, the items and parts of lists and quotes included, so a nested form is read where it lands.
function runText(blocks) {
    return blocks.map(function (block) {
        var own = (block.text === undefined ? "" : block.text) + (block.items === undefined ? "" : block.items.join(""))
        var held = block.parts === undefined ? [] : block.parts
        // A quote's parts are blocks, a list's are one array of blocks per item or null.
        var inner = held.map(function (part) { return Array.isArray(part) ? runText(part) : runText([part]) }).join("")
        return own + inner
    }).join("")
}

// Every block, the parts of items and quotes included, so a nested image is found beside a top-level one.
function flatBlocks(blocks) {
    var out = []
    blocks.forEach(function (block) {
        out.push(block)
        var held = block.parts === undefined ? [] : block.parts
        held.forEach(function (part) { Array.prototype.push.apply(out, flatBlocks(Array.isArray(part) ? part : part === null ? [] : [part])) })
    })
    return out
}

// Sample input: "a\nb" in an item answers "- a\n  b", in a quote "> a\n> b".
var NESTINGS = [{ name: "item", first: "- ", rest: "  " }, { name: "quote", first: "> ", rest: "> " }]
function nested(input, form) {
    return input.split("\n").map(function (line, i) { return (i === 0 ? form.first : form.rest) + line }).join("\n")
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

// Markdown destinations and marks spelled through references, for the forms the top-level cases in markdown-security.qml also hold.
var ENTITY_SPELLED = ["&#91;x&#93;&#40;javascript&#58;alert&#40;1&#41;&#41;", "&ast;a&ast;", "&#91;b&#93;", "&#42;&#42;c&#42;&#42;", "&lbrack;d&rbrack;&lpar;javascript&colon;alert&lpar;1&rpar;&rpar;"]
var LINK_FORMS = ["[b](H)", "[![a](p.png)](H)", "[b][r]\n\n[r]: H"]

// The failure messages for one document folder, each form at the top of the document, inside a list item and inside a quote; an empty list means every case held.
function failures(dir) {
    var out = []
    var shapes = [{ name: "top", wrap: function (input) { return input } }].concat(NESTINGS.map(function (form) {
        return { name: form.name, wrap: function (input) { return nested(input, form) } }
    }))
    var plain = emittedHrefs(blocksOf('<a href="https://a.example/">LTK</a>', dir))
    if (plain.length !== 1 || plain[0] !== "https://a.example/")
        out.push("the anchor check does not see a plain raw HTML link")
    shapes.forEach(function (shape) {
        var at = shape.name + " "
        var nestedPlain = emittedHrefs(blocksOf(shape.wrap('<a href="https://a.example/">LTK</a>'), dir))
        if (nestedPlain.length !== 1 || nestedPlain[0] !== "https://a.example/")
            out.push("the anchor check does not see a plain raw HTML link in the " + shape.name)
        for (var s = 0; s < SPELLED_ADDRESSES.length; s++) {
            // A refused address leaves the anchor's text unlinked, and the product's own gate must pass every address that stays.
            for (var w = 0; w < ANCHOR_WRAPPERS.length; w++) {
                var anchored = blocksOf(shape.wrap(ANCHOR_WRAPPERS[w].replace("H", SPELLED_ADDRESSES[s])), dir)
                var hrefs = emittedHrefs(anchored)
                if (!hrefs.every(Resolve.isLinkTarget) || JSON.stringify(anchored).indexOf("LTX") < 0)
                    out.push(at + "raw HTML anchor spelled through references kept a refused address " + s + "/" + w + " " + JSON.stringify(hrefs))
            }
            var pictured = flatBlocks(blocksOf(shape.wrap('<img src="' + SPELLED_ADDRESSES[s] + '">\n\n<p align="center"><img src="' + SPELLED_ADDRESSES[s] + '"></p>'), dir))
            var urls = pictured.filter(function (block) { return block.type === "image" }).map(function (block) { return block.url })
            if (/javascript:|data:/i.test(JSON.stringify(pictured)) || !urls.every(function (url) { return url.indexOf("file://" + dir + "/") === 0 }))
                out.push(at + "raw HTML image spelled through references left the document folder " + s + " " + JSON.stringify(urls))
            // A Markdown destination spelled the same ways, around an image too, never becomes a link.
            for (var f = 0; f < LINK_FORMS.length; f++) {
                var linked = blocksOf(shape.wrap(LINK_FORMS[f].split("H").join(SPELLED_ADDRESSES[s])), dir)
                if (JSON.stringify(linked).indexOf("](") >= 0 || emittedHrefs(linked).length > 0)
                    out.push(at + "Markdown link spelled through references became a link " + s + "/" + f)
            }
        }
        for (var m = 0; m < MARK_WRAPPERS.length; m++) {
            var drawn = runText(blocksOf(shape.wrap(MARK_WRAPPERS[m].split("T").join(MARK_TEXT)), dir)).replace(/<a href="[^"]*"/g, "<a")
            if (/[\[\]*`]/.test(drawn))
                out.push(at + "a reference-spelled mark inside an HTML wrapper reached Qt as syntax " + m + " " + drawn)
        }
        // A bare paragraph carrying the marks as references reads them as text, never as emphasis, a link or an anchor.
        for (var e = 0; e < ENTITY_SPELLED.length; e++) {
            var spelledRuns = runText(blocksOf(shape.wrap(ENTITY_SPELLED[e]), dir))
            if (/[\[\]*]|<a /.test(spelledRuns))
                out.push(at + "a reference-spelled mark reached Qt as syntax " + e + " " + spelledRuns)
        }
    })
    return out
}
