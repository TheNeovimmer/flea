.pragma library

// MdHtml: the raw-HTML allowlist for rendered Markdown. Every tag the file
// carries is re-emitted by this parser or dropped by it; no raw < survives
// outside code except the tags built here. One forward scan, no backtracking.
.import "MdUrl.js" as MdUrl

// Held-span tokens: private-use characters md4c passes through untouched, so
// spans the parser resolved are restored after every escaping pass. One table
// holds code, tags, images and math alike; a single restore ends the pipeline.
function openToken() {
    return String.fromCharCode(57346)
}

function closeToken() {
    return String.fromCharCode(57347)
}

function holdToken(tokens, html) {
    var token = openToken() + tokens.length + closeToken()
    tokens.push(html)
    return token
}

// Tags whose content is dropped with them: active content and whole-document
// namespaces a preview must never instantiate.
var DROP_CONTENT = { script: 1, style: 1, iframe: 1, object: 1, embed: 1,
    template: 1, noscript: 1, svg: 1, math: 1 }

// Tags re-emitted with the attributes below; any other tag is dropped and its
// content kept. font carries only the color the parser's own links wrap in.
var ALLOWED = { a: 1, b: 1, strong: 1, i: 1, em: 1, u: 1, s: 1, del: 1,
    strike: 1, sub: 1, sup: 1, kbd: 1, code: 1, br: 1, small: 1, mark: 1,
    span: 1, p: 1, div: 1, h1: 1, h2: 1, h3: 1, h4: 1, h5: 1, h6: 1, hr: 1,
    img: 1, picture: 1, source: 1, details: 1, summary: 1, table: 1,
    thead: 1, tbody: 1, tr: 1, th: 1, td: 1, ul: 1, ol: 1, li: 1,
    blockquote: 1, pre: 1, font: 1 }

// Attributes that survive on any allowed tag. Every style, class, id,
// background, srcset, poster, data-* and on* attribute is dropped.
var GLOBAL_ATTRS = { align: 1, alt: 1, width: 1, height: 1, title: 1,
    colspan: 1, rowspan: 1 }

// Void tags never take a closing tag.
var VOID = { br: 1, hr: 1, img: 1, source: 1 }

function isNameChar(c) {
    return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9")
}

// Read one raw tag starting at text[i] === "<". Answers {tag, end} with end
// past the closing ">", or null when no tag opens there. The closing bracket
// is found with a native search and quote-checked only over the candidate, so
// a "<" with no ">" anywhere ahead costs one native scan: the first such miss
// marks every later "<" dead exactly, and dense "<" inputs stay linear. Tags
// longer than 4 KiB read as literal "<", which is display-only: escaping can
// never load, whatever md4c would have made of the tag.
function readTag(text, i, dead) {
    if (dead !== undefined && dead !== null && i < dead.tagDead)
        return null
    var gt = text.indexOf(">", i + 1)
    if (gt < 0) {
        if (dead !== undefined && dead !== null)
            dead.tagDead = text.length
        return null
    }
    if (gt - i > 4096)
        return null
    var dq = text.indexOf('"', i + 1)
    var sq = text.indexOf("'", i + 1)
    if ((dq < 0 || dq > gt) && (sq < 0 || sq > gt))
        return { tag: text.slice(i, gt + 1), end: gt + 1 }
    var quote = ""
    var j = i + 1
    while (j < gt) {
        var c = text.charAt(j)
        if (quote !== "") {
            if (c === quote)
                quote = ""
        } else if (c === '"' || c === "'") {
            quote = c
        }
        j++
    }
    if (quote !== "")
        return null
    return { tag: text.slice(i, gt + 1), end: gt + 1 }
}

// Split a raw tag into its name, closing flag and raw attribute body.
function tagHead(tag) {
    var i = 1
    var closing = false
    if (tag.charAt(i) === "/") {
        closing = true
        i++
    }
    var name = ""
    while (i < tag.length && isNameChar(tag.charAt(i))) {
        name += tag.charAt(i).toLowerCase()
        i++
    }
    return { name: name, closing: closing, rest: tag.slice(i, tag.length - 1) }
}

// One attribute value with entities decoded for the safety checks below.
function attrKept(name, value, tagName) {
    var seen = MdUrl.canonicalUrl(value).toLowerCase()
    // CSS url() in any attribute loads, so the attribute goes.
    if (/url\s*\(/i.test(seen))
        return false
    if (name === "href") {
        if (tagName !== "a")
            return false
        // Links never fetch: http, https, mailto, relative and #anchor stay.
        if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(seen))
            return seen.indexOf("http:") === 0 || seen.indexOf("https:") === 0
                || seen.indexOf("mailto:") === 0 ? true : false
        return true
    }
    if (name === "src")
        return tagName === "img" || tagName === "source"
    if (name === "color")
        return tagName === "font"
    return GLOBAL_ATTRS.hasOwnProperty(name)
}

