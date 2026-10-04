import QtQuick
import "../ui/js/Markdown.js" as Markdown
import "mdspec-blocks.js" as Blocks
import "mdspec-canon.js" as Canon
import "mdspec-rules.js" as Rules

// Feeds every CommonMark 0.31.2 example and every GFM extension example through Flea's parser and Qt's drawing of its text,
// and compares the structure drawn with the spec's HTML. Per-section pass counts only ever go up: RECORDED is the ratchet.
Item {
    id: gate

    readonly property string fixtures: Qt.resolvedUrl("fixtures/markdown-spec/")
    readonly property string dir: "/spec"
    readonly property string chrome: "#181825"
    readonly property string ink: "#c0caf5"
    // Sections in spec order, each with the count of examples that pass today; a section below its count fails the suite.
    readonly property var recorded: ({
        "Tabs": 8,
        "Backslash escapes": 13,
        "Entity and numeric character references": 14,
        "Precedence": 1,
        "Thematic breaks": 19,
        "ATX headings": 17,
        "Setext headings": 25,
        "Indented code blocks": 12,
        "Fenced code blocks": 29,
        "HTML blocks": 14,
        "Link reference definitions": 23,
        "Paragraphs": 8,
        "Blank lines": 1,
        "Block quotes": 22,
        "List items": 43,
        "Lists": 26,
        "Inlines": 1,
        "Code spans": 21,
        "Emphasis and strong emphasis": 131,
        "Links": 84,
        "Images": 8,
        "Autolinks": 11,
        "Raw HTML": 14,
        "Hard line breaks": 15,
        "Soft line breaks": 2,
        "Textual content": 3,
        "GFM table": 7,
        "GFM task list items": 2,
        "GFM strikethrough": 2,
        "GFM autolink": 11,
        "GFM tagfilter": 0
    })

    TextEdit {
        id: engine
        textFormat: TextEdit.MarkdownText
        font.family: "Sans Serif"
    }

    // Qt's HTML export of a Markdown string: the structure the Text item draws, as the document holds it.
    function exported(markdown) {
        engine.textFormat = TextEdit.MarkdownText
        engine.text = markdown
        engine.textFormat = TextEdit.RichText
        var html = engine.getFormattedText(0, engine.length)
        engine.textFormat = TextEdit.MarkdownText
        return html
    }

    function read(name) {
        var request = new XMLHttpRequest()
        request.open("GET", gate.fixtures + name, false)
        request.send()
        return request.responseText
    }

    // Sample input: the cmark spec writes a tab as an arrow, "→", inside its examples.
    function gfmExamples(text) {
        var lines = text.split("\n")
        var fence = "`".repeat(32) + " example"
        var out = []
        var section = ""
        var number = 0
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            if (line.indexOf(fence) !== 0) {
                var h = /^## (.*)$/.exec(line)
                if (h !== null)
                    section = h[1]
                continue
            }
            var kind = line.slice(fence.length).trim()
            var md = []
            var html = []
            var target = md
            for (i++; i < lines.length && lines[i].indexOf("`".repeat(32)) !== 0; i++) {
                if (lines[i] === ".")
                    target = html
                else
                    target.push(lines[i])
            }
            number++
            if (kind === "")
                continue
            out.push({ markdown: md.join("\n").replace(/→/g, "\t") + "\n", html: html.join("\n").replace(/→/g, "\t") + (html.length > 0 ? "\n" : ""),
                section: section, example: number, kind: kind })
        }
        return out
    }

    function drawn(example) {
        var blocks = Markdown.blocks(example.markdown, gate.dir, gate.chrome, gate.ink)
        return Canon.canon(Blocks.blocksHtml(blocks, gate.exported, gate.dir), false)
    }

    function verdict(example) {
        var want = Canon.canon(example.html, true)
        var got = ""
        try {
            got = gate.drawn(example)
        } catch (e) {
            got = "THROW " + e
        }
        var rule = Rules.exceptionFor(example)
        if (rule !== "" && Rules.RULES[rule].varies === true)
            return { state: "exception", rule: rule, got: got, want: want }
        if (got === want)
            return { state: rule === "" ? "pass" : "stale", rule: rule, got: got, want: want }
        return { state: rule === "" ? "fail" : "exception", rule: rule, got: got, want: want }
    }

    Component.onCompleted: {
        var args = Qt.application.arguments
        var listAt = args.indexOf("list")
        var showAt = args.indexOf("show")
        var cm = JSON.parse(gate.read("commonmark-0.31.2-spec.json"))
        var examples = []
        for (var c = 0; c < cm.length; c++)
            examples.push({ markdown: cm[c].markdown, html: cm[c].html, section: cm[c].section, example: cm[c].example, kind: "commonmark" })
        var gfm = gate.gfmExamples(gate.read("gfm-spec.txt"))
        for (var g = 0; g < gfm.length; g++) {
            if (gfm[g].kind === "disabled")
                gfm[g].section = "GFM task list items"
            else
                gfm[g].section = "GFM " + gfm[g].kind
            gfm[g].example = "gfm" + gfm[g].example
            examples.push(gfm[g])
        }
        var order = []
        var tally = {}
        var rules = {}
        var failed = 0
        for (var i = 0; i < examples.length; i++) {
            var ex = examples[i]
            if (showAt >= 0 && String(ex.example) !== args[showAt + 1])
                continue
            var v = gate.verdict(ex)
            if (!tally.hasOwnProperty(ex.section)) {
                tally[ex.section] = { pass: 0, exception: 0, fail: 0, stale: 0 }
                order.push(ex.section)
            }
            tally[ex.section][v.state]++
            if (v.state === "exception")
                rules[v.rule] = (rules[v.rule] || 0) + 1
            if (v.state === "stale")
                console.log("FAIL example " + ex.example + " now draws as the spec's HTML, so rule " + v.rule + " no longer names it")
            if (showAt >= 0)
                console.log("MDSPEC show " + ex.example + " " + v.state + "\nmd:   " + JSON.stringify(ex.markdown) + "\nwant: " + v.want + "\ngot:  " + v.got)
            else if (listAt >= 0 && v.state === "fail")
                console.log("MDSPEC fail " + ex.section + " " + ex.example + (args.indexOf("dump") >= 0
                    ? "\nmd:   " + JSON.stringify(ex.markdown) + "\nwant: " + v.want + "\ngot:  " + v.got : ""))
        }
        var total = 0
        var passes = 0
        var snapshot = []
        for (var s = 0; s < order.length; s++) {
            var name = order[s]
            var t = tally[name]
            var count = t.pass + t.exception + t.fail + t.stale
            var record = gate.recorded.hasOwnProperty(name) ? gate.recorded[name] : -1
            total += count
            passes += t.pass
            snapshot.push("        \"" + name + "\": " + t.pass)
            console.log("MDSPEC " + name + ": pass " + t.pass + " of " + count + " (exceptions " + t.exception + ", failing " + t.fail + "), recorded " + record)
            if (showAt >= 0)
                continue
            if (t.pass < record) {
                console.log("FAIL " + name + ": " + t.pass + " pass, the recorded count is " + record)
                failed++
            } else if (record < 0) {
                console.log("FAIL " + name + ": no recorded count")
                failed++
            }
            if (t.fail > 0) {
                console.log("FAIL " + name + ": " + t.fail + " examples fail and no rule names them")
                failed++
            }
            failed += t.stale
        }
        if (args.indexOf("record") >= 0)
            console.log("MDSPEC recorded {\n" + snapshot.join(",\n") + "\n    }")
        for (var rule in rules)
            console.log("MDSPEC exception " + rule + ": " + rules[rule] + " examples, " + Rules.RULES[rule].text)
        console.log("markdown-spec: " + passes + " of " + total + " examples drawn as the spec's HTML, " + failed + " failures")
        Qt.exit(failed === 0 && (showAt >= 0 || total > 0) ? 0 : 1)
    }
}
