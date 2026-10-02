.pragma library

.import "Format.js" as Format
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml
.import "MdInline.js" as Md
.import "MdRun.js" as Run
.import "MdRefs.js" as Refs
.import "MdLeaf.js" as Leaf
.import "MdBlocks.js" as Blocks

// Rendered Markdown's preprocessing: every image URL is resolved here, before
// Qt's own Markdown renderer sees the text, so no remote request is possible.
// Remote becomes the board's placeholder; only a file inside the document's
// folder loads, as its file:// URL. Fenced blocks and inline code are literal,
// and links carry no handler anywhere, so both stay ink. The pipeline is
// MdUrl (targets), MdHtml (allowlist), MdInline (scanners), MdRun (driver),
// MdRefs (definitions), MdLeaf (leaves) and MdBlocks (splitter); this file is
// the stable API the previews and the suites read.

var RENDERED = "rendered"
var SOURCE = "source"

function isView(value) {
    return value === RENDERED || value === SOURCE
}

function toggled(value) {
    return value === RENDERED ? SOURCE : RENDERED
}

function isRemoteUrl(url) {
    return MdUrl.isRemoteUrl(url)
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
    return body.length === 0 ? 0 : body.split("\n").length
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
    return Refs.collectDefs(String(source).split("\n")).defs
}

// One HTML escape pass: & < > and every ASCII punctuation character become
// numeric entities, so emphasis, links and autolinks cannot form inside
// converted spans and cells.
function htmlEscaped(text) {
    return Md.escapeHtmlText(text)
}

// An inline code span as styled HTML, or the original when no usable chrome arrived.
function codeHtml(content, chrome, original) {
    var held = Md.codeHtml(content, chrome, "")
    return held === null ? original : held
}

// CommonMark code spans over plain text, held as tokens for a caller that
// restores them styled. Unmatched runs stay literal. Linear: one run pairing.
function codeSpansHold(text, codes, chrome) {
    var body = String(text)
    var spans = Md.spanIntervals(body)
    var out = ""
    var at = 0
    for (var s = 0; s < spans.length; s++) {
        if (spans[s].kind !== "")
            continue
        out += body.slice(at, spans[s].from)
        var token = String.fromCharCode(57344) + codes.length + String.fromCharCode(57345)
        codes.push({ token: token, html: codeHtml(spans[s].content, chrome,
            body.slice(spans[s].from, spans[s].to)) })
        out += token
        at = spans[s].to
    }
    return out + body.slice(at)
}

function linkTarget(inner) {
    return targetOf(inner)
}

function linkHtml(label, inner, ink) {
    return Md.linkHtml(label, inner, ink)
}

// Inline links as font-wrapped anchors. Single forward scan, linear.
function rewriteLinks(text, ink) {
    var body = String(text)
    var out = ""
    var i = 0
    while (i < body.length) {
        var open = body.indexOf("[", i)
        if (open < 0 || (open > 0 && body.charAt(open - 1) === "!")) {
            out += body.slice(i)
            break
        }
        var close = Leaf.scanBalanced(body, open + 1)
        if (close < 0 || body.charAt(close + 1) !== "(") {
            out += body.slice(i, open + 1)
            i = open + 1
            continue
        }
        var target = Md.readInlineTarget(body, close + 1)
        if (target === null) {
            out += body.slice(i, open + 1)
            i = open + 1
            continue
        }
        var html = Md.linkHtml(body.slice(open + 1, close), target.url, ink)
        out += body.slice(i, open)
        out += html === null ? body.slice(open, target.end) : MdHtml.holdToken([], html)
        i = target.end
    }
    return out
}

// A prose run through the single-pass driver; definition lines lose their
// bracket so md4c never sees a reference this parser did not resolve.
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
    return Leaf.prepare(source, dir, defs, chrome, ink)
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

function tableBlock(head, aligns, rows) {
    return Leaf.tableBlock(head, aligns, rows)
}

function blocks(source, dir, chrome, ink) {
    return Blocks.blocks(source, dir, chrome, ink)
}