function escapeAttr(value) {
    return String(value).replace(/&/g, "&#38;").replace(/"/g, "&#34;").replace(/</g, "&#60;")
}

// First srcset candidate classifying local, or its remote flag, else null.
function srcsetPick(value, dir) {
    var parts = String(value).split(",")
    var remote = null
    for (var i = 0; i < parts.length; i++) {
        var cand = parts[i].replace(/^\s+|\s+$/g, "").split(/\s+/)[0] || ""
        if (cand.length === 0)
            continue
        var seen = MdUrl.classifyImage(cand, dir)
        if (seen.kind === "local")
            return { kind: "local", url: seen.url }
        if (seen.kind === "remote" && remote === null)
            remote = seen.host
    }
    if (remote !== null)
        return { kind: "remote", host: remote }
    return null
}

// Sanitize one raw tag. Answers {emit, drop} where drop names a DROP_CONTENT
// element the caller must skip to the matching close. emit carries tokens for
// images the parser resolved, never raw URLs.
function sanitizeTag(tag, dir, tokens) {
    function hold(html) {
        return holdToken(tokens, html)
    }
    var head = tagHead(tag)
    var name = head.name
    if (name.length === 0)
        return { emit: "&#60;", drop: null }
    if (DROP_CONTENT.hasOwnProperty(name))
        return { emit: "", drop: head.closing ? null : name }
    if (!ALLOWED.hasOwnProperty(name))
        return { emit: "", drop: null }
    // details shows its body; summary draws bold through the markdown parser.
    if (name === "details")
        return { emit: "", drop: null }
    if (name === "summary")
        return { emit: head.closing ? "**" : "**", drop: null }
    if (head.closing)
        return { emit: "</" + name + ">", drop: null }
    var out = ""
    var rest = head.rest
    var i = 0
    var kept = ""
    var srcSeen = null
    var srcsetSeen = null
    var altSeen = ""
    var selfClose = false
    while (i < rest.length) {
        while (i < rest.length && /\s/.test(rest.charAt(i)))
            i++
        if (i >= rest.length)
            break
        if (rest.charAt(i) === "/") {
            selfClose = true
            i++
            continue
        }
        var aname = ""
        while (i < rest.length && /[^\s=/>]/.test(rest.charAt(i))) {
            aname += rest.charAt(i).toLowerCase()
            i++
        }
        if (aname.length === 0) {
            i++
            continue
        }
        while (i < rest.length && /\s/.test(rest.charAt(i)))
            i++
        var value = null
        if (rest.charAt(i) === "=") {
            i++
            while (i < rest.length && /\s/.test(rest.charAt(i)))
                i++
            var q = rest.charAt(i)
            if (q === '"' || q === "'") {
                i++
                var start = i
                while (i < rest.length && rest.charAt(i) !== q)
                    i++
                value = rest.slice(start, i)
                i++
            } else {
                var begin = i
                while (i < rest.length && !/[\s>]/.test(rest.charAt(i)) && rest.charAt(i) !== "/")
                    i++
                value = rest.slice(begin, i)
            }
        }
        // Every style, class, id, background, srcset, poster, data-* and on*
        // attribute is dropped, whatever its value.
        if (aname === "style" || aname === "class" || aname === "id"
                || aname === "background" || aname === "poster"
                || aname.indexOf("data-") === 0 || aname.indexOf("on") === 0)
            continue
        if (aname === "srcset") {
            if (value !== null)
                srcsetSeen = value
            continue
        }
        if (aname === "src" && (name === "img" || name === "source")) {
            srcSeen = value === null ? "" : value
            continue
        }
        if (aname === "alt")
            altSeen = value === null ? "" : value
        if (value === null || attrKept(aname, value, name))
            kept += " " + aname + (value === null ? "" : '="' + escapeAttr(value) + '"')
    }
    if (name === "img" || name === "source") {
        var picked = null
        if (srcSeen !== null)
            picked = MdUrl.classifyImage(srcSeen, dir)
        else if (srcsetSeen !== null)
            picked = srcsetPick(srcsetSeen, dir)
        if (picked !== null && picked.kind === "local")
            return { emit: hold('<img src="' + picked.url + '" alt="' + escapeAttr(altSeen) + '">'), drop: null }
        if (picked !== null && picked.kind === "remote")
            return { emit: "\n\n" + MdUrl.placeholder(picked.host) + "\n\n", drop: null }
        return { emit: MdUrl.canonicalUrl(altSeen).length > 0 ? escapeAttr(altSeen) : "", drop: null }
    }
    var close = (selfClose || VOID.hasOwnProperty(name)) ? " /" : ""
    return { emit: "<" + name + kept + close + ">", drop: null }
}
