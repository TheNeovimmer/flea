// Geometry assertions for the rendered Markdown pane against RenderedPreviews, read off the live tree.

// md_rendered at body 14: padding 16 20, headings 20 and 15, a 1.7 line box. The mapping may not drift off them.
var BOARD_BODY = 14;
var BOARD_INSET_X = 20;
var BOARD_INSET_Y = 16;
var BOARD_H1 = 20;
var BOARD_H2 = 15;

function textOf(item) {
    for (var i = 0; i < item.children.length; i++) {
        var kid = item.children[i];
        if (kid.visible && kid.font !== undefined && kid.text !== undefined && kid.box !== undefined)
            return kid;
    }
    return null;
}

// A list block's first marker: block, list column, row, then the row's first text.
function markerOf(item) {
    for (var i = 0; i < item.children.length; i++) {
        var column = item.children[i];
        if (!column.visible)
            continue;
        for (var r = 0; r < column.children.length; r++) {
            var row = column.children[r];
            if (row.children.length > 1 && row.children[0].text !== undefined && row.children[0].box !== undefined)
                return row.children[0];
        }
    }
    return null;
}

// Compare first-line baselines in pane coordinates with row positions and padding; answer "" when they hold, otherwise the measured difference.
function listBaselineError(item, pane, count, body, grab, inkAt, reference) {
    if (!item)
        return "no list block was instantiated";
    var seen = 0;
    var error = "";
    for (var i = 0; i < item.children.length; i++) {
        var column = item.children[i];
        if (!column.visible)
            continue;
        for (var r = 0; r < column.children.length; r++) {
            var row = column.children[r];
            if (row.children.length < 2 || row.children[0].box === undefined)
                continue;
            var marker = row.children[0];
            var text = row.children[1];
            seen++;
            if (marker.font.pixelSize !== body || text.font.pixelSize !== body)
                error = "row " + seen + " did not draw at body " + body;
            if (marker.height !== text.box)
                error = "row " + seen + " marker height " + marker.height + " differs from first-line box " + text.box;
            var markY = marker.mapToItem(pane, 0, marker.baselineOffset).y;
            var textY = text.mapToItem(pane, 0, text.baselineOffset).y;
            if (Math.abs(markY - textY) > 0.5)
                error = "row " + seen + " marker baseline " + markY + " differs from item " + textY
                    + " by " + (markY - textY) + " px";
            var ref = reference(marker.text, text.text);
            var markBottom = inkBottom(marker, grab, inkAt);
            var textBottom = inkBottom(text, grab, inkAt);
            var refMarkBottom = ref ? inkBottom(ref.item, grab, inkAt, 0, ref.split) : null;
            var refTextBottom = ref ? inkBottom(ref.item, grab, inkAt, ref.split, ref.item.width) : null;
            if (markBottom === null || textBottom === null || refMarkBottom === null || refTextBottom === null)
                error = "row " + seen + " lost its first-line ink";
            else {
                var diff = (markBottom - textBottom) - (refMarkBottom - refTextBottom);
                if (Math.abs(diff) > 0.5)
                    error = "row " + seen + " painted baselines differ by " + diff + " px";
            }
        }
    }
    return seen !== count ? "read " + seen + " list rows, want " + count : error;
}

// A single reference line gives raised bullets and descenders their rendered offsets from one shared baseline.
function inkBottom(text, grab, inkAt, from, to) {
    var at = text.mapToItem(grab, 0, 0);
    var bottom = null;
    for (var y = Math.floor(at.y); y < Math.ceil(at.y + text.box); y++)
        for (var x = Math.floor(at.x + (from || 0)); x < Math.ceil(at.x + (to === undefined ? Math.min(text.width, text.contentWidth) : to)); x++)
            if (inkAt(x, y))
                bottom = y;
    return bottom;
}

function quoteBoxError(item, pane) {
    if (item)
        for (var i = 0; i < item.children.length; i++) {
            var row = item.children[i];
            var text = row.visible ? textOf(row) : null;
            if (!text)
                continue;
            for (var j = 0; j < row.children.length; j++) {
                var bar = row.children[j];
                if (bar.color === undefined || bar.width !== 2)
                    continue;
                var diff = bar.mapToItem(pane, 0, 0).y - text.mapToItem(pane, 0, 0).y;
                return Math.abs(diff) <= 0.5 && Math.abs(bar.height - text.height) <= 0.5 ? ""
                    : "bar starts " + diff + " px from the text box and spans " + bar.height + "/" + text.height;
            }
        }
    return "no quote text and bar arrived";
}

