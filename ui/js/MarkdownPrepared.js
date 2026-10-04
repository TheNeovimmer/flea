.pragma library

// The one parsed Markdown document Quick Look can take without parsing: the last one Quick Look showed or a resting cursor prepared.
// It holds the text it was parsed from, so a file that changed since misses, and a document past MAX_BYTES is never held.
var entry = null
var MAX_BYTES = 65536

// QML color components read 0..1, so the hex a style attribute needs is assembled, never coerced.
// Sample input: a colour with r 0.0627, g 0.0745, b 0.0745 answers "#101313".
function hexOf(c) {
    function byte(v) {
        var s = Math.round(v * 255).toString(16)
        return s.length < 2 ? "0" + s : s
    }
    return "#" + byte(c.r) + byte(c.g) + byte(c.b)
}

function store(path, text, dir, chrome, ink, blocks) {
    if (text.length > MAX_BYTES) return
    entry = { path: path, text: text, dir: dir, chrome: chrome, ink: ink, blocks: blocks }
}

// The blocks parsed from exactly this text with exactly these inputs, or null.
function take(path, text, dir, chrome, ink) {
    var e = entry
    if (e === null || e.path !== path || e.dir !== dir || e.chrome !== chrome || e.ink !== ink || e.text !== text)
        return null
    return e.blocks
}
