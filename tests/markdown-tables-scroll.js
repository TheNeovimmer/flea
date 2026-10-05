// Readers and judges of the sideways scroll a table wider than its pane owns: its flickable and bar, the chunks that share a position, and the wheel and touchpad routes.
// The reading helpers and the tolerance come from the table readers, the router's state from the app's own Scroll.js.
.import "markdown-tables.js" as Tables
.import "flea/js/Scroll.js" as Scroll

// The sideways scroll a table wider than its pane owns: one flickable each, exactly its columns wide, one bar under the table (its last chunk), none of it in a positioner's flow, and nothing on a table that fits.
// Sample input: scrollError(tables, scrollers, bars) answers "" when 2 tables, one overflowing, hold 1 flickable and 1 bar.
function scrollError(tables, scrollers, bars) {
    var wide = tables.filter(function (t) { return t.overflows })
    if (scrollers.length !== wide.length)
        return scrollers.length + " flickables for " + wide.length + " overflowing tables"
    if (bars.length !== wide.length)
        return bars.length + " bars for " + wide.length + " overflowing tables"
    var lanes = wide.filter(function (t) { return t.lane }).length
    if (bars.filter(function (b) { return b.visible }).length !== lanes)
        return bars.filter(function (b) { return b.visible }).length + " bars shown for " + lanes + " lanes"
    for (var t = 0; t < tables.length; t++) {
        var table = tables[t]
        var own = scrollers.filter(function (s) { return s.table === table })
        if (!table.overflows) {
            if (own.length > 0 || table.scroller !== null)
                return "table " + t + " fits its pane and built a flickable"
            continue
        }
        if (own.length !== 1)
            return "table " + t + " overflows its pane and has " + own.length + " flickables"
        var columns = 0
        for (var c = 0; c < table.widths.length; c++)
            columns += table.widths[c]
        if (Math.abs(own[0].contentWidth - columns) > Tables.TOLERANCE)
            return "table " + t + " flickable is " + own[0].contentWidth + " wide, its columns sum " + columns
        // The block's own width: the pane's for a table at the top, the item's or quote's inside one.
        if (own[0].contentWidth <= table.availableWidth + Tables.TOLERANCE)
            return "table " + t + " flickable is " + own[0].contentWidth + " wide in a " + table.availableWidth + " block"
        if (Math.abs(table.width - table.availableWidth) > Tables.TOLERANCE)
            return "table " + t + " draws " + table.width + " wide, not its block's " + table.availableWidth
        var flow = flowError(table, own[0], bars)
        if (flow !== "")
            return "table " + t + " " + flow
    }
    return ""
}

// Blank when a table's flickable and bar sit beside it in a block that stacks nothing, the bar in the table's own lane, and the block after it has not moved.
// Sample input: flowError(table, scroller, bars) answers "" for a table in a list item whose bar sits at the table's foot and whose next block keeps the column's spacing.
function flowError(table, scroller, bars) {
    var view = table.parent
    if (view.move !== undefined)
        return "sits in a positioner"
    if (scroller.parent !== view)
        return "flickable is not beside the table"
    if (Math.abs(scroller.y - table.y) > Tables.TOLERANCE || Math.abs(scroller.x - table.x) > Tables.TOLERANCE || Math.abs(scroller.width - table.width) > Tables.TOLERANCE)
        return "flickable is at " + scroller.x + "," + scroller.y + ", the table at " + table.x + "," + table.y
    if (Math.abs(view.height - (table.y + table.height)) > Tables.TOLERANCE)
        return "block is " + view.height + " tall, the table ends at " + (table.y + table.height)
    var bar = bars.filter(function (b) { return b.flickable === scroller })[0]
    if (bar === undefined || bar.parent !== view)
        return "has no bar beside it"
    if (table.lane && (Math.abs(bar.y - (table.y + table.height - bar.height)) > Tables.TOLERANCE || Math.abs(bar.x - table.x) > Tables.TOLERANCE))
        return "bar is at " + bar.x + "," + bar.y + ", not at the table's foot " + (table.y + table.height - bar.height)
    var column = view.parent
    if (column.move === undefined)
        return ""
    var at = -1
    for (var i = 0; i < column.children.length; i++)
        if (column.children[i] === view)
            at = i
    var next = column.children[at + 1]
    if (next !== undefined && next.blockIndex !== undefined && Math.abs(next.y - (view.y + view.height + column.spacing)) > Tables.TOLERANCE)
        return "pushed the next block to " + next.y + ", past " + (view.y + view.height + column.spacing)
    return ""
}

// Blank when the live chunks of every chunked table share one sideways position after a wheel over each of two of them, else the first that differs.
// Sample input: chunkError(tables, send) with 3 chunks answers "" when a wheel over chunk 1 and then chunk 3 leaves all three at one contentX and one x of their first cell.
function chunkError(tables, route, send) {
    var chunks = tables.filter(function (t) { return t.overflows && t.block.tableKey !== undefined })
    if (chunks.length < 2)
        return chunks.length + " chunks of a table alive, two are needed"
    var pick = [chunks[0], chunks[chunks.length - 1]]
    for (var w = 0; w < pick.length; w++) {
        var scroller = pick[w].scroller
        var at = scroller.mapToItem(route, scroller.width / 2, WHEEL_ROW_PX)
        send(route, at.x, at.y, -WHEEL_NOTCH, 0, Qt.NoModifier)
        var x = scroller.contentX
        if (x <= 0)
            return "a wheel over chunk " + (w === 0 ? "first" : "last") + " left it at " + x
        for (var c = 0; c < chunks.length; c++) {
            var first = Tables.cellsOf(chunks[c])[0].mapToItem(chunks[c], 0, 0).x
            if (chunks[c].scroller.contentX !== x || Math.abs(first + x) > Tables.TOLERANCE)
                return "chunk " + c + " is at " + chunks[c].scroller.contentX + " and draws its first cell at " + first + " after chunk " + (w === 0 ? "first" : "last") + " moved to " + x
        }
    }
    for (var r = 0; r < chunks.length; r++)
        chunks[r].scroller.contentX = 0
    return ""
}

