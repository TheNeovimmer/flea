.import "markdown-html.js" as Base

// Verdicts on the pictures raw HTML draws, for tests/markdown-html.qml: the logo units, the README header and the badge row.

// A pixel of slack for a fractional block edge, and the rows a logo holds.
var EDGE_SLACK = 1;
var MIN_PICTURE_ROWS = 20;
// The badge strip's pictures, in pixels: their widths and common height are tests/md-fixtures.py's BADGE_WIDTHS and BADGE_H.
var BADGE_WIDTHS = [70, 110, 90, 130];
var WRAP_BADGE_WIDTH = 120;
var BADGE_HEIGHT = 20;
// The wrapping row holds this many pictures, of which this many fit one line of the pane.
var WRAP_BADGES = 6;
var WRAP_PER_LINE = 4;
// The pictures the size rule is judged on, in pixels: tests/md-fixtures.py's SMALL_SIZE and BIG_SIZE, the width attribute past the small one, and both attributes.
var SMALL_H = 30;
var SMALL_W = 40;
var GROWN_WIDTH = 120;
var BIG_W = 2000;
var BIG_H = 40;
var BOX_WIDTH = 70;
var BOX_HEIGHT = 20;
// Local images inside raw HTML that must draw as a picture in place, and whether their wrapper centres them.
var PICTURE_DOCS = { "21-linked-logo.md": true, "22-table-logo.md": false, "23-open-wrapper.md": true,
    "24-empty-closer.md": true, "25-wide-logo.md": false };

// Verdicts as [label, ok] pairs over every document's facts, keyed by name.
function verdict(all) {
    var out = [];
    function check(label, ok) { out.push([label, ok === true]); }
    pictureChecks(all, check);
    badgeChecks(all, check);
    sizeChecks(all, check);
    headerChecks(all["26-readme-header.md"], all["27-break.md"], check);
    gapChecks(all, check);
    return out;
}

// A picture followed by a picture block sits at the list spacing, a picture followed by text keeps the block gap.
function gapChecks(all, check) {
    var pic = all["36-pic-pic.md"];
    if (pic !== undefined) {
        var first = Base.blockOf(pic, "image");
        var boxes = pic.blocks;
        var secondImage = -1;
        for (var k = 0; k < pic.geo.blocks.length; k++)
            if (pic.geo.blocks[k].type === "image" && k !== first)
                secondImage = k;
        var firstInk = first < 0 ? null : boxes[first].box;
        var secondInk = secondImage < 0 ? null : boxes[secondImage].box;
        check("36 two pictures sit one block gap apart", firstInk !== null && secondInk !== null && Math.abs(secondInk.y0 - firstInk.y1 - 1 - pic.geo.blockGap) <= EDGE_SLACK);
    }
    var single = all["32-natural-single.md"];
    if (single !== undefined) {
        var at = Base.blockOf(single, "image");
        var runAt = -1;
        for (var r = 0; r < single.geo.blocks.length; r++)
            if (single.geo.blocks[r].type === "run")
                runAt = r;
        var picInk = at < 0 ? null : single.blocks[at].box;
        var runInk = runAt < 0 ? null : single.blocks[runAt].box;
        check("32 a picture followed by text keeps two block gaps", picInk !== null && runInk !== null && runInk.y0 - picInk.y1 - 1 >= 2 * single.geo.blockGap - EDGE_SLACK);
    }
}

// A local image inside raw HTML draws as a picture in place, with no Markdown image text and no stray closing tag drawn.
function pictureChecks(all, check) {
    Object.keys(PICTURE_DOCS).forEach(function (name) {
        var f = all[name];
        if (f === undefined)
            return;
        var rows = 0, literal = false, closer = false, img = Base.blockOf(f, "image");
        for (var k = 0; k < f.blocks.length; k++) {
            rows += f.blocks[k].picture;
            var plain = String(f.geo.blocks[k].plain);
            literal = literal || plain.indexOf("![") >= 0 || plain.indexOf("file:///") >= 0;
            closer = closer || plain.indexOf("</") >= 0;
        }
        check(name + " draws its picture", rows >= MIN_PICTURE_ROWS);
        check(name + " draws no literal image text", !literal);
        check(name + " draws no stray closing tag", !closer);
        check(name + " holds its picture in an image block", img >= 0);
        var box = img < 0 ? null : f.blocks[img].box;
        if (PICTURE_DOCS[name])
            check(name + " centres its picture", box !== null && Math.abs((box.x0 + box.x1 + 1) / 2 - f.geo.w / 2) <= Base.CENTRE_SLACK);
    });
    var wide = all["25-wide-logo.md"];
    var wideAt = wide === undefined ? -1 : Base.blockOf(wide, "image");
    // Unclamped, the picture sits half its 5000 px width off the left edge and none of it shows.
    var wideBox = wideAt < 0 ? null : wide.blocks[wideAt].box;
    check("25 a width past the pane is clamped to the pane, the picture drawn inside it",
        wideBox !== null && wideBox.x0 >= wide.geo.blocks[wideAt].x && wideBox.x1 < wide.geo.blocks[wideAt].x + wide.geo.blocks[wideAt].w);
    var open = all["23-open-wrapper.md"];
    var name = open === undefined ? -1 : Base.blockOf(open, "run");
    var line = name < 0 ? null : open.blocks[name].first;
    check("23 what the wrapper held under the image is centred under it",
        line !== null && Math.abs((line.x0 + line.x1 + 1) / 2 - open.geo.w / 2) <= Base.CENTRE_SLACK);
}

