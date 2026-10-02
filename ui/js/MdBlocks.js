.pragma library

// MdBlocks: the block layer over MdRun, CommonMark containers and leaves; every scan advances, no regex backtracks.
.import "MdUrl.js" as MdUrl
.import "MdHtml.js" as MdHtml
.import "MdInline.js" as Md
.import "MdLeaf.js" as Leaf
.import "MdRun.js" as Run
.import "MdRefs.js" as Refs

// Sample input: "  1. item" or "- [x] done"; contentCol is where item text starts, so a line indented that far continues it.
function listMarker(line) {
    var m = String(line).match(/^(\s*)(\d+[.)]|[-*+])(\s+)(.*)$/)
    if (!m)
        return null
    var indent = 0
    for (var i = 0; i < m[1].length; i++)
        indent += m[1].charAt(i) === "\t" ? 4 - (indent % 4) : 1
    if (indent > 3 || m[4].length === 0)
        return null
    var gap = 0
    for (var g = 0; g < m[3].length; g++)
        gap += m[3].charAt(g) === "\t" ? 4 - ((indent + m[2].length + gap) % 4) : 1
    var ordered = /^\d/.test(m[2])
    return { indent: indent, ordered: ordered, start: ordered ? parseInt(m[2], 10) : 0,
        text: Leaf.taskText(m[4]), contentCol: indent + m[2].length + gap }
}

