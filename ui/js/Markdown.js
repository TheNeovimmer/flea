.pragma library

.import "Format.js" as Format
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml
.import "MdInline.js" as Md
.import "MdRun.js" as Run
.import "MdResolve.js" as Resolve
.import "MdRefs.js" as Refs
.import "MdLeaf.js" as Leaf
.import "MdBlocks.js" as Blocks

// Markdown's stable API: remote images become a placeholder, only files inside the document folder load.

var RENDERED = "rendered"
var SOURCE = "source"

// Deeper nesting than this shows the source behind one notice.
var NESTING_LIMIT = Blocks.NESTING_LIMIT

function deepNotice() {
    return "Rendered preview skipped: nesting is deeper than " + NESTING_LIMIT + " levels. Showing the source."
}

function isView(value) {
    return value === RENDERED || value === SOURCE
}

function toggled(value) {
    return value === RENDERED ? SOURCE : RENDERED
}

function isRemoteUrl(url) {
    return MdUrl.isRemoteUrl(url)
}

// Only these three schemes open in the default application; relative links, anchors and every other scheme open nothing.
function isExternalLink(url) {
    return Resolve.isExternalLink(url)
}

function hostOf(url) {
    return MdUrl.hostOf(url)
}

function dirOf(path) {
    return MdUrl.dirOf(path)
}

function placeholder(host) {
    return MdUrl.placeholder(host)
}

function lineCount(text) {
    var body = String(text)
    // Match src/backend/linecount.rs: a trailing LF ends a line; only an unterminated tail adds one.
    return body.length === 0 ? 0 : body.split("\n").length - (body.endsWith("\n") ? 1 : 0)
}

function countLine(n) {
    return n === 1 ? "1 line" : Format.count(n) + " lines"
}

function classifyImage(raw, dir) {
    return MdUrl.classifyImage(raw, dir)
}

// The URL half of an inline image target, before an optional quoted title.
function targetOf(inner) {
    var text = String(inner).trim()
    if (text.charAt(0) === "<") {
        var close = text.indexOf(">")
        return close > 0 ? text.slice(1, close) : text
    }
    var space = text.search(/\s/)
    return space >= 0 ? text.slice(0, space) : text
}

function imageFor(alt, raw, dir) {
    var seen = classifyImage(targetOf(raw), dir)
    if (seen.kind === "remote")
        return "\n\n" + placeholder(seen.host) + "\n\n"
    if (seen.kind === "local")
        return "![" + alt + "](" + seen.url + ")"
    return alt
}

// A raw HTML image tag, neutralised here rather than trusted to a renderer option.
function tagFor(tag, dir) {
    var tokens = []
    var san = MdHtml.sanitizeTag(String(tag), dir, tokens)
    if (san.drop !== null)
        return ""
    var emit = san.emit
    for (var i = 0; i < tokens.length; i++)
        emit = emit.split(MdHtml.openToken() + i + MdHtml.closeToken()).join(tokens[i])
    if (emit.indexOf("<img") === 0)
        return emit
    if (emit.indexOf("Remote image not loaded") >= 0)
        return "\n\n" + emit.trim() + "\n\n"
    return emit
}

// Reference definitions, `[id]: url`, resolved against the same rule.
function definitions(source) {
    return Blocks.collectReferences(source).defs
}

// One HTML escape pass: & < > and every ASCII punctuation character become numeric entities.
function htmlEscaped(text) {
    return Md.escapeHtmlText(text)
}

// An inline code span as styled HTML, or the original when no usable chrome arrived.
function codeHtml(content, chrome, original) {
    var held = Md.codeHtml(content, chrome, "")
    return held === null ? original : held
}

function linkTarget(inner) {
    return targetOf(inner)
}

// A prose run through the single-pass driver, definition lines stripped first.
function resolveRun(joined, dir, defs, chrome, ink) {
    var tokens = []
    var lines = String(joined).split("\n")
    for (var i = 0; i < lines.length; i++)
        lines[i] = Refs.killDefinition(lines[i])
    var numbers = {}
    var html = Run.parseInline(lines.join("\n"), dir, defs || {}, numbers, chrome, ink, tokens)
    return html
}

function prepare(source, dir, defs, chrome, ink) {
    return Blocks.prepare(source, dir, defs, chrome, ink)
}

