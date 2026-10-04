.pragma library

// MdResolve: resolve bracket pairs into held local images, escaped placeholders, safe links or literal text.
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml
.import "MdInline.js" as Md
.import "MdRefs.js" as Refs
.import "MdEntity.js" as Ent

var MAX_STYLED_SPANS = 1024
var hasOwn = Object.prototype.hasOwnProperty
// The bytes a markdown destination cannot hold, as percent escapes.
var PERCENT_ESCAPE = { " ": "%20", "(": "%28", ")": "%29" }

// Links never fetch, but javascript: and data: hrefs must never be emitted: only http, https, mailto, relative and #anchor targets become anchors.
function isLinkTarget(url) {
    var seen = MdHtml.normalizedTarget(MdUrl.canonicalUrl(url))
    var m = /^[a-zA-Z][a-zA-Z0-9+.-]*:/.exec(seen)
    if (m === null)
        return true
    var scheme = m[0].toLowerCase()
    return scheme === "http:" || scheme === "https:" || scheme === "mailto:"
}

// Sample input: "https://a.example" and "mailto:a@b.example" are external; "./x.md", "#top" and "ftp://h/f" are not.
function isExternalLink(url) {
    var seen = MdHtml.normalizedTarget(MdUrl.canonicalUrl(url))
    return /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(seen) && isLinkTarget(url)
}

// Sample input: "(/u)" after a label answers { url: "/u", end: 4 }; "[ref]" and "[]" read a definition, as does a bare label (raw).
function readDestination(body, j, raw, defs) {
    var found = readRawDestination(body, j, raw, defs)
    return found === null ? null : { url: Ent.decodeReferences(found.url), end: found.end }
}

function readRawDestination(body, j, raw, defs) {
    var inline = body.charAt(j) === "(" ? Md.readInlineTarget(body, j) : null
    if (inline !== null)
        return { url: inline.url, end: inline.end }
    if (body.charAt(j) === "[") {
        var ref = Md.readLabelRef(body, j)
        var label = ref === null ? "" : ref.label.length > 0 ? ref.label : raw
        if (label.length > 0 && hasOwn.call(defs, Md.normalizeLabel(label)))
            return { url: defs[Md.normalizeLabel(label)], end: ref.end }
        return null
    }
    if (raw.length > 0 && hasOwn.call(defs, Md.normalizeLabel(raw)))
        return { url: defs[Md.normalizeLabel(raw)], end: j }
    return null
}

// An alt text is the label's text alone: tags go, numeric entities turn back into characters.
function plainText(html) {
    return String(html).replace(/<[^>]*>/g, "").replace(/&#(\d+);/g, function (m, n) {
        return String.fromCharCode(parseInt(n, 10))
    })
}

// Resolve one bracket pair into text, a -1-i token reference or null; raw is its label, label() its resolved markup and target its destination.
function resolvePair(raw, target, bang, dir, ink, tokens, label) {
    // A backslash before punctuation is consumed by the backslash: the alt and the label display the punctuation, never the escape.
    var clean = String(raw).replace(/\\([!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~])/g, "$1")
    if (bang) {
        clean = label === undefined ? clean : plainText(label())
        var cls = MdUrl.classifyImage(target, dir)
        if (cls.kind === "remote")
            return "\n\n" + MdUrl.placeholder(Md.escapeHtmlText(cls.host)) + "\n\n"
        if (cls.kind === "local") {
            var alt = Md.escapeHtmlText(clean)
            var url = cls.url.replace(/\(/g, "%28").replace(/\)/g, "%29")
            tokens.push("![" + alt + "](" + url + ")")
            return -1 - (tokens.length - 1)
        }
        return Md.escapeHtmlText(clean)
    }
    target = MdHtml.normalizedTarget(target)
    if (!isLinkTarget(target))
        return Md.escapeHtmlText("[" + clean + "](" + target + ")")
    var shown = label === undefined ? clean : label()
    // Inside an html link the renderer would draw a linked image's alt text beside it, so its own link syntax carries that label.
    var html = label !== undefined && shown.indexOf("![") >= 0
        ? "[" + shown + "](" + target.replace(/[ ()]/g, function (c) { return PERCENT_ESCAPE[c] }) + ")"
        : Md.linkHtml(shown, target, ink, label !== undefined)
    if (html === null)
        return Md.escapeHtmlText("[" + clean + "](" + target + ")")
    tokens.push(html)
    return -1 - (tokens.length - 1)
}