// Every horizontal scroll bar under item, which only a table that overflows owns.
function barsIn(item) {
    var found = []
    for (var i = 0; i < item.children.length; i++) {
        var kid = item.children[i]
        if (kid.knobItem !== undefined && kid.orientation === Qt.Horizontal)
            found.push(kid)
        found = found.concat(barsIn(kid))
    }
    return found
}

// A wheel notch of Qt's angle delta, and how far under a table's top the wheel points.
var WHEEL_NOTCH = 120
var WHEEL_ROW_PX = 8
// A touchpad update's pixels, far over the dead zone.
var TOUCH_PX = 40

// Blank when real wheel events (send) over the first overflowing table of a pane scroll it sideways and by Shift, and a vertical one moves the document and not the table.
// Sample input: wheelError(route, scroller, body, send) answers "" when send(route, x, y, -120, 0, 0) moved contentX and send(route, x, y, 0, -120, 0) moved body.contentY.
function wheelError(route, scroller, body, send) {
    var at = scroller.mapToItem(route, scroller.width / 2, WHEEL_ROW_PX)
    var before = scroller.contentX
    send(route, at.x, at.y, -WHEEL_NOTCH, 0, Qt.NoModifier)
    if (scroller.contentX <= before)
        return "a sideways wheel left the table at " + before + " (now " + scroller.contentX + ")"
    // The first notch may have reached the far end, so Shift+wheel turns back: an upward notch with Shift scrolls left.
    before = scroller.contentX
    send(route, at.x, at.y, 0, WHEEL_NOTCH, Qt.ShiftModifier)
    if (scroller.contentX >= before)
        return "Shift+wheel left the table at " + before + " (now " + scroller.contentX + ")"
    before = scroller.contentX
    var tops = body.contentY
    send(route, at.x, at.y, 0, -WHEEL_NOTCH, Qt.NoModifier)
    if (scroller.contentX !== before)
        return "a vertical wheel over the table moved it from " + before + " to " + scroller.contentX
    if (body.contentY <= tops)
        return "a vertical wheel over the table left the document at " + tops
    return ""
}

// The touchpad branch of the router, each answer blank or what went wrong: [Begin reaches both, the first update locks the table, a vertical stroke stays with the document, End releases].
// Sample input: touchErrors(route, scroller) answers ["", "", "", ""] after a horizontal stroke and a vertical one, each Begin, Updates, End.
function touchErrors(route, scroller) {
    var at = scroller.mapToItem(route, scroller.width / 2, WHEEL_ROW_PX)
    function stroke(phase, px, py) {
        return { x: at.x, y: at.y, pixelDelta: { x: px, y: py }, angleDelta: { x: 0, y: 0 }, modifiers: 0, phase: phase, accepted: false }
    }
    var errors = ["", "", "", ""]
    var samples = Scroll.tailState(scroller, true).samples.length
    var began = route.route(stroke(Qt.ScrollBegin, 0, 0))
    if (began || Scroll.tailState(scroller, true).samples.length <= samples)
        errors[0] = "a Begin over the table answered " + began + " and left " + Scroll.tailState(scroller, true).samples.length + " samples (had " + samples + ")"
    var before = scroller.contentX
    var first = route.route(stroke(Qt.ScrollUpdate, -TOUCH_PX, 3))
    if (!first || route.held !== scroller || scroller.contentX <= before)
        errors[1] = "the first sideways update answered " + first + ", held " + (route.held === scroller) + ", contentX " + before + " to " + scroller.contentX
    var later = route.route(stroke(Qt.ScrollUpdate, 0, -TOUCH_PX))
    if (errors[1] === "" && (!later || route.held !== scroller))
        errors[1] = "a vertical update inside a sideways stroke answered " + later + ", held " + (route.held === scroller)
    var ended = route.route(stroke(Qt.ScrollEnd, 0, 0))
    if (!ended || route.held !== null)
        errors[3] = "End of a sideways stroke answered " + ended + " and held " + (route.held !== null)
    Scroll.stopTail(scroller)
    scroller.contentX = 0
    route.route(stroke(Qt.ScrollBegin, 0, 0))
    var down = route.route(stroke(Qt.ScrollUpdate, 2, -TOUCH_PX))
    var across = route.route(stroke(Qt.ScrollUpdate, -2 * TOUCH_PX, 1))
    if (down || across || scroller.contentX !== 0 || route.held !== null || !route.documentStroke)
        errors[2] = "a vertical stroke answered " + down + " then " + across + ", contentX " + scroller.contentX + ", held " + (route.held !== null) + ", documentStroke " + route.documentStroke
    var over = route.route(stroke(Qt.ScrollEnd, 0, 0))
    if (over || route.documentStroke)
        errors[3] += (errors[3] === "" ? "" : "; ") + (over ? "End of a document stroke answered true" : "documentStroke stayed set after its End")
    return errors
}
