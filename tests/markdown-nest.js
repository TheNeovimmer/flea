// Readers over the live tree for the nesting checks: every element a block built, found by name at any depth.
var BAR_WIDTH = 2; // The board's quote bar, in pixels.
var GEOMETRY_TOLERANCE = 0.5; // Layout positions may differ from the recipe by this many pixels.

// Every descendant of item with this objectName, in tree order.
function all(item, name) {
    var found = [];
    for (var i = 0; i < item.children.length; i++) {
        var kid = item.children[i];
        if (kid.objectName === name)
            found.push(kid);
        found = found.concat(all(kid, name));
    }
    return found;
}

function first(item, name) {
    var found = all(item, name);
    return found.length > 0 ? found[0] : null;
}

function near(a, b) {
    return Math.abs(a - b) <= GEOMETRY_TOLERANCE;
}

// The block's delegate, or null when the list has not built it.
function delegate(md, index) {
    return md.blockItem(index);
}

// Where an element's top left corner lies in another item's frame.
function at(item, frame) {
    return item.mapToItem(frame, 0, 0);
}

// The 2 px bars drawn directly in a quote row, left to right.
function bars(row) {
    var found = [];
    for (var i = 0; i < row.children.length; i++) {
        var c = row.children[i];
        if (c.width === BAR_WIDTH && c.height > 0 && c.color !== undefined && c.visible)
            found.push(c);
    }
    return found.sort(function (a, b) { return a.x - b.x; });
}

// The fence's drawn recipe: surface colour, the text's face and size, and the padding the text sits in.
function recipe(fence) {
    var text = fence.children[0];
    return JSON.stringify([String(fence.color), text.font.family, text.font.pixelSize, text.textFormat, text.anchors.leftMargin, text.anchors.topMargin]);
}

// Every mathsText under a block, settled or not.
function formulas(item) {
    return all(item, "mathsText");
}

// A text item's own markdown, whatever depth it sits at, joined; a table drawn by Qt would leave a <table in it.
function textsOf(item) {
    var out = [];
    function walk(node) {
        if (node.text !== undefined && node.textFormat !== undefined)
            out.push(String(node.text));
        for (var i = 0; i < node.children.length; i++)
            walk(node.children[i]);
    }
    walk(item);
    return out.join("\n");
}
