// RenderedPreviews' own pixels beyond the inset and the headings tests/markdown-render.js holds, and the probes that read them.
.import "markdown-render.js" as Render

// The margin above every block after the first, and the fence's padding: md_rendered's margin-top 6 and padding 8 12.
var BOARD_BLOCK_GAP = 6;
var BOARD_FENCE_PAD_X = 12;
var BOARD_FENCE_PAD_Y = 8;

// A board pixel at the text size: the board is drawn at body 14, and the document's sizes follow the body.
// Sample input: boardPx(6, 14) answers 6, and boardPx(20, 12) answers 17.
function boardPx(px, body) {
    return Math.round(px * body / Render.BOARD_BODY);
}

// The preview column sets the body one token under Quick Look's and keeps the headings at the board's sizes over it.
function compactHeadingError(h1, h2, para, body, bodySmall) {
    if (!h1 || !h2 || !para)
        return "the column drew no h1 (" + !!h1 + "), h2 (" + !!h2 + ") or paragraph (" + !!para + ")";
    var want1 = boardPx(Render.BOARD_H1, body);
    var want2 = boardPx(Render.BOARD_H2, body);
    if (h1.font.pixelSize !== want1 || h2.font.pixelSize !== want2 || para.font.pixelSize !== bodySmall)
        return "column sizes h1 " + h1.font.pixelSize + " h2 " + h2.font.pixelSize + " body " + para.font.pixelSize
            + ", want " + want1 + " " + want2 + " " + bodySmall;
    return "";
}

// RenderedPreviews' table header cells are bold in the heading ink over body cells in the foreground.
function headerInkError(table, bright, foreground) {
    var bold = 0;
    var plain = 0;
    var error = "";
    function visit(parent) {
        for (var i = 0; i < parent.children.length; i++) {
            var kid = parent.children[i];
            if (!kid.visible)
                continue;
            if (kid.box === undefined) {
                visit(kid);
                continue;
            }
            if (kid.font.bold) {
                bold++;
                if (String(kid.color) !== bright)
                    error = "a header cell inks " + kid.color + ", want the heading ink " + bright;
            } else {
                plain++;
                if (String(kid.color) !== foreground)
                    error = "a body cell inks " + kid.color + ", want the foreground " + foreground;
            }
        }
    }
    if (table)
        visit(table);
    return bold === 0 || plain === 0 ? "the table drew " + bold + " header and " + plain + " body cells" : error;
}

// Sample input: blocks 1 and 2 of a drawn document, an empty heading and quote, answer true only when each delegate is 0 high.
function emptiesTakeNoHeight(preview, indexes) {
    return indexes.every(function (index) {
        var item = preview.blockItem(index)
        return item !== null && item.height === 0
    })
}
