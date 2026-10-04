.pragma library

// MdEmph: CommonMark delimiter runs, resolved after the inline scan; a mark that pairs becomes a tag, any other stays text.
.import "MdEscape.js" as Esc

var RULE_OF_THREE = 3
var STRONG_LENGTH = 2
var MAX_RUN_LENGTH = 1024
// Unicode P and S approximated by the blocks that hold them: Latin-1, general punctuation, currency, symbols, CJK, fullwidth.
var UNICODE_PUNCT = /[¡-©«-±´¶-¸»¿×÷˂-˅˒-˟‐-‧‰-⁞₠-⃀℀-⅏←-⯿⸀-⹿、-〃〈-〠〰・︐-︙︰-﹫！-／：-＠［-｀｛-･￠-￮\ud83c-\ud83e]/
var SPACE = /\s/

function isPunctChar(c) {
    return Esc.isAsciiPunct(c.charCodeAt(0)) || UNICODE_PUNCT.test(c)
}

// Sample input: "foo*bar*" at index 3 reads a run of one star, flanked by letters, which can open and close.
function runAt(body, i, at) {
    var ch = body.charAt(i)
    var j = i + 1
    while (j < body.length && j - i < MAX_RUN_LENGTH && body.charAt(j) === ch)
        j++
    var before = i > 0 ? body.charAt(i - 1) : "\n"
    var after = j < body.length ? body.charAt(j) : "\n"
    var spaceBefore = SPACE.test(before)
    var spaceAfter = SPACE.test(after)
    var punctBefore = isPunctChar(before)
    var punctAfter = isPunctChar(after)
    var left = !spaceAfter && (!punctAfter || spaceBefore || punctBefore)
    var right = !spaceBefore && (!punctBefore || spaceAfter || punctAfter)
    var under = ch === "_"
    return { ch: ch, n: j - i, orig: j - i, at: at, end: j,
        open: under ? left && (!right || punctBefore) : left,
        close: under ? right && (!left || punctAfter) : right,
        before: "", after: "", opens: 0, closes: 0 }
}

// The delimiters from index from on pair as the reference algorithm does, over a linked list so a nested pair never rescans its inside.
function process(delims, from) {
    var total = delims.length
    var prev = []
    var next = []
    var bottoms = {}
    for (var k = from; k < total; k++) {
        prev[k] = k - 1
        next[k] = k + 1
    }
    var ci = from
    while (ci < total) {
        var closer = delims[ci]
        if (!closer.close || closer.n === 0) {
            ci = next[ci]
            continue
        }
        var key = closer.ch + (closer.orig % RULE_OF_THREE) + (closer.open ? "o" : "c")
        var bottom = bottoms.hasOwnProperty(key) ? bottoms[key] : from - 1
        var oi = prev[ci]
        while (oi > bottom) {
            var cand = delims[oi]
            if (cand.open && cand.n > 0 && cand.ch === closer.ch
                    && !((closer.open || cand.close) && (cand.orig + closer.orig) % RULE_OF_THREE === 0
                        && !(cand.orig % RULE_OF_THREE === 0 && closer.orig % RULE_OF_THREE === 0)))
                break
            oi = prev[oi]
        }
        if (oi <= bottom) {
            bottoms[key] = prev[ci]
            ci = next[ci]
            continue
        }
        var opener = delims[oi]
        var strong = closer.n >= STRONG_LENGTH && opener.n >= STRONG_LENGTH
        var use = strong ? STRONG_LENGTH : 1
        opener.n -= use
        closer.n -= use
        opener.after = (strong ? "<strong>" : "<em>") + opener.after
        closer.before = closer.before + (strong ? "</strong>" : "</em>")
        opener.opens++
        closer.closes++
        // Everything between the pair can no longer pair: unlink it, and the opener too once it has no marks left.
        next[oi] = ci
        prev[ci] = oi
        if (opener.n === 0) {
            next[prev[oi]] = ci
            prev[ci] = prev[oi]
        }
        if (closer.n === 0)
            ci = next[ci]
    }
}

// Sample input: an unpaired "**" that could open reads "&#42;&#42;", which no renderer pairs again; the "_" in "a_b" stays plain.
function literal(d) {
    if (d.n === 0)
        return ""
    return d.open || d.close ? Esc.escapeText(d.ch).repeat(d.n) : d.ch.repeat(d.n)
}
