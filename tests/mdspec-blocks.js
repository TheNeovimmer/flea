.pragma library

// The spec harness's adapter: Flea's block model, plus Qt's drawing of each block's text, as the HTML a reader would see.
.import "mdspec-qt.js" as Qt

// Sample input: "<p>a <em>b</em></p>" answers "a <em>b</em>"; anything else is returned whole.
function unwrap(html) {
    var m = /^<p>([\s\S]*)<\/p>$/.exec(html)
    return m !== null && m[1].indexOf("<p>") < 0 ? m[1] : html
}

var TASK_BOX_OPEN = '<font face="Noto Sans Symbols 2">☐</font> '
var TASK_BOX_DONE = '<font face="Noto Sans Symbols 2">☑</font> '

// Sample input: "<p>a</p><ul><li><p>b</p></li></ul>" answers "a<ul><li><p>b</p></li></ul>"; only paragraphs outside a nested list or quote go bare.
function bareParagraphs(html) {
    var depth = 0
    return html.replace(/<(\/?)(ul|ol|blockquote|p)\b[^>]*>/g, function (tag, closing, name) {
        if (name === "p")
            return depth === 0 ? "" : tag
        depth += closing === "/" ? -1 : 1
        return tag
    })
}

// One item as list-item content: its parts when it holds blocks, else Qt's drawing of its text; a task glyph becomes a checkbox, and a tight item keeps every paragraph bare.
function itemHtml(block, i, qt, dir, loose) {
    var parts = block.parts !== undefined && block.parts[i] ? block.parts[i] : null
    var text = parts !== null ? (parts[0].type === "run" ? parts[0].text : "") : block.items[i]
    var html = parts !== null ? blocksHtml(parts, qt, dir) : Qt.fromExport(qt(text), dir, text)
    var done = text.indexOf(TASK_BOX_DONE) === 0
    var box = done || text.indexOf(TASK_BOX_OPEN) === 0
    if (!loose)
        html = bareParagraphs(html)
    if (box)
        html = html.replace(done ? "☑ " : "☐ ", "<input " + (done ? "checked=\"\" " : "") + "disabled=\"\" type=\"checkbox\"> ")
    return html
}

// Sample input: items a (depth 0) and b (depth 1) answer "<ul><li>a<ul><li>b</li></ul></li></ul>"; a marker "" continues the open item.
function listHtml(block, qt, dir) {
    var open = []
    var out = ""
    function tagOf(ordered) {
        return ordered ? "ol" : "ul"
    }
    function closeTo(depth) {
        while (open.length > depth + 1) {
            out += "</li></" + tagOf(open[open.length - 1].ordered) + ">"
            open.length--
        }
    }
    for (var i = 0; i < block.items.length; i++) {
        var depth = block.depths !== undefined ? block.depths[i] : 0
        var marker = block.markers !== undefined ? block.markers[i] : block.ordered ? (block.start + i) + "." : "•"
        var loose = block.gaps !== undefined && block.gaps[i]
        closeTo(depth)
        if (marker === "") {
            out += itemHtml(block, i, qt, dir, loose)
            continue
        }
        var ordered = marker !== "•"
        if (open.length > depth && open[depth].ordered === ordered) {
            out += "</li>"
        } else {
            if (open.length > depth) {
                out += "</li></" + tagOf(open[depth].ordered) + ">"
                open.length--
            }
            var start = ordered ? parseInt(marker, 10) : 1
            out += "<" + tagOf(ordered) + (ordered && start !== 1 ? " start=\"" + start + "\"" : "") + ">"
            open.push({ ordered: ordered })
        }
        out += "<li>" + itemHtml(block, i, qt, dir, loose)
    }
    closeTo(-1)
    return out
}

var ALIGNED = { center: 1, right: 1 }

function tableHtml(block, qt, dir) {
    function cells(row, tag) {
        var out = ""
        for (var c = 0; c < block.cols; c++) {
            var align = ALIGNED.hasOwnProperty(block.aligns[c]) ? " align=\"" + block.aligns[c] + "\"" : ""
            out += "<" + tag + align + ">" + (c < row.length ? unwrap(Qt.fromExport(qt(row[c]), dir, row[c])) : "") + "</" + tag + ">"
        }
        return "<tr>" + out + "</tr>"
    }
    var body = ""
    for (var r = 0; r < block.rows.length; r++)
        body += cells(block.rows[r], "td")
    return "<table><thead>" + cells(block.head, "th") + "</thead>" + (body !== "" ? "<tbody>" + body + "</tbody>" : "") + "</table>"
}

// Sample input: info "js extra" answers class "language-js"; an empty info answers no class.
function fenceHtml(block) {
    var word = String(block.info || "").trim().split(/\s+/)[0]
    return "<pre><code" + (word !== "" ? " class=\"language-" + Qt.esc(word) + "\"" : "") + ">"
        + Qt.esc(block.text + (block.text === "" ? "" : "\n")) + "</code></pre>"
}

function blockHtml(block, qt, dir) {
    if (block.type === "heading")
        return "<h" + block.level + ">" + unwrap(Qt.fromExport(qt(block.text), dir, block.text)) + "</h" + block.level + ">"
    if (block.type === "run")
        return Qt.fromExport(qt(block.text), dir, block.text)
    if (block.type === "list")
        return listHtml(block, qt, dir)
    if (block.type === "table")
        return tableHtml(block, qt, dir)
    if (block.type === "fence")
        return fenceHtml(block)
    if (block.type === "image")
        return "<p><img src=\"" + Qt.esc(block.url.replace("file://" + dir + "/", "")) + "\" alt=\"" + Qt.esc(block.alt) + "\"></p>"
    if (block.type === "remote")
        return "<p>⟦remote " + Qt.esc(block.host) + "⟧</p>"
    return "<p>⟦" + block.type + "⟧</p>"
}

// A quote's content: its parts when it holds blocks, else Qt's drawing of its text.
function quoteHtml(block, qt, dir) {
    return block.parts !== undefined ? blocksHtml(block.parts, qt, dir) : Qt.fromExport(qt(block.text), dir, block.text)
}

// Quote blocks at depth 2 and more nest inside the quote before them; any other block closes every quote.
function blocksHtml(blocks, qt, dir) {
    var out = ""
    var depth = 0
    for (var i = 0; i < blocks.length; i++) {
        var want = blocks[i].type === "quote" ? blocks[i].depth || 1 : 0
        if (want > 0 && !blocks[i].joined)
            want = -want
        if (want < 0) {
            for (; depth > 0; depth--)
                out += "</blockquote>"
            want = -want
        }
        for (; depth < want; depth++)
            out += "<blockquote>"
        for (; depth > want; depth--)
            out += "</blockquote>"
        out += blocks[i].type === "quote" ? quoteHtml(blocks[i], qt, dir) : blockHtml(blocks[i], qt, dir)
    }
    return out + "</blockquote>".repeat(depth)
}
