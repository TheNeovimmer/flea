.pragma library

// MdHtml: one forward scan allowlists raw tags; only sanitized markup reaches md4c.
.import "MdUrl.js" as MdUrl
.import "MdEscape.js" as MdEscape

var TOKEN_OPEN = 57346
var TOKEN_CLOSE = 57347
var MAX_TAG_LENGTH = 4096

// Sample input: "\uE0020\uE003" becomes "\uFFFD0\uFFFD" before document parsing reserves its token markers.
function documentText(text) {
    return String(text).replace(/[\uE002\uE003]/g, "\uFFFD")
}

// Held spans use private-use delimiters and one shared token table, restored after escaping.
function openToken() {
    return String.fromCharCode(TOKEN_OPEN)
}

function closeToken() {
    return String.fromCharCode(TOKEN_CLOSE)
}

function holdToken(tokens, html) {
    var token = openToken() + tokens.length + closeToken()
    tokens.push(html)
    return token
}

// Tags whose content is dropped with them: active content and whole-document namespaces a preview must never instantiate.
var DROP_CONTENT = { script: 1, style: 1, iframe: 1, object: 1, embed: 1,
    template: 1, noscript: 1, svg: 1, math: 1 }

// Tags re-emitted with the attributes below; any other tag is dropped and its content kept. font carries only the color the parser's own links wrap in.
var ALLOWED = { a: 1, b: 1, strong: 1, i: 1, em: 1, u: 1, s: 1, del: 1,
    strike: 1, sub: 1, sup: 1, kbd: 1, code: 1, br: 1, small: 1, mark: 1,
    span: 1, p: 1, div: 1, h1: 1, h2: 1, h3: 1, h4: 1, h5: 1, h6: 1, hr: 1,
    img: 1, picture: 1, source: 1, details: 1, summary: 1, table: 1,
    thead: 1, tbody: 1, tr: 1, th: 1, td: 1, ul: 1, ol: 1, li: 1,
    blockquote: 1, pre: 1, font: 1 }

// Attributes that survive on any allowed tag. Every style, class, id, background, srcset, poster, data-* and on* attribute is dropped.
var GLOBAL_ATTRS = { align: 1, alt: 1, width: 1, height: 1, title: 1,
    colspan: 1, rowspan: 1 }

// Void tags never take a closing tag.
var VOID = { br: 1, hr: 1, img: 1, source: 1 }

function isNameChar(c) {
    return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9")
}

function isHtmlWhitespace(c) {
    return c === "\t" || c === "\n" || c === "\f" || c === "\r" || c === " "
}

// Sample: <img src="pic.png" alt="picture">. Quote-check only the candidate; a failed native search marks later openers dead, and oversized tags stay literal.
function readTag(text, i, dead) {
    if (dead !== undefined && dead !== null && i < dead.tagDead)
        return null
    var cached = dead !== undefined && dead !== null && dead.tagClose > i
    var gt = cached ? dead.tagClose : text.indexOf(">", i + 1)
    if (dead !== undefined && dead !== null && gt >= 0)
        dead.tagClose = gt
    if (gt < 0) {
        if (dead !== undefined && dead !== null)
            dead.tagDead = text.length
        return null
    }
    if (gt - i > MAX_TAG_LENGTH) {
        if (dead !== undefined && dead !== null)
            dead.tagDead = gt - MAX_TAG_LENGTH
        return null
    }
    var candidate = text.slice(i, gt + 1)
    var dq = candidate.indexOf('"')
    var sq = candidate.indexOf("'")
    if (dq < 0 && sq < 0)
        return { tag: candidate, end: gt + 1 }
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
    return { tag: candidate, end: gt + 1 }
}

// Sample input: ' a=b/' keeps the slash in b/; ' ==/' names '=' with value '/'; ' a="b"/' sets the self-closing flag.
function scanAttributes(rest) {
    var i = 0
    var attributes = []
    var valid = true
    var selfClose = false
    while (i < rest.length) {
        while (i < rest.length && isHtmlWhitespace(rest.charAt(i)))
            i++
        if (i >= rest.length)
            break
        if (rest.charAt(i) === "/") {
            selfClose = i === rest.length - 1
            i++
            continue
        }
        // Before an attribute name, even '=' starts the name; only a later '=' starts its value.
        var aname = rest.charAt(i).toLowerCase()
        i++
        while (i < rest.length && !isHtmlWhitespace(rest.charAt(i))
                && rest.charAt(i) !== "=" && rest.charAt(i) !== "/" && rest.charAt(i) !== ">") {
            aname += rest.charAt(i).toLowerCase()
            i++
        }
        if (!/^[A-Za-z_:][-A-Za-z0-9_.:]*$/.test(aname))
            valid = false
        while (i < rest.length && isHtmlWhitespace(rest.charAt(i)))
            i++
        var value = null
        if (rest.charAt(i) === "=") {
            i++
            while (i < rest.length && isHtmlWhitespace(rest.charAt(i)))
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
                while (i < rest.length && !isHtmlWhitespace(rest.charAt(i)) && rest.charAt(i) !== ">")
                    i++
                value = rest.slice(begin, i)
            }
        }
        attributes.push({ name: aname, value: value })
    }
    return { attributes: attributes, valid: valid, selfClose: selfClose }
}

