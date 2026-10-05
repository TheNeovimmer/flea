.import "markdown-tables.js" as Tables

// Readers over the live tree for the list cases: where each row's marker sits against its item text, by number and by drawn ink.

// A list marker must sit on its item's first baseline; more than this far apart is a floating bullet.
var MARKER_BASELINE_TOLERANCE = 1

// List cases whose rows must judge at least one marker, so an all-skipped fixture fails instead of passing empty.
var LIST_CASES = ["piclist", "picordered", "picparts"]

// The first drawn text under an item's blocks, in tree order, skipping the hidden measurer.
function firstPartsText(blocks) {
    if (blocks.children === undefined)
        return null
    for (var i = 0; i < blocks.children.length; i++) {
        var kid = blocks.children[i]
        if (kid.box !== undefined && kid.baselineOffset !== undefined && kid.visible && typeof kid.text === "string" && kid.text.length > 0 && kid.objectName !== "measurer")
            return kid
        var deep = firstPartsText(kid)
        if (deep !== null)
            return deep
    }
    return null
}

// The text a row's marker sits against: its own item text, or the first paragraph run of an item drawn through itemParts; null when neither is judgeable.
// Sample input: textOf(row) answers { text, parts: false } for a prose item, { text, parts: true } for an item whose first block is a run, else null.
function textOf(row) {
    if (row.children.length < 2 || row.children[0].box === undefined || row.children[1].box === undefined)
        return null
    if (row.children[1].visible)
        return { text: row.children[1], parts: false }
    var loader = null
    for (var k = 0; k < row.children.length; k++) {
        var cand = row.children[k]
        if (cand.active !== undefined && cand.item !== undefined) {
            loader = cand
            break
        }
    }
    if (loader === null || !loader.active || loader.item === null || loader.item.blocks === undefined || loader.item.blocks.length === 0)
        return null
    var first = loader.item.blocks[0]
    if (first.type !== "run" || first.maths !== undefined)
        return null
    var firstView = null
    for (var v = 0; v < loader.item.children.length; v++) {
        if (loader.item.children[v].block !== undefined) {
            firstView = loader.item.children[v]
            break
        }
    }
    var firstText = firstView !== null ? firstPartsText(firstView) : null
    return firstText === null || !firstText.visible ? null : { text: firstText, parts: true }
}

// Blank when every drawn list row's marker shares its item text's first baseline, else the first row that does not.
function markerBaselineError(root, frame, name) {
    var rows = Tables.all(root, "listRow")
    var judged = 0
    for (var i = 0; i < rows.length; i++) {
        var found = textOf(rows[i])
        if (found === null)
            continue
        judged++
        var marker = rows[i].children[0]
        var markY = marker.mapToItem(frame, 0, marker.drawnBaseline).y
        var textY = found.text.mapToItem(frame, 0, found.text.drawnBaseline).y
        if (Math.abs(markY - textY) > MARKER_BASELINE_TOLERANCE)
            return "row " + i + " marker baseline " + markY + " differs from " + (found.parts ? "parts item " : "item ") + textY + " by " + (markY - textY) + " px"
    }
    var base = typeof name === "string" ? name.replace(Tables.CONTROL, "") : ""
    if (LIST_CASES.indexOf(base) >= 0 && judged === 0)
        return "case " + base + " judged no rows"
    return ""
}

// The rectangles of every judged list row's marker and item text in the frame's coordinates, for the judge that reads the marker's ink against the text's.
// Sample input: listInk(body.contentItem, frame, "piclist") answers { required: true, rows: [{ marker: { x, y, w, h }, text: { x, y, w, h }, picture }] }.
function listInk(root, frame, name) {
    function rect(item) {
        var at = item.mapToItem(frame, 0, 0)
        return { x: Math.round(at.x), y: Math.round(at.y), w: Math.round(item.width), h: Math.round(item.height) }
    }
    var rows = []
    var all = Tables.all(root, "listRow")
    for (var i = 0; i < all.length; i++) {
        var found = textOf(all[i])
        if (found !== null)
            rows.push({ marker: rect(all[i].children[0]), text: rect(found.text), picture: typeof found.text.markdown === "string" && found.text.markdown.indexOf("![") >= 0 })
    }
    return { required: LIST_CASES.indexOf(name.replace(Tables.CONTROL, "")) >= 0, rows: rows }
}
