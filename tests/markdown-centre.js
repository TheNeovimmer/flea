// Where each Markdown line sits in its 1.7 box against the CSS-centred baseline, read off the grab's ink rows.
.import "markdown-render.js" as Render

// A baseline may sit this many pixels off the one CSS centring gives.
var CENTRE_TOLERANCE = 1;
// The first glyph's stem lies in this share of the font size from the text's left edge, clear of any descender after it.
var FIRST_GLYPH_SHARE = 0.4;

// Each wrapped line's painted baseline against the CSS-centred one, half the leading above the ascent: want is that baseline in the box, the grab's ink rows give the painted one.
function lineCentreError(text, grab, inkAt, lines, want, name) {
    if (!text)
        return name + " drew no text";
    var at = text.mapToItem(grab, 0, 0);
    var left = Math.floor(at.x);
    var right = Math.ceil(at.x + FIRST_GLYPH_SHARE * text.font.pixelSize);
    for (var k = 0; k < lines; k++) {
        var boxTop = Math.round(at.y) + text.cellPad + k * text.box;
        var bottom = null;
        for (var y = boxTop; y < boxTop + text.box; y++)
            for (var x = left; x < right; x++)
                if (inkAt(x, y))
                    bottom = y;
        if (bottom === null)
            return name + " line " + (k + 1) + " has no ink in its " + text.box + " px box";
        var baseline = bottom + 1 - boxTop;
        if (Math.abs(baseline - want) > CENTRE_TOLERANCE)
            return name + " line " + (k + 1) + " baseline sits " + baseline + " px into its " + text.box + " px box, centred is "
                + want.toFixed(1) + " (" + (baseline - want).toFixed(1) + " px off)";
    }
    return "";
}

// A quote block's text: the first row holding one.
function quoteTextOf(item) {
    for (var i = 0; item && i < item.children.length; i++) {
        var text = item.children[i].visible ? Render.textOf(item.children[i]) : null;
        if (text)
            return text;
    }
    return null;
}

// A table's cells in reading order: every text with a line box under the block.
function cellsOf(item, out) {
    out = out || [];
    for (var i = 0; i < item.children.length; i++) {
        var kid = item.children[i];
        if (!kid.visible)
            continue;
        if (kid.box !== undefined)
            out.push(kid);
        else
            cellsOf(kid, out);
    }
    return out;
}
