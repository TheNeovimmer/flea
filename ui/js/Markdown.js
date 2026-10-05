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

function blocks(source, dir, chrome, ink) {
    return Blocks.blocks(source, dir, chrome, ink)
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
