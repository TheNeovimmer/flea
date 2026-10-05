.pragma library

// MdMath: where a display formula starts and ends in the block reader's lines, and which formulas a paragraph holds.
.import "MdInline.js" as Md
var INLINE_DELIMITER_LENGTH = 1
var DISPLAY_DELIMITER_LENGTH = 2

// Sample input: "$$x^2$$ tail" answers { source: "x^2", tail: " tail", to: i }; a lone "$$" opener reads on to its closer line.
function displayAt(lines, i, text) {
    var disp = /^ {0,3}\$\$(.*)$/.exec(text)
    if (disp === null)
        return null
    var rest = disp[1]
    var closeAt = rest.indexOf("$$")
    var source = ""
    var tail = ""
    var to = i
    if (closeAt >= 0) {
        source = rest.slice(0, closeAt).trim()
        tail = rest.slice(closeAt + DISPLAY_DELIMITER_LENGTH)
    } else {
        // The closer search stops at the paragraph's blank line, so no later opener scans these lines again.
        var end = -1
        for (var at = i + 1; end < 0 && at < lines.length && lines[at].trim().length > 0; at++) {
            if (lines[at].indexOf("$$") >= 0)
                end = at
        }
        if (end > i) {
            var endAt = lines[end].indexOf("$$")
            source = [rest].concat(lines.slice(i + 1, end), [lines[end].slice(0, endAt)]).join("\n").trim()
            tail = lines[end].slice(endAt + DISPLAY_DELIMITER_LENGTH)
            to = end
        }
    }
    return source.length > 0 ? { source: source, tail: tail, to: to } : null
}

// Sample input: "a $$x$$ b" answers [{ text: "a " }, { math: "x" }, { text: " b" }]; text without a display pair answers null.
function splitDisplay(text) {
    if (text.indexOf("$$") < 0)
        return null
    var spans = Md.spanIntervals(text)
    var pieces = []
    var at = 0
    for (var k = 0; k < spans.length; k += Md.INTERVAL_STRIDE) {
        if (spans[k + 3] !== Md.MATH_SPAN || spans[k + 2] !== DISPLAY_DELIMITER_LENGTH)
            continue
        pieces.push({ text: text.slice(at, spans[k]) })
        pieces.push({ math: text.slice(spans[k] + DISPLAY_DELIMITER_LENGTH, spans[k + 1] - DISPLAY_DELIMITER_LENGTH).trim() })
        at = spans[k + 1]
    }
    pieces.push({ text: text.slice(at) })
    return pieces.length > 1 ? pieces : null
}

// Sample input: "e $x^2$ and $y$" answers ["x^2", "y"]; display pairs and code spans hold none.
function inlineSources(text) {
    var out = []
    if (text.indexOf("$") < 0)
        return out
    var spans = Md.spanIntervals(text)
    for (var k = 0; k < spans.length; k += Md.INTERVAL_STRIDE) {
        if (spans[k + 3] === Md.MATH_SPAN && spans[k + 2] === INLINE_DELIMITER_LENGTH)
            out.push(text.slice(spans[k] + INLINE_DELIMITER_LENGTH, spans[k + 1] - INLINE_DELIMITER_LENGTH).trim())
    }
    return out
}