function tableBaselineError(item, pane, rows, columns) {
    var seen = 0;
    var error = "";
    function visit(parent) {
        var cells = [];
        for (var i = 0; i < parent.children.length; i++) {
            var kid = parent.children[i];
            if (!kid.visible)
                continue;
            if (kid.box !== undefined)
                cells.push(kid);
            else
                visit(kid);
        }
        if (cells.length === 0)
            return;
        seen++;
        if (cells.length !== columns)
            error = "row " + seen + " has " + cells.length + " cells, want " + columns;
        var baseline = cells[0].mapToItem(pane, 0, cells[0].baselineOffset).y;
        for (var c = 1; c < cells.length; c++)
            if (Math.abs(cells[c].mapToItem(pane, 0, cells[c].baselineOffset).y - baseline) > 0.5
                    || cells[c].topPadding !== cells[0].topPadding || cells[c].lineHeight !== cells[0].lineHeight)
                error = "row " + seen + " cell " + c + " left its first-line baseline or box";
    }
    if (item)
        visit(item);
    return seen !== rows ? "read " + seen + " table rows, want " + rows : error;
}

function remoteLineError(item, pane) {
    if (item)
        for (var i = 0; i < item.children.length; i++) {
            var box = item.children[i];
            if (!box.visible)
                continue;
            for (var j = 0; j < box.children.length; j++) {
                var row = box.children[j];
                if (row.children.length !== 2 || row.children[0].name === undefined || row.children[1].text === undefined)
                    continue;
                var mark = row.children[0];
                var text = row.children[1];
                var diff = mark.mapToItem(pane, 0, mark.height / 2).y - text.mapToItem(pane, 0, text.height / 2).y;
                return Math.abs(diff) <= 0.5 ? "" : "placeholder mark and text centres differ by " + diff + " px";
            }
        }
    return "no remote placeholder line arrived";
}

function fallbackOf(figure) {
    for (var i = 0; i < figure.children.length; i++) {
        var kid = figure.children[i];
        if (kid.color !== undefined && kid.children.length === 1 && kid.children[0].text !== undefined)
            return kid;
    }
    return null;
}

function fenceOf(item) {
    for (var i = 0; i < item.children.length; i++)
        if (item.children[i].objectName === "fenceBox")
            return item.children[i];
    return null;
}

// Every block starts the inset in from the frame and ends the inset short of the other side.
function insetError(rects, frameW, insetX, insetY, body) {
    if (!(insetX > 0 && insetY > 0))
        return "the pane declares no inset (x " + insetX + ", y " + insetY + ")";
    for (var i = 0; i < rects.length; i++) {
        var left = rects[i].x;
        var right = frameW - rects[i].x - rects[i].w;
        if (left !== insetX || right !== insetX)
            return "block " + i + " sits " + left + " px from the left and " + right + " px from the right, want " + insetX;
    }
    if (rects[0].y !== insetY)
        return "the first block starts " + rects[0].y + " px down, want " + insetY;
    if (body === BOARD_BODY && (insetX !== BOARD_INSET_X || insetY !== BOARD_INSET_Y))
        return "at body 14 the inset is " + insetY + " " + insetX + ", the board draws " + BOARD_INSET_Y + " " + BOARD_INSET_X;
    return "";
}

// Every drawn gap equals Theme.spacing.rowPaddingY independently of the renderer's blockGap.
function rhythmError(rects, gap) {
    if (!(gap > 0))
        return "the pane declares no block gap";
    for (var i = 1; i < rects.length; i++) {
        var seen = rects[i].y - rects[i - 1].y - rects[i - 1].h;
        if (seen !== gap)
            return "block " + i + " sits " + seen + " px below block " + (i - 1) + ", want " + gap;
    }
    return "";
}

