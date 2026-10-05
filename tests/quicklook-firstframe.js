.pragma library
.import "flea/js/Markdown.js" as Markdown

// Object keys in sorted order, because a block that crossed the worker's boundary comes back with its keys sorted.
function canon(v) {
    if (v === null || typeof v !== "object") return JSON.stringify(v)
    if (Array.isArray(v)) return "[" + v.map(canon).join(",") + "]"
    return "{" + Object.keys(v).sort().filter(function (k) { return v[k] !== undefined }).map(function (k) { return JSON.stringify(k) + ":" + canon(v[k]) }).join(",") + "}"
}

// The blocks the card took from the prepared entry (the worker's parse) against a fresh parse of the same text on the merged parser, kinds the stage added among them.
function sameAsFreshParse(root, d, n) {
    var fresh = Markdown.blocks(d.rawText, Markdown.dirOf(d.path), d.chromeHex, d.inkHex)
    var kinds = fresh.map(function (b) { return b.type })
    var empty = fresh.some(function (b) { return b.type === "heading" && b.text === "" })
    if (kinds.indexOf("images") < 0 || kinds.indexOf("image") < 0 || kinds.indexOf("quote") < 0 || !empty)
        root.fail("step " + n + " fixture lost a kind the prepared parse must carry: " + kinds.join("+"))
    if (canon(d.blockList) !== canon(fresh))
        root.fail("step " + n + " drew a prepared parse that differs from a fresh parse of the same text")
    else
        root.log("PARSE " + n + " prepared equals fresh blocks=" + fresh.length)
}
