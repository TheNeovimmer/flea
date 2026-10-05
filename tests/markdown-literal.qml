import QtQuick
import "../ui/js/Markdown.js" as Markdown

// A decoded "1. ol" reaches Qt as text, so the real MarkdownText lays it out as one plain line and never as a list item.
QtObject {
    id: gate
    property Item sandbox: Item {}
    property int checks: 0
    property int failures: 0
    readonly property int geometryWidth: 400
    // A list item draws its marker in an indent, so it is wider than the same text drawn plain by more than this.
    readonly property real widthTolerance: 0.5
    // Each case is a source whose decoded text starts a line, and that text drawn plain.
    readonly property var cases: [
        { name: "dot", source: "&#49;. ol\n", plain: "1. ol" },
        { name: "paren", source: "&#49;) ol\n", plain: "1) ol" },
        { name: "digits", source: "&#52;&#50;. answer\n", plain: "42. answer" },
        { name: "hex", source: "&#x31;. hex\n", plain: "1. hex" },
        { name: "dash", source: "&#45; a\n", plain: "- a" },
        { name: "plus", source: "&#43; a\n", plain: "+ a" },
        { name: "star", source: "&#42; a\n", plain: "* a" },
        { name: "hash", source: "&#35; h\n", plain: "# h" },
        { name: "quote mark", source: "&#62; q\n", plain: "> q" },
        { name: "fence", source: "&#96;&#96;&#96;\nx\n", plain: "``` x" },
        { name: "pipe", source: "&#124; a &#124; b &#124;\n", plain: "| a | b |" },
        { name: "rule", source: "&#45;&#45;&#45;\n", plain: "---" },
        { name: "after a soft break", source: "a\n&#49;. b\n", plain: "a 1. b" },
        { name: "after a hard break", source: "a  \n&#49;. b\n", plain: "a\n1. b", rich: true },
        { name: "in a list item", source: "- &#49;. ol\n", plain: "1. ol", part: "item" },
        { name: "in a quote", source: "> &#49;. ol\n", plain: "1. ol", part: "quote" }
    ]

    function check(ok, name) {
        checks++
        console.log((ok ? "ok " : "FAIL ") + name)
        if (!ok)
            failures++
    }

    function item(module, text, plain) {
        var format = plain ? "Text.PlainText" : "Text.MarkdownText"
        var made = Qt.createQmlObject('import QtQuick\nimport "' + module + '" as Flea\nFlea.MarkdownText {\nwidth: ' + geometryWidth
            + '\ntextFormat: ' + format + '\n}', sandbox)
        made.text = text
        made.forceLayout()
        return made
    }

    Component.onCompleted: {
        var module = Qt.resolvedUrl(Qt.application.arguments[Qt.application.arguments.length - 1])
        for (var i = 0; i < cases.length; i++) {
            var c = cases[i]
            var blocks = Markdown.blocks(c.source, "/doc", "#181825", "#c0caf5")
            var shown = c.part === "item" ? blocks[0].items[0] : blocks[0].text
            var drawn = item(module, shown, false)
            var reference = item(module, c.plain, true)
            // Qt counts a line break inside one rich paragraph as part of its line, so that case is held by its width alone.
            check(c.rich === true || drawn.lineCount === reference.lineCount, "literal " + c.name + " has the lines of its plain text (" + drawn.lineCount + " against " + reference.lineCount + ")")
            check(Math.abs(drawn.implicitWidth - reference.implicitWidth) <= widthTolerance,
                "literal " + c.name + " is as wide as its plain text (" + drawn.implicitWidth + " against " + reference.implicitWidth + ")")
        }
        // The pinned box sits in the item's own line box: a font tag opens no taller line than the bare glyph.
        var task = Markdown.blocks("- [ ] a\n", "/doc", "#181825", "#c0caf5")[0].items[0]
        var pinned = item(module, task, false)
        var bare = item(module, "\u2610 a", false)
        check(pinned.implicitHeight === bare.implicitHeight, "a pinned task box keeps the line height (" + pinned.implicitHeight + " against " + bare.implicitHeight + ")")
        console.log("MARKDOWN_LITERAL " + checks + " checks, " + failures + " failed")
        Qt.exit(failures === 0 ? 0 : 1)
    }
}
