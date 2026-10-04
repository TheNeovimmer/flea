// Geometry and ink readers for the nesting and inline-maths checks, over the live tree and the painted pixels.
var RGBA_CHANNELS = 4;
var BAR_WIDTH = 2; // The board's quote bar, in pixels.
var INK_MIN_DIFF = 90; // A pixel this far from the ground in any channel is ink.
var GEOMETRY_TOLERANCE = 0.5; // Layout positions may differ from the recipe by this many pixels.
var RASTER_TOLERANCE = 1; // Painted rows may differ from the recipe by this many pixels.
var HEIGHT_TOLERANCE = 1.5; // A formula's x-height may differ from the prose's by this many pixels.
var DESCENT_MIN_PX = 2; // A descender reaches at least this far under the baseline.
var DESCENT_MAX_EM = 0.4; // And at most this share of the body.

function child(item, name) {
    for (var i = 0; i < item.children.length; i++)
        if (item.children[i].objectName === name)
            return item.children[i];
    return null;
}

// The drawn element of a block (its delegate's one named child), or null when the block has no delegate.
function drawn(md, index, name) {
    var delegate = md.blockItem(index);
    return delegate === null ? null : child(delegate, name);
}

// The drawn rectangle of a block's element in the list's content, so two blocks compare edge to edge.
function rectOf(md, item) {
    var at = item.mapToItem(md.bodyItem.contentItem, 0, 0);
    return { x: at.x, y: at.y, w: item.width, h: item.height };
}

// Every 2 px bar of a quote row, left to right.
function bars(row) {
    var found = [];
    for (var i = 0; i < row.children.length; i++) {
        var c = row.children[i];
        if (c.width === BAR_WIDTH && c.height > 0 && c.color !== undefined && c.visible)
            found.push(c);
    }
    return found.sort(function (a, b) { return a.x - b.x; });
}

// The quote's text, the row's one Text child.
function quoteText(row) {
    for (var i = 0; i < row.children.length; i++)
        if (row.children[i].text !== undefined)
            return row.children[i];
    return null;
}

// A list's rows with their marker and text, in entry order.
function rows(column) {
    var found = [];
    for (var i = 0; i < column.children.length; i++)
        if (column.children[i].objectName === "listRow")
            found.push({ row: column.children[i], marker: column.children[i].children[0], text: column.children[i].children[1] });
    return found;
}

function near(a, b, tolerance) {
    return Math.abs(a - b) <= tolerance;
}

// Sample input: a depth-3 quote row answers "" when three bars stand at 0, step and 2 steps and each spans the row.
function quoteBarsError(row, depth, step) {
    var found = bars(row);
    if (found.length !== depth)
        return found.length + " bars for depth " + depth;
    for (var k = 0; k < depth; k++) {
        if (!near(found[k].x, k * step, GEOMETRY_TOLERANCE))
            return "bar " + k + " at x " + found[k].x + ", want " + k * step;
        if (!near(found[k].height, row.height, GEOMETRY_TOLERANCE) || !near(found[k].y, 0, GEOMETRY_TOLERANCE))
            return "bar " + k + " spans y " + found[k].y + " for " + found[k].height + " of a " + row.height + " px block";
    }
    var text = quoteText(row);
    return near(text.x, depth * step, GEOMETRY_TOLERANCE) ? "" : "text at x " + text.x + ", want " + depth * step;
}

// A list entry's text column in its row's own frame.
function textColumn(entry) {
    return entry.row.x + entry.text.x;
}

// Pixels of one rect as ink columns, grouped where a blank column separates them.
function inkGroups(pixels, width, rect, ground) {
    var groups = [];
    var open = null;
    for (var x = rect.x; x < rect.x + rect.w; x++) {
        var top = -1, bottom = -1;
        for (var y = rect.y; y < rect.y + rect.h; y++) {
            var at = (y * width + x) * RGBA_CHANNELS;
            var diff = Math.max(Math.abs(pixels[at] - ground[0]), Math.abs(pixels[at + 1] - ground[1]), Math.abs(pixels[at + 2] - ground[2]));
            if (diff >= INK_MIN_DIFF) {
                if (top < 0)
                    top = y;
                bottom = y;
            }
        }
        if (top < 0) {
            open = null;
            continue;
        }
        if (open === null) {
            open = { x0: x, x1: x, top: top, bottom: bottom };
            groups.push(open);
        } else {
            open.x1 = x;
            open.top = Math.min(open.top, top);
            open.bottom = Math.max(open.bottom, bottom);
        }
    }
    return groups;
}

// "x $x$ x": the formula's x stands on the prose's baseline and is as tall as the prose x.
function levelError(groups, box) {
    if (groups.length !== 3)
        return groups.length + " ink groups in the line, want prose, formula, prose";
    var a = groups[0], f = groups[1], b = groups[2];
    if (!near(f.bottom, a.bottom, RASTER_TOLERANCE) || !near(f.bottom, b.bottom, RASTER_TOLERANCE))
        return "formula bottom row " + f.bottom + " against prose " + a.bottom + " and " + b.bottom;
    var h = f.bottom - f.top + 1, p = a.bottom - a.top + 1;
    if (!near(h, p, HEIGHT_TOLERANCE))
        return "formula is " + h + " px tall, the prose x " + p;
    if (f.top < box.y || f.bottom >= box.y + box.h)
        return "formula rows " + f.top + " to " + f.bottom + " leave the line box " + box.y + " to " + (box.y + box.h);
    return "";
}

// "y $y$ y": the formula's descender reaches under the baseline the first line fixed, by its own depth.
function depthError(groups, baseline, bodyPx) {
    if (groups.length !== 3)
        return groups.length + " ink groups in the line, want prose, formula, prose";
    var below = groups[1].bottom - baseline;
    if (below < DESCENT_MIN_PX || below > DESCENT_MAX_EM * bodyPx)
        return "formula descends " + below + " px under the baseline, want " + DESCENT_MIN_PX + " to " + DESCENT_MAX_EM * bodyPx;
    return "";
}
