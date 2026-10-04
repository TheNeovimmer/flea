.pragma library

// MdHold: a code or math span becomes one held token, and a span that repeats the one before it reuses that token.
.import "MdResolve.js" as Res

// Sample input: "`a` `a`" held twice answers one token for both; a null chrome holds the span's raw text instead of its styled html.
function hold(body, from, to, length, kind, chrome, cache, last, tokens, out) {
    if (chrome === null) {
        tokens.push(body.slice(from, to))
        out.push(-1 - (tokens.length - 1))
        return
    }
    var innerStart = from + length
    var innerEnd = to - length
    var same = last.start >= 0 && kind === last.kind && length === last.open && innerEnd - innerStart === last.length
    for (var e = 0; same && e < last.length; e++)
        same = body.charAt(innerStart + e) === body.charAt(last.start + e)
    if (same) {
        out.push(last.ref)
        return
    }
    var innerText = body.slice(innerStart, innerEnd).replace(/\n/g, " ")
    if (innerText.length > 0 && innerText.charAt(0) === " " && innerText.charAt(innerText.length - 1) === " ")
        innerText = innerText.slice(1, -1)
    tokens.push(Res.styledSpan(kind, innerText, chrome, cache))
    last.start = innerStart
    last.length = innerEnd - innerStart
    last.open = length
    last.kind = kind
    last.ref = -1 - (tokens.length - 1)
    out.push(last.ref)
}