// Push sanitizer output, splitting any held-span markers it carries into token references. Tags are short, so this walk is bounded by the tag length.
function pushEmitted(out, tokens, emit) {
    var open = MdHtml.openToken()
    if (emit.indexOf(open) < 0) {
        out.push(emit)
        return
    }
    var close = MdHtml.closeToken()
    var plain = ""
    var i = 0
    while (i < emit.length) {
        if (emit.charAt(i) !== open) {
            plain += emit.charAt(i)
            i++
            continue
        }
        var j = i + 1
        var num = ""
        while (j < emit.length && emit.charAt(j) !== close) {
            num += emit.charAt(j)
            j++
        }
        var idx = parseInt(num, 10)
        if (j < emit.length && idx >= 0 && idx < tokens.length) {
            if (plain !== "") {
                out.push(plain)
                plain = ""
            }
            out.push(-1 - idx)
            i = j + 1
        } else {
            plain += emit.charAt(i)
            i++
        }
    }
    if (plain !== "")
        out.push(plain)
}

// In-place text equality without slicing either side: allocation-free repeat detection for dense span runs.
function sameText(body, a, b, len) {
    for (var k = 0; k < len; k++) {
        if (body.charAt(a + k) !== body.charAt(b + k))
            return false
    }
    return true
}

// One styled span, cached by content: dense documents repeat the same spans thousands of times, and each rebuild costs a regex the cache pays once.
function styledSpan(kind, content, chrome, cache) {
    var key = kind + "\n" + content
    if (cache.hasOwnProperty(key))
        return cache[key]
    var held = Md.codeHtml(content, chrome, kind)
    var count = 0
    for (var existing in cache)
        count++
    if (count < MAX_STYLED_SPANS)
        cache[key] = held
    return held
}

// Sample input: '<img src="pic.png">' at its "<" resolves a tag; '<https://a.example>' resolves an autolink.
function parseAngle(body, i, dir, ink, styleLinks, dead, tokens, out) {
    var auto = Md.readAutolink(body, i)
    if (auto !== null && !isLinkTarget(auto.href))
        auto = null
    if (auto !== null) {
        if (!styleLinks) {
            out.push(Md.escapeHtmlText(auto.url))
            i = auto.end
            return i
        }
        var ahtml = Md.linkHtml(auto.url, auto.href, ink)
        if (ahtml === null)
            out.push(Md.escapeHtmlText(auto.url))
        else {
            tokens.push(ahtml)
            out.push(-1 - (tokens.length - 1))
        }
        i = auto.end
        return i
    }
    if (body.slice(i, i + 4) === "<!--") {
        if (dead.commentDead) {
            out.push("&#60;")
            i++
            return i
        }
        var ce = body.indexOf("-->", i + 4)
        if (ce < 0) {
            dead.commentDead = true
            out.push("&#60;")
            i++
        } else {
            i = ce + 3
        }
        return i
    }
    if (body.charAt(i + 1) === "!" || body.charAt(i + 1) === "?") {
        var decl = MdHtml.readTag(body, i, dead)
        if (decl === null) {
            out.push("&#60;")
            i++
        } else {
            i = decl.end
        }
        return i
    }
    var found = MdHtml.readTag(body, i, dead)
    if (found === null || MdHtml.tagHead(found.tag).name.length === 0) {
        out.push("&#60;")
        i++
        return i
    }
    var san = MdHtml.sanitizeTag(found.tag, dir, tokens)
    pushEmitted(out, tokens, san.emit)
    i = found.end
    if (san.drop !== null)
        i = Refs.skipDropContent(body, i, san.drop, dead)
    return i
}

// Sample input: "see https://a.example/x now" at the "h" answers the index after the address; no bare address answers -1.
function bareAt(body, i, ink, styleLinks, tokens, out) {
    var bare = Md.readBarelink(body, i)
    if (bare === null || !isLinkTarget(bare.href))
        return -1
    var url = bare.url
    var href = bare.href
    // GFM leaves a trailing entity reference such as "&hl;" out of the address.
    var entity = body.charAt(bare.end) === ";" ? /&[A-Za-z0-9]+$/.exec(url) : null
    if (entity !== null) {
        url = url.slice(0, entity.index)
        href = href.slice(0, href.length - (bare.url.length - url.length))
    }
    var html = styleLinks ? Md.linkHtml(url, href, ink) : null
    if (html === null) {
        out.push(Md.escapeHtmlText(url))
    } else {
        tokens.push(html)
        out.push(-1 - (tokens.length - 1))
    }
    return bare.end - (bare.url.length - url.length)
}
