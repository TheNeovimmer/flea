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

// A rich text's lineCount stays 1, so lines are its content height over the 1.7 line box MarkdownText sets.
// What one table drew in a pane whose block column is avail wide, in the table's own frame.
function geometry(table, avail) {
    var cells = cellsOf(table).map(function (cell) {
        var at = cell.mapToItem(table, 0, 0)
        return { text: cell.text, x: Math.round(at.x), y: Math.round(at.y), w: Math.round(cell.width), h: Math.round(cell.height),
            content: Math.round(cell.contentWidth), lines: Math.round(cell.contentHeight / cell.box) }
    })
    return { measurers: all(table, "measurer").map(function (m) { return { text: m.text, w: Math.round(m.implicitWidth) } }), w: Math.round(table.width), h: Math.round(table.height), avail: Math.round(avail), cells: cells }
}

// Blank when every cell sits inside the table and the table inside its block column, else the first offender.
function fitError(geo) {
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

// Cases whose columns cannot all keep a glyph in the narrow column, so only Quick Look's card must hold them (a design question, not a fit).
var NARROW_OVERFLOW = ["wide", "extreme"]
// Cases Quick Look's card has room for, so no cell of them may wrap.
var ONE_LINE = ["inline", "cjk", "align", "ragged", "adjacent", "headonly", "nested", "rows500"]

// Blank when a table drew the lines the case promises in this pane, else what it drew.
function lineError(name, label, geos) {
    var geo = geos.length > 0 ? geos[0] : null
    if (geo === null)
        return "no table was built"
    if (label === "card" && ONE_LINE.indexOf(name) >= 0) {
        for (var i = 0; i < geo.cells.length; i++)
            if (geo.cells[i].lines !== 1)
                return "cell " + i + " (" + geo.cells[i].text + ") wrapped to " + geo.cells[i].lines + " lines in a card that has room"
    }
    if (name === "br") {
        var broken = geo.cells.filter(function (c) { return c.text.indexOf("<br") >= 0 }).map(function (c) { return c.lines })
        if (label === "card" && JSON.stringify(broken) !== "[3,2]")
            return "break cells drew " + JSON.stringify(broken) + " lines, not [3,2]"
        var plain = geo.cells.filter(function (c) { return c.text.indexOf("<br") < 0 && c.lines !== 1 })
        if (label === "card" && plain.length > 0)
            return "a plain cell wrapped because a break cell set the column: " + plain[0].text
    }
    if (name === "rows500" && label === "card" && geos.length > 4)
        return geos.length + " table chunks are alive in a screenful"
    if (name === "sentence" || name === "path") {
        var long = geo.cells.reduce(function (a, c) { return c.lines > a ? c.lines : a }, 0)
        if (long < 2)
            return "the long cell stayed on one line"
    }
    return ""
}