// The README header: each top-level block of an HTML run draws as its own block, and a break's next line starts at the text column.
function headerChecks(f, broken, check) {
    if (f === undefined)
        return;
    function holding(needle) {
        for (var i = 0; i < f.geo.blocks.length; i++)
            if (String(f.geo.blocks[i].text).indexOf(needle) >= 0)
                return i;
        return -1;
    }
    var h = holding("Flea"), p = holding("A file manager"), after = holding("A line after a break.");
    check("26 the HTML heading is a heading block", h >= 0 && f.geo.blocks[h].type === "heading");
    check("26 the heading and the paragraph are blocks of their own", h >= 0 && p >= 0 && h !== p);
    check("26 the paragraph sits below the heading across a gap",
        h >= 0 && p >= 0 && f.geo.blocks[p].y > f.geo.blocks[h].y + f.geo.blocks[h].h);
    [h, p].forEach(function (k) {
        var line = k < 0 ? null : f.blocks[k].first;
        check("26 block " + k + " is centred", line !== null && Math.abs((line.x0 + line.x1 + 1) / 2 - f.geo.w / 2) <= Base.CENTRE_SLACK);
    });
    // The pane's block gap sits under the logo as well as in the list, so the heading never touches it.
    var logo = Base.blockOf(f, "image");
    var logoInk = logo < 0 ? null : f.blocks[logo].box;
    var headInk = h < 0 ? null : f.blocks[h].box;
    check("26 the heading starts below the logo across two block gaps",
        logoInk !== null && headInk !== null && headInk.y0 - logoInk.y1 - 1 >= 2 * f.geo.blockGap - EDGE_SLACK);
    var second = after < 0 ? null : f.blocks[after].second;
    check("26 the line after a break starts at the text column",
        second !== null && second.x0 - f.geo.blocks[after].x <= Base.LEADING_SLACK);
    // The same break alone, so the line it checks is the second one whatever the blocks above it hold.
    var line = broken === undefined || broken.blocks.length === 0 ? null : broken.blocks[0].second;
    check("27 the line after a break starts at the text column, not after a space",
        line !== null && line.x0 - broken.geo.blocks[0].x <= Base.LEADING_SLACK);
}

// A run of images in one HTML block draws as one row that wraps at the pane width, each line centred, each picture with its own link.
function badgeChecks(all, check) {
    function sizes(line) { return line.clusters.map(function (c) { return c.x1 - c.x0 + 1; }); }
    function sameSizes(got, want) {
        return got.length === want.length && got.every(function (w, i) { return Math.abs(w - want[i]) <= Base.SIZE_SLACK; });
    }
    function gapsOk(line, gap) {
        return line.clusters.every(function (c, i) { return i === 0 || Math.abs(c.x0 - line.clusters[i - 1].x1 - 1 - gap) <= EDGE_SLACK; });
    }
    function centred(line, width) {
        var last = line.clusters[line.clusters.length - 1];
        return line.clusters.length > 0 && Math.abs((line.clusters[0].x0 + last.x1 + 1) / 2 - width / 2) <= Base.CENTRE_SLACK;
    }
    var none = { clusters: [], y0: 0, y1: 0 };
    var row = all["28-badge-row.md"];
    if (row !== undefined) {
        var at = Base.blockOf(row, "images");
        check("28 the four badges are one images block", at >= 0);
        var lines = at < 0 ? [] : row.blocks[at].lines;
        check("28 the badges sit on one line", lines.length === 1);
        var one = lines.length > 0 ? lines[0] : none;
        check("28 the line holds four pictures, each as wide as it is", sameSizes(sizes(one), BADGE_WIDTHS));
        check("28 the pictures are one block gap apart", one.clusters.length > 1 && gapsOk(one, row.geo.blockGap));
        check("28 the line is as tall as one badge", Math.abs(one.y1 - one.y0 + 1 - BADGE_HEIGHT) <= Base.SIZE_SLACK);
        check("28 the line is centred in the pane", centred(one, row.geo.w));
        var links = at < 0 ? [] : row.geo.blocks[at].row;
        check("28 each picture answers for its own link",
            links.map(function (l) { return l.link; }).join(",") === ["a", "b", "c", "d"].map(function (n) { return "https://example.com/" + n; }).join(",")
            && links.every(function (l) { return l.tap && l.hover; }));
    }
    var wrap = all["29-badge-wrap.md"];
    if (wrap !== undefined) {
        var wat = Base.blockOf(wrap, "images");
        var wlines = wat < 0 ? [] : wrap.blocks[wat].lines;
        var block = wat < 0 ? { x: 0, w: 0 } : wrap.geo.blocks[wat];
        check("29 a row wider than the pane wraps onto a second line", wlines.length === 2);
        var first = wlines.length > 0 ? wlines[0] : none, second = wlines.length > 1 ? wlines[1] : none;
        var per = function (n) { return new Array(n).fill(WRAP_BADGE_WIDTH); };
        check("29 the first line holds as many pictures as fit the pane", sameSizes(sizes(first), per(WRAP_PER_LINE)));
        check("29 the second line holds the rest", sameSizes(sizes(second), per(WRAP_BADGES - WRAP_PER_LINE)));
        check("29 the lines are one block gap apart", second.y0 - first.y1 - 1 >= wrap.geo.blockGap - EDGE_SLACK && second.y0 - first.y1 - 1 <= wrap.geo.blockGap + EDGE_SLACK);
        check("29 each line is centred in the pane", centred(first, wrap.geo.w) && centred(second, wrap.geo.w));
        check("29 no picture leaves the content width",
            first.clusters.length > 0 && first.clusters[0].x0 >= block.x && first.clusters[first.clusters.length - 1].x1 < block.x + block.w);
        check("29 all six pictures keep a link of their own", wat >= 0 && wrap.geo.blocks[wat].row.length === WRAP_BADGES
            && wrap.geo.blocks[wat].row.every(function (l, i) { return l.link === "https://example.com/w" + (i + 1) && l.tap; }));
    }
}