// Top-level split: ordinary runs share one Text.MarkdownText, special kinds get delegates; fences keep their info string.
function blocks(source, dir, chrome, ink) {
    var body = String(source)
    var rawLines = body.split("\n")
    var found = Refs.collectDefs(rawLines)
    var foot = Refs.collectFootnotes(rawLines)
    var hide = {}
    function markHidden(ranges) {
        for (var h = 0; h < ranges.length; h++)
            for (var l = ranges[h][0]; l <= ranges[h][1]; l++)
                hide[l] = true
    }
    markHidden(found.dropped)
    markHidden(foot.dropped)
    var lines = []
    for (var li = 0; li < rawLines.length; li++) {
        if (!hide.hasOwnProperty(li))
            lines.push(rawLines[li])
    }
    var defs = found.defs
    var numbers = foot.numbers
    var tokens = []

    function inlineOf(joined) {
        return Run.parseInline(joined, dir, defs, numbers, chrome, ink, tokens)
    }

    var out = []
    var run = []
    var quote = []
    var fence = null
    var fenceInfo = ""
    var fenceTick = ""
    var fenceLen = 0
    var inParagraph = false

    function flushRun() {
        if (run.length === 0) {
            inParagraph = false
            return
        }
        var text = inlineOf(run.join("\n"))
        if (text.trim().length > 0)
            out.push({ type: "run", text: text })
        run = []
        inParagraph = false
    }
    function flushQuote() {
        if (quote.length === 0)
            return
        var inner = quote.map(function (line) { return line.replace(/^ {0,3}> ?/, "") })
        var titled = inner.slice()
        var title = Leaf.alertTitle(titled[0] || "")
        if (title !== null)
            titled[0] = title
        out.push({ type: "quote", text: inlineOf(titled.join("\n")) })
        quote = []
    }
    function flushFence() {
        out.push({ type: "fence", text: fence.join("\n"), info: fenceInfo })
        fence = null
        fenceInfo = ""
    }
    var list = null
    function flushList() {
        if (list === null)
            return
        var items = []
        for (var k = 0; k < list.items.length; k++)
            items.push(inlineOf(list.items[k].join("\n")))
        out.push({ type: "list", ordered: list.ordered, start: list.start, items: items })
        list = null
    }

    // YAML front matter at line 1 draws as a fenced block.
    var i = 0
    if (lines.length > 0 && lines[0] === "---") {
        var fe = 1
        while (fe < lines.length && lines[fe] !== "---" && lines[fe] !== "...")
            fe++
        if (fe < lines.length) {
            out.push({ type: "fence", text: lines.slice(1, fe).join("\n"), info: "" })
            i = fe + 1
        }
    }

    for (; i < lines.length; i++) {
        var line = lines[i]
        if (fence !== null) {
            var fo = Leaf.fenceOpen(line)
            // A closing fence matches tick, has no info and is at least as long; anything else inside is literal.
            if (fo !== null && fo.info === "" && fo.tick === fenceTick && fo.len >= fenceLen)
                flushFence()
            else
                fence.push(line)
            continue
        }
        var open = Leaf.fenceOpen(line)
        if (open !== null) {
            flushRun()
            flushQuote()
            flushList()
            fence = []
            fenceInfo = open.info
            fenceTick = open.tick
            fenceLen = open.len
            continue
        }
        // Indented code: four spaces or a tab outside a paragraph draws verbatim.
        if (!inParagraph && (/^ {4}/.test(line) || /^\t/.test(line))) {
            flushRun()
            flushQuote()
            flushList()
            var code = []
            while (i < lines.length && (/^(?: {4}|\t)/.test(lines[i])
                    || lines[i].trim().length === 0)) {
                if (lines[i].trim().length === 0) {
                    var peek = i + 1
                    while (peek < lines.length && lines[peek].trim().length === 0)
                        peek++
                    if (peek >= lines.length || !/^(?: {4}|\t)/.test(lines[peek]))
                        break
                }
                code.push(lines[i].replace(/^(?: {4}|\t)/, ""))
                i++
            }
            i--
            out.push({ type: "fence", text: code.join("\n"), info: "" })
            inParagraph = false
            continue
        }
        // A fence quoted as `> ``` ` is quote content, never a fence.
        if (/^ {0,3}>/.test(line)) {
            flushRun()
            flushList()
            quote.push(line)
            inParagraph = true
            continue
        }
        // A GFM table: a header line carrying | over a delimiter row.
        if (line.indexOf("|") >= 0 && i + 1 < lines.length && Leaf.delimAligns(lines[i + 1]) !== null) {
            var aligns = Leaf.delimAligns(lines[i + 1])
            var head = Leaf.splitRow(line)
            var bodyRows = []
            var j = i + 2
            while (j < lines.length && lines[j].trim().length > 0 && lines[j].indexOf("|") >= 0) {
                bodyRows.push(Leaf.splitRow(lines[j]))
                j++
            }
            flushRun()
            flushQuote()
            flushList()
            out.push(Leaf.tableBlock(head, aligns, bodyRows))
            i = j - 1
            continue
        }
        // A thematic break or setext underline stays a run; md4c draws the rule.
        if (Leaf.isThematic(line)) {
            flushQuote()
            flushList()
            run.push(line)
            inParagraph = true
            continue
        }
        var mark = listMarker(line)
        if (mark !== null) {
            // Below the content column a marker is a sibling of the same type, else it starts another list.
            var outside = list !== null && mark.indent < list.contentCol
            if (list === null || (outside && mark.ordered !== list.ordered))
                flushList()
            if (list === null) {
                flushRun()
                flushQuote()
                list = { ordered: mark.ordered, start: mark.start, indent: mark.indent,
                    contentCol: mark.contentCol, items: [[mark.text]] }
            } else if (outside) {
                list.indent = mark.indent
                list.contentCol = mark.contentCol
                list.items.push([mark.text])
            } else {
                list.items[list.items.length - 1].push(line.slice(list.contentCol))
            }
            inParagraph = true
            continue
        }
        if (list !== null) {
            if (line.trim().length > 0) {
                // Indented to the content column continues the item (a paragraph, not code); a lazy line joins whole.
                if (Leaf.indentOf(line) >= list.contentCol)
                    list.items[list.items.length - 1].push(line.slice(list.contentCol))
                else
                    list.items[list.items.length - 1].push(line)
                    inParagraph = true
                continue
            }
            var n = i + 1
            while (n < lines.length && lines[n].trim().length === 0)
                n++
            var nm = n < lines.length ? listMarker(lines[n]) : null
            if (nm !== null && nm.indent <= 3) {
                list.items[list.items.length - 1].push("")
                continue
            }
            // List-indent trick: a blank then a line at the content column stays in the item, blank included.
            if (n < lines.length && Leaf.indentOf(lines[n]) >= list.contentCol) {
                list.items[list.items.length - 1].push("")
                continue
            }
            flushList()
        }
        var solo = line.trim().length > 0 && (i === 0 || lines[i - 1].trim().length === 0)
            && (i === lines.length - 1 || lines[i + 1].trim().length === 0)
        var held = solo ? Leaf.standaloneImage(line, dir, defs) : null
        if (held !== null) {
            flushRun()
            flushQuote()
            flushList()
            out.push(held)
            inParagraph = false
            continue
        }
        flushQuote()
        // Definition-shaped lines never reach md4c: collected ones dropped above, leftovers lose their bracket.
        run.push(Refs.killDefinition(line))
        if (line.trim().length > 0)
            inParagraph = true
        else
            inParagraph = false
    }
    if (fence !== null)
        flushFence()
    flushList()
    flushQuote()
    flushRun()
    // Footnote definitions list after a rule, only for notes whose <sup> number a run, quote or list item emitted.
    var usedNums = {}
    for (var b = 0; b < out.length; b++) {
        var block = out[b]
        var inlineTexts = block.type === "list" ? block.items
            : (block.type === "run" || block.type === "quote") ? [block.text] : []
        for (var t = 0; t < inlineTexts.length; t++) {
            var re = /<sup>(\d+)<\/sup>/g
            var hit = null
            while ((hit = re.exec(inlineTexts[t])) !== null)
                usedNums[hit[1]] = true
        }
    }
    var footItems = []
    for (var q = 0; q < foot.order.length; q++) {
        var id = foot.order[q]
        if (usedNums.hasOwnProperty(String(foot.notes[id].n)))
            footItems.push("<sup>" + foot.notes[id].n + "</sup> " + inlineOf(foot.notes[id].text))
    }
    if (footItems.length > 0) {
        out.push({ type: "run", text: "---" })
        out.push({ type: "list", ordered: false, start: 0, items: footItems })
    }
    return out
}


