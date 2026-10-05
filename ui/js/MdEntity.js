.pragma library

// MdEntity: backslash escapes and character references in destinations, info strings and running text, decoded here.
.import "MdEntityTable.js" as Names

var REPLACEMENT_CHARACTER = 0xfffd
var MAX_CODE_POINT = 0x10ffff
var SURROGATE_START = 0xd800
var SURROGATE_END = 0xdfff
// The longest reference is "&CounterClockwiseContourIntegral;" (33 characters), so a window this long holds any one.
var REFERENCE_WINDOW = 34
var REFERENCE = /\\([!-\/:-@\[-`{-~])|&(?:#([0-9]{1,7})|#[xX]([0-9a-fA-F]{1,6})|([A-Za-z][A-Za-z0-9]{1,31}));/g
var REFERENCE_HERE = /^&(?:#([0-9]{1,7})|#[xX]([0-9a-fA-F]{1,6})|([A-Za-z][A-Za-z0-9]{1,31}));/

// Sample input: 10 and 0x1F600 answer their characters; 0, a surrogate and a value past U+10FFFF answer U+FFFD.
function codePointText(code) {
    var valid = code > 0 && code <= MAX_CODE_POINT && (code < SURROGATE_START || code > SURROGATE_END)
    return String.fromCodePoint(valid ? code : REPLACEMENT_CHARACTER)
}

// Sample input: "f&ouml;o\\*" answers "f\u00f6o*"; an unknown name such as "&nosuch;" stays as written.
function decodeReferences(text) {
    if (text.indexOf("\\") < 0 && text.indexOf("&") < 0)
        return text
    return text.replace(REFERENCE, function (all, escaped, dec, hex, name) {
        if (escaped !== undefined)
            return escaped
        if (name !== undefined) {
            var named = Names.namedValue(name)
            return named === null ? all : named
        }
        return codePointText(dec !== undefined ? parseInt(dec, 10) : parseInt(hex, 16))
    })
}

// Sample input: "a &copy; b" at index 2 answers { text: "\u00a9", end: 8 }; "&nosuch;" and a bare "&" answer null.
function referenceAt(text, i) {
    var hit = REFERENCE_HERE.exec(text.slice(i, i + REFERENCE_WINDOW))
    if (hit === null)
        return null
    var decoded = hit[3] !== undefined ? Names.namedValue(hit[3])
        : codePointText(hit[1] !== undefined ? parseInt(hit[1], 10) : parseInt(hit[2], 16))
    return decoded === null ? null : { text: decoded, end: i + hit[0].length }
}

// Sample input: "", " " or "  " is a piece with nothing drawn on its line.
var BLANK_PIECE = /^ *$/
var WHITESPACE_REFERENCE = /[\t\n\r\f]/g
var HARD_BREAK_PIECE = "<br />"
// What a line holding only space references keeps, so Qt reads text and the paragraph stays whole.
var WHOLE_LINE_REFERENCE = "&#32;"

// Sample input: after "a" and "\n" a line is blank, after " " it stays blank, after "b" or a token (a number) it is not; "<br />" ends a line.
function blankAfter(blank, piece) {
    if (typeof piece !== "string")
        return false
    var cut = piece.lastIndexOf("\n")
    if (cut >= 0)
        return BLANK_PIECE.test(piece.slice(cut + 1))
    return piece === HARD_BREAK_PIECE || (blank && BLANK_PIECE.test(piece))
}

// Sample input: lineBlank(lineState(true), ["a", "\n", " "]) answers true; ["a", " "] on a fresh state answers false; lineState(false), a fragment, starts not blank.
// The state folds each piece once, so it stays linear; lineRestart sets it afresh after a label's pieces were replaced by one.
function lineState(startsBlank) {
    return { scanned: 0, blank: startsBlank }
}

function lineBlank(state, out) {
    state.scanned = Math.min(state.scanned, out.length)
    for (; state.scanned < out.length; state.scanned++)
        state.blank = blankAfter(state.blank, out[state.scanned])
    return state.blank
}

function lineRestart(state, out, piece) {
    state.blank = blankAfter(false, piece)
    state.scanned = out.length
}

// Sample input: a tab or a newline (the decoded text of "&#9;" and "&#10;") is drawn as one space, any other text is unchanged.
function drawnText(text) {
    return text.replace(WHITESPACE_REFERENCE, " ")
}

// Sample input: "x  &#32;\ny" at 3 answers { text: "", end: 8, trim: 2 }; "x&#32;  \ny" at 1 answers { text: "", end: 6, trim: 0 }; "a\n&#32;\nb" at 2 with blank true answers { text: "&#32;", end: 7, trim: 0 }; "&copy;" answers null.
// A run of space references with the literal spaces inside and after it is one unit: dropped at a line end (the literal spaces after it stay to decide a hard break) and at a line start, else one raw space; a whole-line run stays one reference so Qt sees a non-blank line.
function spaceRunAt(text, i, out, blank, endsLine) {
    var end = i
    var lastReference = i
    var hit = referenceAt(text, end)
    while (hit !== null && drawnText(hit.text) === " ") {
        end = hit.end
        lastReference = end
        while (text.charAt(end) === " ")
            end++
        hit = referenceAt(text, end)
    }
    if (lastReference === i)
        return null
    if ((end >= text.length && endsLine) || text.charAt(end) === "\n") {
        var trim = 0
        while (trim < out.length && out[out.length - 1 - trim] === " ")
            trim++
        return { text: blank ? WHOLE_LINE_REFERENCE : "", end: lastReference, trim: trim }
    }
    return { text: blank ? "" : " ", end: end, trim: 0 }
}