// One size rule for a lone picture and for a row: an attribute is honoured past the natural size, none draws it whole, both draw their box.
function sizeChecks(all, check) {
    function inkSize(f, at) {
        var box = f === undefined || at < 0 ? null : f.blocks[at].box;
        return box === null ? [0, 0] : [box.x1 - box.x0 + 1, box.y1 - box.y0 + 1];
    }
    function near(got, want) { return Math.abs(got - want) <= Base.SIZE_SLACK; }
    function lineOf(f, line) {
        var at = f === undefined ? -1 : Base.blockOf(f, "images");
        return at < 0 || f.blocks[at].lines.length <= line ? { clusters: [], y0: 0, y1: -1 } : f.blocks[at].lines[line];
    }
    function widths(line) { return line.clusters.map(function (c) { return c.x1 - c.x0 + 1; }); }
    function high(line) { return line.y1 - line.y0 + 1; }
    function wholeWidth(f, at) { return f === undefined || at < 0 ? 0 : f.geo.blocks[at].w; }
    var grownHeight = GROWN_WIDTH * SMALL_H / SMALL_W;
    var single = all["30-grow-single.md"];
    var s = inkSize(single, single === undefined ? -1 : Base.blockOf(single, "image"));
    check("30 a width past the natural size is honoured by a lone picture", near(s[0], GROWN_WIDTH) && near(s[1], grownHeight));
    var grown = lineOf(all["31-grow-row.md"], 0);
    check("31 a width past the natural size is honoured in a row, both pictures on a line", widths(grown).length === 2
        && widths(grown).every(function (w) { return near(w, GROWN_WIDTH); }) && near(high(grown), grownHeight));
    var natural = all["32-natural-single.md"];
    var nAt = natural === undefined ? -1 : Base.blockOf(natural, "image");
    var n = inkSize(natural, nAt);
    check("32 a picture with no attribute is capped at the pane width by a lone picture, its ratio kept",
        near(n[0], wholeWidth(natural, nAt)) && near(n[1], wholeWidth(natural, nAt) * BIG_H / BIG_W));
    // A box taller than its picture leaves a gap of its own inside the block, so the block holds the picture and the pane's block gap, no more.
    check("32 the block is as tall as the picture it holds", nAt >= 0 && natural.geo.blocks[nAt].h - n[1] <= natural.geo.blockGap + Base.SIZE_SLACK);
    var rowFacts = all["33-natural-row.md"];
    var rowAt = rowFacts === undefined ? -1 : Base.blockOf(rowFacts, "images");
    var top = lineOf(rowFacts, 0), under = lineOf(rowFacts, 1);
    check("33 a picture with no attribute is capped at the pane width in a row, the next picture below it",
        widths(top).length === 1 && near(widths(top)[0], wholeWidth(rowFacts, rowAt)) && near(high(top), wholeWidth(rowFacts, rowAt) * BIG_H / BIG_W)
        && widths(under).length === 1 && near(widths(under)[0], BADGE_WIDTHS[0]));
    var box = all["34-box-single.md"];
    var b = inkSize(box, box === undefined ? -1 : Base.blockOf(box, "image"));
    check("34 both attributes draw their box on a lone picture", near(b[0], BOX_WIDTH) && near(b[1], BOX_HEIGHT));
    var pair = lineOf(all["35-box-row.md"], 0);
    check("35 both attributes draw their box in a row", widths(pair).length === 2 && widths(pair).every(function (w) { return near(w, BOX_WIDTH); }) && near(high(pair), BOX_HEIGHT));
}