// h1 and h2 are bold foreground at the board's sizes, and body text stays body.
function headingError(h1, h2, para, body, foreground) {
    if (!h1 || !h2 || !para)
        return "the document drew no h1 (" + !!h1 + "), h2 (" + !!h2 + ") or paragraph (" + !!para + ")";
    var want1 = Math.round(body * BOARD_H1 / BOARD_BODY);
    var want2 = Math.round(body * BOARD_H2 / BOARD_BODY);
    if (h1.font.pixelSize !== want1 || h2.font.pixelSize !== want2 || para.font.pixelSize !== body)
        return "sizes h1 " + h1.font.pixelSize + " h2 " + h2.font.pixelSize + " body " + para.font.pixelSize
            + ", want " + want1 + " " + want2 + " " + body;
    if (!h1.font.bold || !h2.font.bold || para.font.bold)
        return "bold h1 " + h1.font.bold + " h2 " + h2.font.bold + " body " + para.font.bold + ", want true true false";
    if (String(h1.color) !== foreground || String(h2.color) !== foreground)
        return "heading ink " + h1.color + " " + h2.color + ", want " + foreground;
    return "";
}

// The RenderedPreviews board sets Markdown text on a 1.7 line box; the renderer never supplies its own ratio here.
var BOARD_LINE_BOX_RATIO = 1.7;

// Every line uses the board's box at its font size and each block spans whole boxes.
function lineBoxError(items) {
    if (items.length === 0)
        return "no run or heading drew its text on a line box";
    for (var i = 0; i < items.length; i++) {
        var t = items[i].text;
        var h = items[i].h;
        var expected = Math.round(BOARD_LINE_BOX_RATIO * t.font.pixelSize);
        if (t.box !== expected)
            return items[i].name + " has a " + t.box + " px box, want " + expected + " px at font " + t.font.pixelSize;
        if (!(t.box > 0) || t.lineHeight !== t.box || h < t.box || h % t.box !== 0)
            return items[i].name + " is " + h + " px tall on a " + t.lineHeight + " px line, want a whole number of " + t.box + " px boxes";
    }
    return "";
}

// The code surface differs from the page it sits on, or the fence disappears into it.
function surfaceError(fence, expected, page) {
    if (!fence)
        return "the pane drew no fence";
    if (String(fence.color) !== expected)
        return "the fence is " + fence.color + ", want " + expected;
    if (String(fence.color) === page)
        return "the fence " + fence.color + " is the page colour";
    return "";
}

// The fence pads 8 12 on the board; text starts the padding in from the surface.
function fencePadError(fence, padX, padY) {
    if (!fence)
        return "the pane drew no fence";
    var text = null;
    for (var i = 0; i < fence.children.length; i++)
        if (fence.children[i].text !== undefined)
            text = fence.children[i];
    if (!text)
        return "the fence holds no text";
    if (text.x !== padX || text.y !== padY || fence.width - text.x - text.width !== padX || fence.height - text.y - text.height !== padY)
        return "fence text sits at " + text.x + "," + text.y + " with " + (fence.width - text.x - text.width) + ","
            + (fence.height - text.y - text.height) + " left, want " + padX + "," + padY;
    return "";
}

// ql_bar: the mark, the name, the muted count right after it, then the segments and close.
function barError(g, tokens) {
    if (!g)
        return "the pane exposes no bar geometry";
    if (g.markName !== "markdown")
        return "the bar mark is " + g.markName + ", want markdown";
    if (g.mark.width !== tokens.chromeMark || g.mark.x !== tokens.padX)
        return "the mark is " + g.mark.width + " px at " + g.mark.x + ", want " + tokens.chromeMark + " at " + tokens.padX;
    if (g.height !== tokens.chromeHeight)
        return "the bar is " + g.height + " px tall, want " + tokens.chromeHeight;
    if (!g.ready)
        return "the count never became ready";
    if (!(g.mark.x < g.name.x && g.name.x < g.lines.x && g.lines.x < g.segment.x && g.segment.x < g.close.x))
        return "order by x is mark " + g.mark.x + " name " + g.name.x + " count " + g.lines.x
            + " segments " + g.segment.x + " close " + g.close.x;
    if (g.name.x - (g.mark.x + g.mark.width) !== tokens.gap)
        return "the name starts " + (g.name.x - (g.mark.x + g.mark.width)) + " px after the mark, want " + tokens.gap;
    if (g.lines.x - g.nameEnd !== tokens.gap)
        return "the count starts " + (g.lines.x - g.nameEnd) + " px after the name's text, want " + tokens.gap;
    return "";
}
