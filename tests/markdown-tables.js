// Readers over the live tree for the table cases: each table a pane built, and the geometry of its cells.

// Layout positions may differ from the recipe by this many pixels.
var TOLERANCE = 0.5

// Every descendant of item with this objectName, in tree order (a ListView's content item is a child of the view).
function all(item, name) {
    var found = []
    for (var i = 0; i < item.children.length; i++) {
        var kid = item.children[i]
        if (kid.objectName === name)
            found.push(kid)
        found = found.concat(all(kid, name))
    }
    return found
}

// Every rich text a table drew, header cells first, in tree order.
function cellsOf(table) {
    var found = []
    function walk(item) {
        for (var i = 0; i < item.children.length; i++) {
            var kid = item.children[i]
            if (kid.textFormat !== undefined && kid.visible && typeof kid.text === "string" && kid.text.length > 0 && kid.objectName !== "measurer")
                found.push(kid)
            else
                walk(kid)
        }
    }
    walk(table)
    return found
}

// The hidden texts a table measures its columns with, in column order.
function measurersOf(table) {
    var found = []
    for (var i = 0; i < table.children.length; i++) {
        var kid = table.children[i]
        if (kid.textFormat !== undefined && !kid.visible)
            found.push({ text: kid.text, w: Math.round(kid.implicitWidth) })
        else if (kid.children.length > 0 && kid.visible === undefined)
            found = found.concat(measurersOf(kid))
    }
    return found
}

// Lines are content height over the 1.7 line box since lineCount stays 1; what one table drew in a pane avail wide at body offset tx.
// Sample input: geometry(table, 812, 8) answers { w, tx: 8, avail: 812, glyph, gap, cells } with each cell's laid-out line width as content.
function geometry(table, avail, tx) {
    var cells = cellsOf(table).map(function (cell) {
        var at = cell.mapToItem(table, 0, 0)
        return { text: cell.text, x: Math.round(at.x), y: Math.round(at.y), w: Math.round(cell.width), h: Math.round(cell.height),
            content: Math.round(cell.contentWidth), lines: Math.round(cell.contentHeight / cell.box) }
    })
    return { measurers: all(table, "measurer").map(function (m) { return { text: m.text, w: Math.round(m.implicitWidth) } }), w: Math.round(table.width), h: Math.round(table.height), tx: tx, avail: Math.round(avail), glyph: table.glyphPx, gap: table.cellGap, cells: cells }
}

// Blank when the table sits inside its block column at its body offset and every cell inside the table, else the first offender.
function fitError(geo) {
    if (geo.tx + geo.w > geo.avail + TOLERANCE)
        return "the table starts at " + geo.tx + " and is " + geo.w + " wide in a " + geo.avail + " column"
    if (geo.w > geo.avail + TOLERANCE)
        return "the table is " + geo.w + " wide in a " + geo.avail + " column"
    for (var i = 0; i < geo.cells.length; i++) {
        var c = geo.cells[i]
        if (c.x + c.w > geo.w + TOLERANCE)
            return "cell " + i + " ends at " + (c.x + c.w) + " past the table's " + geo.w
        if (c.content > c.w + TOLERANCE)
            return "cell " + i + " draws " + c.content + " px of text in " + c.w
    }
    return ""
}

// Blank when every cell's drawn text ends a full gap before the next cell in its row, else the first overlap.
function gapError(geo) {
    var rows = {}
    for (var i = 0; i < geo.cells.length; i++) {
        var key = geo.cells[i].y
        if (rows[key] === undefined)
            rows[key] = []
        rows[key].push(geo.cells[i])
    }
    for (var y in rows) {
        var row = rows[y].sort(function (a, b) { return a.x - b.x })
        for (var k = 0; k + 1 < row.length; k++) {
            if (row[k].x + row[k].content + geo.gap > row[k + 1].x + TOLERANCE)
                return "row at y " + y + " draws text to " + (row[k].x + row[k].content) + " with " + (row[k + 1].x - row[k].x - row[k].content) + " px before the next cell, not " + geo.gap
        }
    }
    return ""
}

// Cases whose columns cannot all keep a glyph in the narrow column, so only Quick Look's card must hold them (a design question, not a fit).
var NARROW_OVERFLOW = ["wide", "extreme"]
// Cases Quick Look's card has room for, so no cell of them may wrap.
var ONE_LINE = ["inline", "cjk", "align", "ragged", "adjacent", "headonly", "nested", "rows500"]

// Blank when every table the pane built drew the lines the case promises in this pane, else what table t drew.
function lineError(name, label, geos) {
    if (geos.length === 0)
        return "no table was built"
    for (var t = 0; t < geos.length; t++) {
        var geo = geos[t]
        if (label === "card" && ONE_LINE.indexOf(name) >= 0) {
            for (var i = 0; i < geo.cells.length; i++)
                if (geo.cells[i].lines !== 1)
                    return "table " + t + " cell " + i + " (" + geo.cells[i].text + ") wrapped to " + geo.cells[i].lines + " lines in a card that has room"
        }
        if (name === "br") {
            var broken = geo.cells.filter(function (c) { return c.text.indexOf("<br") >= 0 }).map(function (c) { return c.lines })
            if (label === "card" && JSON.stringify(broken) !== "[3,2]")
                return "table " + t + " break cells drew " + JSON.stringify(broken) + " lines, not [3,2]"
            var plain = geo.cells.filter(function (c) { return c.text.indexOf("<br") < 0 && c.lines !== 1 })
            if (label === "card" && plain.length > 0)
                return "table " + t + " plain cell wrapped because a break cell set the column: " + plain[0].text
        }
        if (name === "sentence" || name === "path") {
            var long = geo.cells.reduce(function (a, c) { return c.lines > a ? c.lines : a }, 0)
            if (long < 2)
                return "table " + t + " long cell stayed on one line"
        }
    }
    if (name === "rows500" && label === "card" && geos.length > 4)
        return geos.length + " table chunks are alive in a screenful"
    return ""
}
