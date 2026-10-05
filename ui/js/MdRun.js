.pragma library

// MdRun: hold code/math, then resolve links, images and HTML in one forward scan; links deactivate earlier link openers, while image openers stay active.
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml
.import "MdInline.js" as Md
.import "MdRefs.js" as Refs
.import "MdResolve.js" as Res
.import "MdEmph.js" as Emph
.import "MdBreak.js" as Brk
.import "MdEntity.js" as Ent
.import "MdHold.js" as Hold

var hasOwn = Object.prototype.hasOwnProperty
// The work gate replaces this no-op to count each frame visited.
var countFrameStep = function () {}

// The driver: held spans first, then one forward scan; bareText says no container holds the text (its ">" is never a quote mark); fragment says the text starts and ends mid-line (an image's alt text).
function parseInline(text, dir, defs, numbers, chrome, ink, tokens, cited, literalPlain, bareText, fragment) {
    var body = MdHtml.documentText(text)
    // Plain prose returns directly; plain table cells use the bulk escaper before any markup is emitted.
    if (!/[`$[\]<>\\!*_]| {2}\n|https?:\/\/|www\./.test(body)
            && (literalPlain ? !/[*_~]|&(?:#(?:[0-9]+|[xX][0-9a-fA-F]+)|[A-Za-z][A-Za-z0-9]*);/.test(body) : !/&[#A-Za-z]/.test(body)))
        return literalPlain ? Md.escapeHtmlText(body) : body
    var spans = Md.spanIntervals(body)
    var out = []
    var delims = []
    delims.bottom = 0
    var citationTokens = {}
    var frames = []
    var activeLinks = []
    // Without usable ink, link brackets are escaped so md4c cannot resolve unvetted targets.
    var styleLinks = /^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(ink || ""))
    var chromeOk = /^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(chrome || ""))
    var styleCache = {}
    // The span held last, so a repeat reuses its token without slicing.
    var lastSpan = { start: -1, length: -1, open: -1, kind: "", ref: 0 }
    // Exact dead flags: the first scan to find no "-->" or ">" ahead proves no later opener can close either, so dense hostile inputs pay once.
    var dead = { tagDead: -1, commentDead: false }
    var i = 0
    var sp = 0
    var lastQuote = -1
    // out[0, numbered) holds no citation still to number; imageMark is where the outermost open image's alt text begins, or -1.
    var numbered = 0
    var imageMark = -1
    var imageDepth = -1
    var line = Ent.lineState(fragment !== true)

    // Join strings, -1-index token references and emphasis marks; inside an emphasis tag or a label a newline is a space, which the renderer would drop.
    function renderFrom(from, flat, alt) {
        var parts = []
        var depth = flat ? 1 : 0
        for (var k = from; k < out.length; k++) {
            var piece = out[k]
            if (typeof piece === "string") {
                parts.push(depth > 0 && piece === "\n" ? " " : piece)
                continue
            }
            if (typeof piece === "object") {
                depth -= piece.closes
                parts.push(piece.before + Emph.literal(piece) + piece.after)
                depth += piece.opens
                continue
            }
            var tokenIndex = -1 - piece
            if (alt === true && citationTokens.hasOwnProperty(tokenIndex)) {
                parts.push("[^" + citationTokens[tokenIndex] + "]")
                continue
            }
            if (citationTokens.hasOwnProperty(tokenIndex))
                cite(tokenIndex)
            parts.push(tokens[tokenIndex])
        }
        return parts.join("")
    }

    // The open brackets of a finished paragraph never pair with a later "]", so they stay literal.
    function endParagraph() {
        frames.length = 0
        activeLinks.length = 0
        imageMark = -1
    }

    // Number a footnote citation the first time it is read, so its superscript is the next free number.
    function cite(tokenIndex) {
        var id = citationTokens[tokenIndex]
        if (cited !== undefined && numbers[id] === 0) {
            cited.push(id)
            numbers[id] = cited.length
        }
        tokens[tokenIndex] = "<sup>" + numbers[id] + "</sup>"
    }

    // Number the citations before out[limit], which a label rendered now would otherwise number ahead of; an image's alt text draws none.
    function citeBefore(limit) {
        var to = Math.min(limit, imageMark < 0 ? limit : imageMark)
        for (; numbered < to; numbered++) {
            var piece = out[numbered]
            if (typeof piece === "number" && citationTokens.hasOwnProperty(-1 - piece))
                cite(-1 - piece)
        }
    }

    // The label of the bracket pair opened at out[mark], its emphasis resolved first.
    function labelHtml(mark, alt) {
        citeBefore(mark)
        var from = delims.length
        while (from > 0 && delims[from - 1].at > mark)
            from--
        Emph.process(delims, from)
        return renderFrom(mark + 1, true, alt)
    }

    while (i < body.length) {
        if (sp < spans.length && i === spans[sp]) {
            var spanTo = spans[sp + 1]
            var spanLen = spans[sp + 2]
            var spanKind = spans[sp + 3] === Md.MATH_SPAN ? "math" : ""
            if (!chromeOk && spanKind === "math") {
                sp += Md.INTERVAL_STRIDE
                continue
            }
            Hold.hold(body, i, spanTo, spanLen, spanKind, chromeOk ? chrome : null, styleCache, lastSpan, tokens, out)
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
        if (c === "\n" || (c === "\\" && body.charAt(i + 1) === "\n")) {
            i = Brk.lineBreak(body, i, out, delims, endParagraph)
            continue
        }
        if (c === "`" || c === "$") {
            out.push(c)
            i++
            continue
        }
        if ((c === "*" || c === "_") && Brk.isRuleLine(body, i)) {
            var ruleEnd = body.indexOf("\n", i)
            ruleEnd = ruleEnd < 0 ? body.length : ruleEnd
            out.push(c + c + c)
            i = ruleEnd
            continue
        }
        if (c === "*" || c === "_") {
            var mark = Emph.runAt(body, i, out.length)
            delims.push(mark)
            out.push(mark)
            i = mark.end
            continue
        }
        if (c === "!" && body.charAt(i + 1) === "[") {
            out.push("!")
            if (imageMark < 0) {
                imageMark = out.length
                imageDepth = frames.length
            }
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
            if (frames.length === imageDepth)
                imageMark = -1
            if (!frame.bang && frame.active)
                activeLinks.pop()
            if (frame.passthrough) {
                out.push("&#93;")
                i++
                continue
            }
            var raw = body.slice(frame.rawStart, i)
            var j = i + 1
            var made = null
            if (frame.active) {
                var found = Res.readDestination(body, j, raw, defs)
                if (found !== null) {
                    // Emphasis inside the label pairs now, so the link or image takes the label's own markup.
                    made = Res.resolvePair(raw, found.url, frame.bang, dir, ink, tokens, function () {
                        return labelHtml(frame.mark, frame.bang)
                    })
                    j = found.end
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
                numbered = Math.min(numbered, out.length)
                while (delims.length > 0 && delims[delims.length - 1].at >= out.length)
                    delims.pop()
                out.push(made)
                Ent.lineRestart(line, out, made)
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
        if (c === "&") {
            var spaces = Ent.spaceRunAt(body, i, out, Ent.lineBlank(line, out), fragment !== true)
            if (spaces !== null) {
                out.length -= spaces.trim
                out.push(spaces.text)
                i = spaces.end
                continue
            }
            // Qt's own table is short and keeps a newline reference, so the character is decoded here.
            var reference = Ent.referenceAt(body, i)
            out.push(reference === null ? c : Md.escapeDecodedText(reference.text))
            i = reference === null ? i + 1 : reference.end
            continue
        }
        if (c === "<") {
            i = Res.parseAngle(body, i, dir, ink, styleLinks, dead, tokens, out, chrome)
            continue
        }
        if (c === "h" || c === "w") {
            var bareEnd = Res.bareAt(body, i, ink, styleLinks, tokens, out)
            if (bareEnd < 0) {
                out.push(c)
                i++
            } else {
                i = bareEnd
            }
            continue
        }
        if (c === ">") {
            // A mark that opens a quote inside a list item stays for the renderer; table cells never hold one.
            var quoting = !literalPlain && bareText !== true && Brk.quoteMarkAt(body, i, lastQuote)
            lastQuote = quoting ? i : lastQuote
            out.push(quoting ? ">" : "&#62;")
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
    Emph.process(delims, delims.bottom)
    return renderFrom(0, false)
}
