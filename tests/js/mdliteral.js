.import "../../ui/js/Markdown.js" as Markdown

// Decoded text and task boxes reach Qt as text: a digit a reference spelled is no list marker, and a done box is no emoji glyph.
function run(check) {
    var dir = "/home/gm/notes"
    var chrome = "#181825"
    var ink = "#c0caf5"
    function styled(doc) {
        return Markdown.prepare(doc, dir, undefined, chrome, ink)
    }
    // A decoded digit stays an entity, so Qt cannot read "1. ol" as an ordered list marker at a line start.
    check("decoded digit stays an entity", styled("&#49;. ol"), "&#49;. ol")
    check("decoded digits after a soft break", styled("a\n&#49;&#48;) ol"), "a\n&#49;&#48;) ol")
    check("a literal digit is untouched", styled("v1 is 2"), "v1 is 2")
    // U+2611 is an emoji and falls back to a colour font; a font tag with one family holding both boxes keeps both in one text font, in the row ink.
    var open = Markdown.blocks("- [ ] a\n", dir, chrome, ink)[0].items[0]
    var done = Markdown.blocks("- [x] a\n", dir, chrome, ink)[0].items[0]
    check("an open box is U+2610 in the pinned face", open, '<font face="Noto Sans Symbols 2">\u2610</font> a')
    check("a done box is U+2611 in the pinned face", done, '<font face="Noto Sans Symbols 2">\u2611</font> a')
    check("a pinned box sets no colour", /color/.test(done + open), false)
    check("a nested done box is pinned", Markdown.blocks("- a\n  - [x] b\n", dir, chrome, ink)[0].items[1], '<font face="Noto Sans Symbols 2">\u2611</font> b')
    check("a done box in a quoted list is pinned", JSON.stringify(Markdown.blocks("> - [x] b\n", dir, chrome, ink)).indexOf('<font face=\\"Noto Sans Symbols 2\\">\u2611</font> b') >= 0, true)
    check("a done box before a fence is pinned", (Markdown.blocks("- [x] b\n\n  ```\n  c\n  ```\n", dir, chrome, ink)[0].parts || [[{ text: "" }]])[0][0].text.trim(), '<font face="Noto Sans Symbols 2">\u2611</font> b')
}
