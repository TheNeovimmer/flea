// Geometry assertions for the Markdown Quick Look bar against RenderedPreviews, read off MarkdownPane.barGeometry().

// ql_bar: the mark, the name, the muted count right after it, then close. The Rendered|Source segment is gone (GM 2026-10-03).
function barError(g, tokens) {
    if (!g)
        return "the pane exposes no bar geometry";
    if (g.segment !== undefined)
        return "the bar still exposes a segment";
    if (g.markName !== "markdown")
        return "the bar mark is " + g.markName + ", want markdown";
    if (g.mark.width !== tokens.chromeMark || g.mark.x !== tokens.padX)
        return "the mark is " + g.mark.width + " px at " + g.mark.x + ", want " + tokens.chromeMark + " at " + tokens.padX;
    if (g.height !== tokens.chromeHeight)
        return "the bar is " + g.height + " px tall, want " + tokens.chromeHeight;
    if (!g.ready)
        return "the count never became ready";
    if (!(g.mark.x < g.name.x && g.name.x < g.lines.x && g.lines.x < g.close.x))
        return "order by x is mark " + g.mark.x + " name " + g.name.x + " count " + g.lines.x + " close " + g.close.x;
    if (g.name.x - (g.mark.x + g.mark.width) !== tokens.gap)
        return "the name starts " + (g.name.x - (g.mark.x + g.mark.width)) + " px after the mark, want " + tokens.gap;
    if (g.lines.x - g.nameEnd !== tokens.gap)
        return "the count starts " + (g.lines.x - g.nameEnd) + " px after the name's text, want " + tokens.gap;
    return pressError(g.bar, g.close);
}

// Every press target inside the bar belongs to the close button: an item owning a TapHandler or MouseArea is a control.
function pressError(bar, close) {
    var stack = [bar], strays = [];
    while (stack.length) {
        var item = stack.pop();
        var owned = item.data || [];
        for (var i = 0; i < owned.length; i++) {
            if (owned[i].acceptedButtons !== undefined && !isWithin(item, close))
                strays.push(String(item));
            if (owned[i].data !== undefined)
                stack.push(owned[i]);
        }
    }
    return strays.length ? "the bar holds a press target besides close: " + strays.join(", ") : "";
}

function isWithin(item, ancestor) {
    for (var node = item; node; node = node.parent)
        if (node === ancestor)
            return true;
    return false;
}

// A name too long for the bar takes the room up to the count, and the count sits one gap before close.
function nameRoomError(g, tokens) {
    if (!g)
        return "the long-name pane exposes no bar geometry";
    if (!(g.name.width < g.name.implicitWidth))
        return "the name did not elide, so the room is not tested (" + g.name.width + "/" + g.name.implicitWidth + ")";
    var rightGap = g.close.x - (g.lines.x + g.lines.implicitWidth);
    if (rightGap !== tokens.gap)
        return "the count ends " + rightGap + " px before close, want " + tokens.gap + " (name " + g.name.x + "+" + g.name.width
            + " count " + g.lines.x + "+" + g.lines.implicitWidth + " close " + g.close.x + " bar " + g.bar.width + ")";
    return "";
}