// Sample input: '<img src="pic.png"/>' yields name "img", its attributes and a self-closing flag.
function tagHead(tag) {
    var i = 1
    var closing = false
    if (tag.charAt(i) === "/") {
        closing = true
        i++
    }
    var name = ""
    while (i < tag.length && (isNameChar(tag.charAt(i)) || tag.charAt(i) === "-")) {
        name += tag.charAt(i).toLowerCase()
        i++
    }
    var rest = tag.slice(i, tag.length - 1)
    var slashFirst = rest.charAt(0) === "/"
    var whitespaceEnd = slashFirst ? 1 : 0
    while (whitespaceEnd < rest.length && isHtmlWhitespace(rest.charAt(whitespaceEnd)))
        whitespaceEnd++
    var validHead = /^[a-z]/.test(name)
        && (rest === "" || isHtmlWhitespace(rest.charAt(0)) || slashFirst)
        && (!closing || (!slashFirst && whitespaceEnd === rest.length))
        && (!slashFirst || whitespaceEnd === rest.length)
    // Malformed dropped openers still suppress their bodies; malformed closers cannot end a dropped body.
    if (!validHead && (closing || !DROP_CONTENT.hasOwnProperty(name)))
        name = ""
    var attrs = scanAttributes(rest)
    return { name: name, closing: closing, rest: rest, selfClose: validHead && attrs.valid && attrs.selfClose,
        attributes: attrs.attributes, validAttrs: attrs.valid }
}

// Sample input: " \thttps://a.example/x\n " strips URL padding and embedded tab, CR and LF.
function normalizedTarget(value) {
    return String(value).replace(/^[\x00-\x20]+|[\x00-\x20]+$/g, "").replace(/[\t\r\n]/g, "")
}

// One attribute value with entities decoded for the safety checks below.
function attrKept(name, value, tagName) {
    var seen = normalizedTarget(MdUrl.canonicalUrl(value)).toLowerCase()
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

// Sanitize one tag into {emit, drop}; held image tokens carry resolved URLs, and drop names content to skip.
function sanitizeTag(tag, dir, tokens) {
    function hold(html) {
        return holdToken(tokens, html)
    }
    var head = tagHead(tag)
    var name = head.name
    if (name.length === 0)
        return { emit: "&#60;", drop: null }
    if (DROP_CONTENT.hasOwnProperty(name))
        return { emit: "", drop: head.closing || head.selfClose ? null : name }
    if (!ALLOWED.hasOwnProperty(name))
        return { emit: "", drop: null }
    // details shows its body; summary draws bold through the markdown parser.
    if (name === "details")
        return { emit: "", drop: null }
    if (name === "summary")
        return { emit: head.closing ? "**" : "**", drop: null }
    if (head.closing)
        return { emit: "</" + name + ">", drop: null }
    if (!head.validAttrs)
        return { emit: "", drop: null }
    var kept = ""
    var srcSeen = null
    var srcsetSeen = null
    var altSeen = null
    for (var i = 0; i < head.attributes.length; i++) {
        var aname = head.attributes[i].name
        var value = head.attributes[i].value
        // Every style, class, id, background, srcset, poster, data-* and on* attribute is dropped, whatever its value.
        if (aname === "style" || aname === "class" || aname === "id"
                || aname === "background" || aname === "poster"
                || aname.indexOf("data-") === 0 || aname.indexOf("on") === 0)
            continue
        if (aname === "srcset") {
            if (srcsetSeen === null)
                srcsetSeen = value === null ? "" : value
            continue
        }
        if (aname === "src" && (name === "img" || name === "source")) {
            if (srcSeen === null)
                srcSeen = value === null ? "" : value
            continue
        }
        if (aname === "alt") {
            if (altSeen !== null)
                continue
            altSeen = value === null ? "" : value
        }
        if (aname === "href" && value !== null)
            value = normalizedTarget(value)
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
            return { emit: hold('<img src="' + picked.url + '" alt="' + escapeAttr(altSeen === null ? "" : altSeen) + '">'), drop: null }
        if (picked !== null && picked.kind === "remote")
            return { emit: "\n\n" + MdUrl.placeholder(MdEscape.escapeText(picked.host)) + "\n\n", drop: null }
        return { emit: MdUrl.canonicalUrl(altSeen).length > 0 ? MdEscape.escapeText(altSeen) : "", drop: null }
    }
    var close = (head.selfClose || VOID.hasOwnProperty(name)) ? " /" : ""
    return { emit: "<" + name + kept + close + ">", drop: null }
}
