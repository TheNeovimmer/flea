// Shared figure assertions read the live tree and its painted pixels.
function figure(md, index) {
    var block = md.blockItem(index);
    if (!block)
        return null;
    for (var b = 0; b < block.children.length; b++) {
        var box = block.children[b];
        if (box.objectName !== "figureBox")
            continue;
        for (var i = 0; i < box.children.length; i++)
            if (box.children[i].objectName === "figureItem")
                return box.children[i];
    }
    return null;
}

function bodyFont(md) {
    var block = md.blockItem(5);
    if (block)
        for (var i = 0; i < block.children.length; i++)
            if (block.children[i].visible && block.children[i].font !== undefined)
                return block.children[i].font;
    return null;
}

function labelError(svg, font, foreground) {
    var labels = svg.match(/<(?:text|tspan)(?:\s[^<>]*?)?>/g) || [];
    if (labels.length === 0)
        return "no Mermaid labels";
    var escaped = font.family.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
    for (var i = 0; i < labels.length; i++) {
        var label = labels[i];
        if (label.indexOf('font-size="' + font.pixelSize + '"') < 0)
            return "label size differs from body " + font.pixelSize + "px: " + label;
        if (label.indexOf('font-family="' + escaped + '"') < 0)
            return "label family differs from body " + font.family + ": " + label;
        if (label.indexOf('fill="' + foreground + '"') < 0)
            return "label ink differs from foreground: " + label;
    }
    return "";
}

function paletteError(svg, roles) {
    var paints = svg.match(/(?:fill|stroke)="[^"]*"/g) || [];
    for (var i = 0; i < paints.length; i++) {
        var value = paints[i].replace(/^[^"]*"/, "").replace(/"$/, "");
        if (value !== "none" && roles.indexOf(value) < 0)
            return "diagram paint outside theme roles: " + value;
    }
    return "";
}

function surfaceError(item) {
    if (!item.visible)
        return "";
    if (item.border !== undefined && item.color !== undefined
            && item.width > 0 && item.height > 0) {
        if (item.border.width > 0 || item.color.a > 0)
            return "visible rectangle border=" + item.border.width + " alpha=" + item.color.a;
    }
    for (var i = 0; i < item.children.length; i++) {
        var error = surfaceError(item.children[i]);
        if (error !== "")
            return error;
    }
    return "";
}

function paddingCount(cacheEnd, measuredEnd, paragraphHeight, spacing) {
    if (!(paragraphHeight > 0) || !(spacing >= 0))
        throw new Error("the fixture has no measured paragraph extent");
    return Math.max(2, Math.ceil((cacheEnd - measuredEnd) / (paragraphHeight + spacing)) + 2);
}

function farTop(md, count, paragraphHeight) {
    var last = md.blockItem(5);
    if (!last)
        return -1;
    return last.y + last.height + count * (paragraphHeight + md.bodyItem.spacing) + md.bodyItem.spacing;
}

function inkBounds(pixels, width, rect, ground, chrome) {
    var top = -1;
    var bottom = -1;
    for (var y = rect.y; y < rect.y + rect.h; y++) {
        for (var x = rect.x; x < rect.x + rect.w; x++) {
            var at = (y * width + x) * 4;
            var r = pixels[at], g = pixels[at + 1], b = pixels[at + 2];
            if ((r === ground[0] && g === ground[1] && b === ground[2])
                    || (r === chrome[0] && g === chrome[1] && b === chrome[2])
                    || (r === 0 && g === 0 && b === 0))
                continue;
            if (top < 0)
                top = y;
            bottom = y;
            break;
        }
    }
    return { top: top, bottom: bottom, height: top < 0 ? 0 : bottom - top + 1 };
}

function mathError(rows, bodyPx) {
    var minimum = Math.ceil(bodyPx * 1.04);
    var maximum = Math.ceil(bodyPx * 1.25);
    return rows >= minimum && rows <= maximum ? ""
        : "x^2 paints " + rows + " rows at body " + bodyPx + "px, want " + minimum + ".." + maximum;
}

function spacingError(previous, figure, next, ink, paragraphGap) {
    var above = figure.y - previous.y - previous.h + ink.top - figure.y;
    var below = next.y - figure.y - figure.h + figure.y + figure.h - 1 - ink.bottom;
    return Math.abs(above - paragraphGap) <= 2 && Math.abs(below - paragraphGap) <= 2 ? ""
        : "figure gaps " + above + "/" + below + "px, paragraph gap " + paragraphGap + "px";
}

// Read the drawn SVG image, including its live size after asynchronous decoding.
function imageOf(figure) {
    if (figure)
        for (var i = 0; i < figure.children.length; i++) {
            var image = figure.children[i];
            if (image.visible && image.status !== undefined && image.source !== undefined)
                return image;
        }
    return null;
}

// Figure block bounds include the same vertical inset as the fenced figure fallback.
function drawnBlockRect(md, index, target, inset) {
    var block = md.blockItem(index);
    if (!block)
        return null;
    var image = md.blockList[index].type === "figure" ? imageOf(figure(md, index)) : null;
    var item = image;
    if (!item)
        for (var i = 0; i < block.children.length; i++) {
            var child = block.children[i];
            if (child.visible && (child.objectName === "fenceBox" || child.box !== undefined))
                item = child;
        }
    if (!item)
        return null;
    var at = item.mapToItem(target, 0, 0);
    return { x: at.x, y: at.y - (image ? inset : 0), w: item.width,
        h: item.height + (image ? 2 * inset : 0) };
}

function blockGapError(previous, next, gap) {
    if (!previous || !next)
        return "a drawn block is missing";
    var seen = next.y - previous.y - previous.h;
    return Math.abs(seen - gap) <= 0.5 ? ""
        : "drawn block gap " + seen + "px, want " + gap + "px";
}
