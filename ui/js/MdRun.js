.pragma library

// MdRun: hold code/math, then resolve links, images and HTML in one forward scan; links deactivate earlier link openers, while image openers stay active.
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml
.import "MdInline.js" as Md
.import "MdRefs.js" as Refs
.import "MdResolve.js" as Res

var hasOwn = Object.prototype.hasOwnProperty
// The work gate replaces this no-op to count each frame visited.
var countFrameStep = function () {}

// The driver: held spans first, then one forward scan. defs maps normalised labels to targets; numbers maps footnote ids to numbers.
function parseInline(text, dir, defs, numbers, chrome, ink, tokens, cited, literalPlain) {
    var body = MdHtml.documentText(text)
    // Plain prose returns directly; plain table cells use the bulk escaper before any markup is emitted.
    if (!/[`$[\]<>\\!]|https?:\/\/|www\./.test(body)
            && (!literalPlain || !/[*_~]|&(?:#(?:[0-9]+|[xX][0-9a-fA-F]+)|[A-Za-z][A-Za-z0-9]*);/.test(body)))
        return literalPlain ? Md.escapeHtmlText(body) : body
    var spans = Md.spanIntervals(body)
    var out = []
    var citationTokens = {}
    var frames = []
    var activeLinks = []
    // Without usable ink, link brackets are escaped so md4c cannot resolve unvetted targets.
    var styleLinks = /^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(ink || ""))
    var chromeOk = /^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(chrome || ""))
    var styleCache = {}
    // Compare the last span in place to reuse its held token without slicing; the cache covers other repeats.
    var lastStart = -1
    var lastLen = -1
    var lastOpen = -1
    var lastKind = -1
    var lastHeld = null
    var lastRef = 0
    // Exact dead flags: the first scan to find no "-->" or ">" ahead proves no later opener can close either, so dense hostile inputs pay once.
    var dead = { tagDead: -1, commentDead: false }
    var i = 0
    var sp = 0

    while (i < body.length) {
        if (sp < spans.length && i === spans[sp]) {
            var spanTo = spans[sp + 1]
            var spanLen = spans[sp + 2]
            var spanKind = spans[sp + 3] === 1 ? "math" : ""
            if (!chromeOk && spanKind === "math") {
                sp += Md.INTERVAL_STRIDE
                continue
            }
            var held = null
            if (chromeOk) {
                var innerStart = i + spanLen
                var innerEnd = spanTo - spanLen
                var same = lastStart >= 0 && spanKind === lastKind && spanLen === lastOpen
                    && innerEnd - innerStart === lastLen
                if (same) {
                    for (var e = 0; e < lastLen; e++) {
                        if (body.charAt(innerStart + e) !== body.charAt(lastStart + e)) {
                            same = false
                            break
                        }
                    }
                }
                if (same) {
                    out.push(lastRef)
                    i = spanTo
                    sp += Md.INTERVAL_STRIDE
                    continue
                }
                var innerText = body.slice(innerStart, innerEnd)
                if (innerText.length > 0 && innerText.charAt(0) === " "
                        && innerText.charAt(innerText.length - 1) === " ")
                    innerText = innerText.slice(1, -1)
                held = Res.styledSpan(spanKind, innerText, chrome, styleCache)
                lastStart = innerStart
                lastLen = innerEnd - innerStart
                lastOpen = spanLen
                lastKind = spanKind
                lastHeld = held
                tokens.push(held)
                lastRef = -1 - (tokens.length - 1)
                out.push(lastRef)
            }
            if (held === null) {
                held = body.slice(i, spanTo)
                tokens.push(held)
                out.push(-1 - (tokens.length - 1))
            }
            i = spanTo
            sp += Md.INTERVAL_STRIDE
            continue
        }
        if (sp < spans.length && i > spans[sp]) {
            sp += Md.INTERVAL_STRIDE
            continue
        }
        var c = body.charAt(i)
        if (c === "\\" && i + 1 < body.length && Md.isPunct(body.charAt(i + 1))) {
            out.push("&#" + body.charCodeAt(i + 1) + ";")
            i += 2
            continue
        }
        if (c === "`" || c === "$") {
            out.push(c)
            i++
            continue
        }
        if (c === "!" && body.charAt(i + 1) === "[") {
            out.push("!")
            frames.push({ bang: true, mark: out.length, rawStart: i + 2, active: true })
            out.push("&#91;")
            i += 2
            continue
        }
        if (c === "[") {
            if (body.charAt(i + 1) === "^") {
                var fn = Refs.readFootnoteRef(body, i)
                if (fn !== null && numbers && hasOwn.call(numbers, fn.id)
                        && (cited !== undefined || numbers[fn.id] > 0)) {
                    citationTokens[tokens.length] = fn.id
                    tokens.push("<sup>" + numbers[fn.id] + "</sup>")
                    out.push(-1 - (tokens.length - 1))
                    i = fn.end
                    continue
                }
                out.push("&#91;")
                i++
                continue
            }
            if (!styleLinks) {
                frames.push({ bang: false, mark: out.length, rawStart: i + 1,
                    active: false, passthrough: true })
                out.push("&#91;")
                i++
                continue
            }
            var opener = { bang: false, mark: out.length, rawStart: i + 1, active: true }
            frames.push(opener)
            activeLinks.push(opener)
            out.push("&#91;")
            i++
            continue
        }
        if (c === "]" && frames.length > 0) {
            var frame = frames.pop()
            countFrameStep()
            if (!frame.bang && frame.active)
                activeLinks.pop()
            if (frame.passthrough) {
                out.push("&#93;")
                i++
                continue
            }
            frame.rawEnd = i
            var raw = body.slice(frame.rawStart, frame.rawEnd)
            var j = i + 1
            var made = null
            if (frame.active) {
                var inline = null
                if (body.charAt(j) === "(")
                    inline = Md.readInlineTarget(body, j)
                if (inline !== null) {
                    made = Res.resolvePair(raw, inline.url, frame.bang, dir, ink, tokens)
                    j = inline.end
                } else if (body.charAt(j) === "[") {
                    var ref = Md.readLabelRef(body, j)
                    if (ref !== null) {
                        var label = ref.label.length > 0 ? ref.label : raw
                        if (label.length > 0) {
                            var key = Md.normalizeLabel(label)
                            if (hasOwn.call(defs, key)) {
                                made = Res.resolvePair(raw, defs[key], frame.bang, dir, ink, tokens)
                                j = ref.end
                            }
                        }
                    }
                } else if (raw.length > 0) {
                    var skey = Md.normalizeLabel(raw)
                    if (hasOwn.call(defs, skey))
                        made = Res.resolvePair(raw, defs[skey], frame.bang, dir, ink, tokens)
                }
                if (made !== null && !frame.bang) {
                    while (activeLinks.length > 0) {
                        countFrameStep()
                        activeLinks.pop().active = false
                    }
                }
            }
            if (made !== null) {
                out.length = frame.bang ? frame.mark - 1 : frame.mark
                out.push(made)
                i = j
            } else {
                out.push("&#93;")
                i++
            }
            continue
        }
        if (c === "]") {
            out.push("&#93;")
            i++
            continue
        }
        if (c === "<") {
            i = Res.parseAngle(body, i, dir, ink, styleLinks, dead, tokens, out)
            continue
        }
        if (c === "h" || c === "w") {
            var bare = Md.readBarelink(body, i)
            if (bare !== null && !Res.isLinkTarget(bare.url))
                bare = null
            if (bare !== null) {
                if (!styleLinks) {
                    out.push(Md.escapeHtmlText(bare.url))
                    i = bare.end
                    continue
                }
                var bhtml = Md.linkHtml(bare.url, bare.url, ink)
                if (bhtml === null) {
                out.push(Md.escapeHtmlText(bare.url))
            } else {
                tokens.push(bhtml)
                out.push(-1 - (tokens.length - 1))
            }
                i = bare.end
                continue
            }
            out.push(c)
            i++
            continue
        }
        if (c === ">") {
            out.push("&#62;")
            i++
            continue
        }
        // A table cell's only pipe is an unescaped "\|", so it stays cell text like the bulk escaper writes it.
        if (c === "|" && literalPlain) {
            out.push("&#124;")
            i++
            continue
        }
        out.push(c)
        i++
    }
    // Join strings and -1-index token references without per-span objects or another interpreted output scan.
    var parts = new Array(out.length)
    for (var k = 0; k < out.length; k++) {
        if (typeof out[k] === "string") {
            parts[k] = out[k]
            continue
        }
        var tokenIndex = -1 - out[k]
        if (citationTokens.hasOwnProperty(tokenIndex)) {
            var id = citationTokens[tokenIndex]
            if (cited !== undefined && numbers[id] === 0) {
                cited.push(id)
                numbers[id] = cited.length
            }
            tokens[tokenIndex] = "<sup>" + numbers[id] + "</sup>"
        }
        parts[k] = tokens[tokenIndex]
    }
    return parts.join("")
}
