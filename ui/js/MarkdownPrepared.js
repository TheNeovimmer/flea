.pragma library

.import "Kinds.js" as Kinds
.import "ExtThumbs.js" as ExtThumbs

// The one parsed Markdown document Quick Look takes without parsing, keyed by its text so an edited file misses and one past MAX_BYTES is never held.
var entry = null
var MAX_BYTES = 65536
// The st_mode file-type mask and the regular-file type, which a listing row's p carries whole.
var S_IFMT = 0xF000
var S_IFREG = 0x8000

// Sample input: a 900 byte regular "a.md" row on class "" answers true; a named pipe row (size 0) or class "network" answers false.
// Only a regular local file under MAX_BYTES is read ahead or inside the key; cifs, nfs and listed FUSE shares classify "network" in extclass.rs.
function readsInline(row, storageClass) {
    if (!row || row.d || ExtThumbs.present(storageClass) || !Kinds.isMarkdown(row.n))
        return false
    return (row.p & S_IFMT) === S_IFREG && row.s > 0 && row.s <= MAX_BYTES
}

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
