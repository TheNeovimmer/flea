.pragma library

// MdEscape: ASCII punctuation as numeric entities, so emphasis, links and autolinks cannot form inside converted text.
var ASCII_LIMIT = 128
var LONG_ESCAPE_LENGTH = 1024
var ENTITY_CHARS = "&#;"
// Sample input: a<b splits to ["a", "<", "b"]; the capture keeps each punctuation character for its entity.
var PUNCT_SPLIT = /([\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E])/
var ENTITY_CHAR_SPLIT = /([&#;])/
var ENTITIES = []
var OTHER_PUNCT = []
for (var asciiCode = 0; asciiCode < ASCII_LIMIT; asciiCode++) {
    ENTITIES.push("&#" + asciiCode + ";")
    if (isAsciiPunct(asciiCode) && ENTITY_CHARS.indexOf(String.fromCharCode(asciiCode)) < 0)
        OTHER_PUNCT.push(String.fromCharCode(asciiCode))
}

function isAsciiPunct(code) {
    return (code >= 33 && code <= 47) || (code >= 58 && code <= 64)
        || (code >= 91 && code <= 96) || (code >= 123 && code <= 126)
}

function escapeWith(text, splitter) {
    var parts = text.split(splitter)
    for (var i = 1; i < parts.length; i += 2)
        parts[i] = ENTITIES[parts[i].charCodeAt(0)]
    return parts.join("")
}

// Short text: one split on all punctuation. Long text: & # ; first (entities use them), then one native split per other mark.
function escapeText(content) {
    var text = String(content)
    if (text.length < LONG_ESCAPE_LENGTH)
        return escapeWith(text, PUNCT_SPLIT)
    text = escapeWith(text, ENTITY_CHAR_SPLIT)
    for (var k = 0; k < OTHER_PUNCT.length; k++) {
        var mark = OTHER_PUNCT[k]
        if (text.indexOf(mark) >= 0)
            text = text.split(mark).join(ENTITIES[mark.charCodeAt(0)])
    }
    return text
}
