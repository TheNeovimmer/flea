.pragma library

// MdEntity: backslash escapes and character references in destinations, info strings and running text, decoded here.
.import "MdEntityTable.js" as Names
.import "MdInline.js" as Md

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
// Pieces of output looked back over, so a flood of references stays linear.
var BLANK_WINDOW = 8

// Sample input: out ["a", "\n", " "] is blank after its last newline; ["a ", "b"] is not; longer than the window answers false, a long leading run is code already.
function blankLineTail(out) {
    var floor = Math.max(0, out.length - BLANK_WINDOW)
    for (var k = out.length - 1; k >= floor; k--) {
        var cut = out[k].lastIndexOf("\n")
        var tail = cut < 0 ? out[k] : out[k].slice(cut + 1)
        if (!BLANK_PIECE.test(tail))
            return false
        if (cut >= 0)
            return true
    }
    return floor === 0
}

// A decoded reference reaches Qt as numeric entities; Qt drops an entity space, so a space stays raw unless it would open indented code or end a line as a hard break, where it is dropped.
function decodedReference(text, out, next) {
    if (text === " " && (next === " " || next === "\n" || next === "" || blankLineTail(out)))
        return ""
    return Md.escapeHtmlText(text)
}