function listMarker(line) {
    return Blocks.listMarker(line)
}

function imageParagraph(line, dir, defs) {
    return Leaf.standaloneImage(String(line), dir, defs || {})
}

function delimAligns(line) {
    return Leaf.delimAligns(line)
}

function splitRow(line) {
    return Leaf.splitRow(line)
}

// A big document's first screen draws from this many blocks, which the worker sends ahead of the rest.
var HEAD_BLOCKS = 96

function blocks(source, dir, chrome, ink) {
    return Blocks.blocks(source, dir, chrome, ink)
}

// The deep verdict reads this many bytes of the head at most: the pass is forward only, so a head that nests too deep is deep in the whole text.
var DEEP_HEAD_BYTES = 16384

// Sample: "> ".repeat(400) + "x" answers { deep: true, scanned: 801 }; a head that never nests too deep answers deep false.
function deepHead(source) {
    var head = String(source)
    if (head.length > DEEP_HEAD_BYTES)
        head = head.slice(0, Math.max(0, head.lastIndexOf("\n", DEEP_HEAD_BYTES)))
    var state = Blocks.referenceState()
    Blocks.blockPass(MdHtml.documentText(head).split("\n"), state, undefined, true)
    return { deep: state.deep === true, scanned: head.length }
}

// The one block a document nested too deep parses to, so a deep head lands it with no parse of the text.
function deepBlocks() {
    return [{ type: "deep", limit: NESTING_LIMIT }]
}

// The fenced info string naming a figure, or "" for code. Tests pin it.
function figureKind(info) {
    return Blocks.figureKind(info)
}

// Every figure block in document order, top level and held by a quote or a list item at any depth, pushed onto out.
function figuresIn(blocks, out) {
    for (var i = 0; i < blocks.length; i++) {
        var block = blocks[i]
        if (block.type === "figure")
            out.push(block)
        else if (block.type === "quote" && block.parts !== undefined)
            figuresIn(block.parts, out)
        else if (block.type === "list" && block.parts !== undefined)
            for (var k = 0; k < block.parts.length; k++)
                if (block.parts[k])
                    figuresIn(block.parts[k], out)
    }
    return out
}

// The Source view lays out chunks of whole lines about this many characters long, so a screenful of a large file costs a few chunks.
var SOURCE_CHUNK_CHARS = 4096
// No chunk is longer than this: a line that runs past it is cut at its last space past SOURCE_CHUNK_CHARS, or at the limit when it has none.
var SOURCE_CHUNK_MAX = 2 * SOURCE_CHUNK_CHARS

// A high surrogate that ends a hard cut steps the cut back one unit, so no chunk splits an astral pair.
var HIGH_FIRST = 0xD800
var HIGH_LAST = 0xDBFF

// Sample: 20000 chars in lines of 100 answers [0, 4100, 8200, 12300]; a short line straddling the window ends before it, an 8192-char line ends at its newline, a spaceless astral run steps back off a split pair.
function sourceChunkStarts(text) {
    var starts = [0]
    var from = 0
    while (text.length - from > SOURCE_CHUNK_MAX) {
        var cut = text.indexOf("\n", from + SOURCE_CHUNK_CHARS)
        var next
        if (cut >= 0 && cut <= from + SOURCE_CHUNK_MAX) {
            next = cut + 1
        } else {
            var back = text.lastIndexOf("\n", from + SOURCE_CHUNK_CHARS - 1)
            if (back > from) {
                next = back + 1
            } else {
                var space = text.lastIndexOf(" ", from + SOURCE_CHUNK_MAX - 1)
                next = space >= from + SOURCE_CHUNK_CHARS ? space + 1 : from + SOURCE_CHUNK_MAX
                if (next === from + SOURCE_CHUNK_MAX) {
                    var unit = text.charCodeAt(next - 1)
                    if (unit >= HIGH_FIRST && unit <= HIGH_LAST) {
                        next--
                    }
                }
            }
        }
        starts.push(next)
        from = next
    }
    return starts
}

// Chunk i without the newline that ends it, if one does; a cut inside a line drops nothing, so the chunks are the text again.
function sourceChunk(text, starts, i) {
    var end = i + 1 < starts.length ? starts[i + 1] : text.length
    if (i + 1 < starts.length && text.charAt(end - 1) === "\n")
        end--
    return text.slice(starts[i], end)
}
