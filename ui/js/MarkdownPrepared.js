.pragma library

.import "Kinds.js" as Kinds
.import "ExtThumbs.js" as ExtThumbs

// The one parsed Markdown document Quick Look takes without parsing, keyed by its text so an edited file misses and one past MAX_BYTES is never held.
var entry = null
var MAX_BYTES = 65536
// The st_mode file-type mask and the regular-file type, which a listing row's p carries whole.
var S_IFMT = 0xF000
var S_IFREG = 0x8000

// Sample input: the row { n: "a.md", d: false } answers true; { n: "a.md", d: true }, { n: "a.txt", d: false } and null answer false.
// Whether the cursor row is a Markdown file by name, the one trigger Quick Look's warm and its ahead-of-Space build share.
function isMarkdownRow(row) {
    return row !== null && row !== undefined && !row.d && Kinds.isMarkdown(row.n)
}

// Sample input: a 900 byte regular "a.md" row on class "" with the class known answers true; a named pipe row, class "network" or an unknown class answers false.
// Only a regular local file under MAX_BYTES in a folder whose class has landed is read ahead or inside the key; cifs, nfs and listed FUSE shares classify "network" in extclass.rs.
function readsInline(row, storageClass, storageKnown) {
    if (!row || row.d || !storageKnown || ExtThumbs.present(storageClass) || !Kinds.isMarkdown(row.n))
        return false
    return (row.p & S_IFMT) === S_IFREG && row.s > 0 && row.s <= MAX_BYTES
}

// A picture at most this big is decoded ahead of the open, and a document is asked about at most this many.
var PICTURE_MAX_BYTES = 262144
var PICTURE_LIMIT = 8
var FILE_SCHEME_LENGTH = 7
// The stat child that sizes the pictures is dropped after this long, so a hung mount holds nothing past it.
var PICTURE_SIZE_DEADLINE_MS = 1500

// Sample input: "file:///d/b%20c.png" answers "/d/b c.png"; "file:///d/100%.png" (a stray percent) answers "".
function pathOfUrl(url) {
    try {
        return decodeURIComponent(String(url).slice(FILE_SCHEME_LENGTH))
    } catch (e) {
        return ""
    }
}

// Sample input: path "/d/img/a.png" in dir "/d" answers true; "/mnt/nas/a.png" and "/d/../e/a.png" answer false.
// Only a picture under the document's folder shares the storage class readsInline cleared, so a stat never reaches another mount.
function insideDir(path, dir) {
    return dir !== "" && path.indexOf(dir + "/") === 0 && path.split("/").indexOf("..") < 0
}

// Sample input: blocks [{ type: "image", url: "file:///d/a.png" }, { type: "images", items: [{ url: "file:///d/b%20c.png" }, { url: "file:///d/a.png" }] }, { type: "run" }] in dir "/d" answer ["file:///d/a.png", "file:///d/b%20c.png"].
// The local pictures a parsed document draws at its top level under its own folder, each once, in reading order, at most limit of them.
function pictureUrls(blocks, limit, dir) {
    var urls = []
    function add(url) {
        if (typeof url === "string" && url.indexOf("file://") === 0 && urls.length < limit && urls.indexOf(url) < 0
                && insideDir(pathOfUrl(url), dir))
            urls.push(url)
    }
    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i]
        if (b.type === "image") {
            add(b.url)
        } else if (b.type === "images" && b.items !== undefined) {
            for (var j = 0; j < b.items.length; j++)
                add(b.items[j].url)
        }
    }
    return urls
}

// Sample input: urls ["file:///d/a.png", "file:///d/big.png", "file:///d/gone.png"] with the stat text "2048\t/d/a.png\n900000\t/d/big.png\n" answer ["file:///d/a.png"].
// The pictures stat sized at PICTURE_MAX_BYTES or less; a name stat did not print (a missing file) or a bigger one keeps the open's own load.
function smallPictures(urls, statText) {
    var sizes = {}
    var lines = String(statText).split("\n")
    for (var i = 0; i < lines.length; i++) {
        var tab = lines[i].indexOf("\t")
        if (tab > 0)
            sizes[lines[i].slice(tab + 1)] = Number(lines[i].slice(0, tab))
    }
    return urls.filter(function (url) {
        var size = sizes[pathOfUrl(url)]
        return size !== undefined && size > 0 && size <= PICTURE_MAX_BYTES
    })
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
