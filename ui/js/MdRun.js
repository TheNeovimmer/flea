.pragma library

// MdRun: the single-pass inline driver. Code and math spans are held first (so
// image syntax inside backticks never resolves), then one forward scan resolves
// images, links, footnote refs, autolinks and raw HTML while escaping every
// bracket and angle bracket it did not emit itself. Link bottoms follow
// CommonMark: resolving a link deactivates every opener below it, so an outer
// link never forms around an inner one; image openers stay active throughout.
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml
.import "MdInline.js" as Md
.import "MdRefs.js" as Refs
.import "MdResolve.js" as Res

// The driver: held spans first, then one forward scan. defs maps normalised
// labels to targets; numbers maps footnote ids to numbers.
function parseInline(text, dir, defs, numbers, chrome, ink, tokens) {
    var body = String(text)
    // Plain prose takes no interpreted walk at all: one native scan for every
    // trigger character and bare-link prefix, and the text returns as is.
    // Anything reaching the loop below carries syntax worth parsing.
    if (!/[`$[\]<>\\!]|https?:\/\/|www\./.test(body))
        return body
    var spans = Md.spanIntervals(body)
    var out = []
    var frames = []
    // Without a usable ink links stay literal, the way unworn chrome leaves
    // code spans literal: nothing is styled, so nothing is rewritten. The
    // chrome check is hoisted out of the per-span path, and styled spans are
    // cached by content: dense documents repeat the same spans thousands of
    // times, and each rebuild costs a regex the cache pays once.
    var styleLinks = /^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(ink || ""))
    var chromeOk = /^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(chrome || ""))
    var styleCache = {}
    // Dense documents repeat one span thousands of times. The last span's
    // content is compared in place, so a repeat reuses its token with no slice
    // and no allocation at all; the cache below covers the rest.
    var lastStart = -1
    var lastLen = -1
    var lastOpen = -1
    var lastKind = -1
    var lastHeld = null
    var lastRef = 0
    // Exact dead flags: the first scan to find no "-->" or ">" ahead proves
    // no later opener can close either, so dense hostile inputs pay once.
    var dead = { tagDead: -1, commentDead: false }
    var i = 0
    var sp = 0

    while (i < body.length) {
        if (sp < spans.length && i === spans[sp]) {
            var spanTo = spans[sp + 1]
            var spanLen = spans[sp + 2]
            var spanKind = spans[sp + 3] === 1 ? "math" : ""
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
                    sp += 4
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
            sp += 4
            continue
        }
        if (sp < spans.length && i > spans[sp]) {
            sp += 4
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
                if (fn !== null && numbers && numbers.hasOwnProperty(fn.id)) {
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
                out.push("[")
                i++
                continue
            }
            frames.push({ bang: false, mark: out.length, rawStart: i + 1, active: true })
            out.push("&#91;")
            i++
            continue
        }
        if (c === "]" && frames.length > 0) {
            var frame = frames.pop()
            if (frame.passthrough) {
                out.push("]")
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
                            if (defs.hasOwnProperty(key)) {
                                made = Res.resolvePair(raw, defs[key], frame.bang, dir, ink, tokens)
                                j = ref.end
                            }
                        }
                    }
                } else if (raw.length > 0) {
                    var skey = Md.normalizeLabel(raw)
                    if (defs.hasOwnProperty(skey))
                        made = Res.resolvePair(raw, defs[skey], frame.bang, dir, ink, tokens)
                }
                if (made !== null && !frame.bang) {
                    for (var f = 0; f < frames.length; f++)
                        frames[f].active = false
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
                    out.push(body.slice(i, bare.end))
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
        out.push(c)
        i++
    }
    // Native join over strings and token references: a reference is -1 minus
    // its index, so the walk is arithmetic with no per-span objects for the
    // GC to re-scan. No interpreted per-char walk over the styled output.
    var parts = new Array(out.length)
    for (var k = 0; k < out.length; k++)
        parts[k] = typeof out[k] === "string" ? out[k] : tokens[-1 - out[k]]
    return parts.join("")
}

