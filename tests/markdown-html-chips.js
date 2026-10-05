// Pixel facts and verdicts for the code chip's padding in tests/markdown-html.qml: where each chip's background starts and ends against its glyph ink.

// A pixel within this summed distance of the chip's colour counts as that colour, and past INK_DELTA from it is glyph ink.
var COLOUR_TOLERANCE = 3;
var INK_DELTA = 48;
// A chip is a chrome run at least this wide on its top row; the board pads it 4 px a side at body 14, and the two sides may differ by one.
var MIN_CHIP_RUN = 12;
var CHIP_PAD_PX = 4;
var CHIP_PAD_SLACK = 1;
var DOC = "37-chips.md";

function isChrome(px, w, rgb, x, y) {
    var o = (y * w + x) * 4;
    return Math.abs(px[o] - rgb[0]) + Math.abs(px[o + 1] - rgb[1]) + Math.abs(px[o + 2] - rgb[2]) <= COLOUR_TOLERANCE;
}

// Each chip on the rectangle's line as {x0, x1, ink0, ink1}: its chrome run on the first row that holds one, and the first and last column of glyph ink inside it.
function chips(px, w, h, chrome, rect) {
    var out = [], top = -1, y0 = Math.max(0, Math.floor(rect.y)), y1 = Math.min(h, Math.ceil(rect.y + rect.h));
    var x0 = Math.max(0, Math.floor(rect.x)), x1 = Math.min(w, Math.ceil(rect.x + rect.w));
    for (var y = y0; y < y1 && top < 0; y++)
        for (var x = x0; x < x1 && top < 0; x++)
            if (isChrome(px, w, chrome, x, y))
                top = y;
    if (top < 0)
        return out;
    for (var x = x0; x < x1; x++) {
        if (!isChrome(px, w, chrome, x, top))
            continue;
        var run = { x0: x, x1: x, ink0: -1, ink1: -1 };
        while (x + 1 < x1 && isChrome(px, w, chrome, x + 1, top))
            run.x1 = ++x;
        if (run.x1 - run.x0 + 1 < MIN_CHIP_RUN)
            continue;
        for (var cx = run.x0; cx <= run.x1; cx++)
            for (var cy = top; cy < y1 && isChrome(px, w, chrome, run.x0, cy); cy++) {
                var o = (cy * w + cx) * 4;
                if (Math.abs(px[o] - chrome[0]) + Math.abs(px[o + 1] - chrome[1]) + Math.abs(px[o + 2] - chrome[2]) > INK_DELTA) {
                    run.ink0 = run.ink0 < 0 ? cx : run.ink0;
                    run.ink1 = cx;
                }
            }
        out.push(run);
    }
    return out;
}

// Verdicts as [label, ok] pairs: a Markdown span, a raw code tag and a key cap on one line, each padded the same on both sides.
function verdict(all) {
    var out = [];
    function check(label, ok) { out.push([label, ok === true]); }
    var doc = all[DOC];
    if (doc === undefined || doc.chipRuns === undefined)
        return out;
    var found = doc.chipRuns;
    check("37 the line holds three chips", found.length === 3);
    found.forEach(function (chip, k) {
        var left = chip.ink0 - chip.x0, right = chip.x1 - chip.ink1;
        check("37 chip " + k + " pads its left " + left + " px, 4 within 1", chip.ink0 >= 0 && Math.abs(left - CHIP_PAD_PX) <= CHIP_PAD_SLACK);
        check("37 chip " + k + " pads its right " + right + " px, 4 within 1", chip.ink0 >= 0 && Math.abs(right - CHIP_PAD_PX) <= CHIP_PAD_SLACK);
        check("37 chip " + k + " pads both sides alike", chip.ink0 >= 0 && Math.abs(left - right) <= CHIP_PAD_SLACK);
    });
    return out;
}
