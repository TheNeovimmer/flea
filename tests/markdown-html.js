// Pixel facts and verdicts for tests/markdown-html.qml: what each fixture document draws in the rendered pane.

// A pixel is ink when its channels sit this far, summed, from the ground.
var INK_DELTA = 48;
// Ink columns closer than this belong to one glyph cluster.
var CLUSTER_GAP = 3;
// Slack of a centred or sized measure, in pixels.
var CENTRE_SLACK = 3;
var SIZE_SLACK = 2;
// Bold glyphs carry at least this much more ink than the regular ones.
var BOLD_RATIO = 1.12;
// A key cap fills far more than a stray antialiased pixel.
var MIN_CAP_PIXELS = 100;
// A second line starts at the text column, within this many pixels of the block's left edge (a collapsed break leaves no space).
var LEADING_SLACK = 2;
// The mark and the word are two clusters; the mark is narrower than this.
var MARK_MAX_WIDTH = 14;
// A raised glyph's foot sits this far above a baseline one.
var RAISE_PX = 2;
// The harness captures geometry for this many leading blocks, and every verdict below reads exactly those.
var CAPTURED_BLOCKS = 8;
// A pixel within this summed distance of a colour counts as that colour.
var COLOUR_TOLERANCE = 3;
// A picture pixel has its channels this far apart; grey text, even antialiased, does not.
var SATURATION_SPREAD = 40;
// A picture row holds a run of such pixels this long (link text and its underline never do).
var MIN_PICTURE_RUN = 48;
// The documents the verdicts below judge; one missing from the run fails by name.
var REQUIRED = ["07-rawhtml.md", "15-pathological.md", "16-sub-base.md", "16-sub-low.md", "16-sub-high.md",
    "17-plain-title.md", "18-bold-title.md", "19-key.md", "19-nokey.md", "20-summary.md",
    "21-linked-logo.md", "22-table-logo.md", "23-open-wrapper.md", "24-empty-closer.md", "25-wide-logo.md", "26-readme-header.md", "27-break.md",
    "28-badge-row.md", "29-badge-wrap.md"];
// The block types whose delegates draw text or a picture the moment they are built, and so are never empty.
var DRAWN_TYPES = ["heading", "run", "quote", "list", "table", "image", "remote"];

function isInk(px, w, ground, x, y) {
    var o = (y * w + x) * 4;
    return Math.abs(px[o] - ground[0]) + Math.abs(px[o + 1] - ground[1]) + Math.abs(px[o + 2] - ground[2]) > INK_DELTA;
}

// The ink bounding box of a rectangle, null when it holds none.
function inkBox(px, w, h, ground, rect) {
    var x0 = Math.max(0, Math.floor(rect.x)), x1 = Math.min(w, Math.ceil(rect.x + rect.w));
    var y0 = Math.max(0, Math.floor(rect.y)), y1 = Math.min(h, Math.ceil(rect.y + rect.h));
    var box = null, count = 0;
    for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
            if (!isInk(px, w, ground, x, y))
                continue;
            count++;
            if (box === null)
                box = { x0: x, x1: x, y0: y, y1: y };
            box.x0 = Math.min(box.x0, x); box.x1 = Math.max(box.x1, x);
            box.y0 = Math.min(box.y0, y); box.y1 = Math.max(box.y1, y);
        }
    }
    if (box !== null)
        box.count = count;
    return box;
}

// Pixels equal to one colour, within a rounding of the renderer.
function colourCount(px, w, h, rgb, rect) {
    var n = 0;
    for (var y = Math.max(0, Math.floor(rect.y)); y < Math.min(h, Math.ceil(rect.y + rect.h)); y++) {
        for (var x = Math.max(0, Math.floor(rect.x)); x < Math.min(w, Math.ceil(rect.x + rect.w)); x++) {
            var o = (y * w + x) * 4;
            if (Math.abs(px[o] - rgb[0]) + Math.abs(px[o + 1] - rgb[1]) + Math.abs(px[o + 2] - rgb[2]) <= COLOUR_TOLERANCE)
                n++;
        }
    }
    return n;
}

// Rows of the rectangle holding a run of MIN_PICTURE_RUN pixels whose channels spread past SATURATION_SPREAD: a picture's rows.
function pictureRows(px, w, h, rect) {
    var rows = 0;
    for (var y = Math.max(0, Math.floor(rect.y)); y < Math.min(h, Math.ceil(rect.y + rect.h)); y++) {
        var run = 0, best = 0;
        for (var x = Math.max(0, Math.floor(rect.x)); x < Math.min(w, Math.ceil(rect.x + rect.w)); x++) {
            var o = (y * w + x) * 4;
            run = Math.max(px[o], px[o + 1], px[o + 2]) - Math.min(px[o], px[o + 1], px[o + 2]) > SATURATION_SPREAD ? run + 1 : 0;
            best = Math.max(best, run);
        }
        if (best >= MIN_PICTURE_RUN)
            rows++;
    }
    return rows;
}

// Runs of ink columns, each as {x0, x1}, split where a gap of CLUSTER_GAP empty columns opens.
function clusters(px, w, h, ground, rect) {
    var out = [], empty = CLUSTER_GAP;
    for (var x = Math.max(0, Math.floor(rect.x)); x < Math.min(w, Math.ceil(rect.x + rect.w)); x++) {
        var any = false;
        for (var y = Math.max(0, Math.floor(rect.y)); y < Math.min(h, Math.ceil(rect.y + rect.h)) && !any; y++)
            any = isInk(px, w, ground, x, y);
        if (any) {
            if (empty >= CLUSTER_GAP)
                out.push({ x0: x, x1: x });
            out[out.length - 1].x1 = x;
            empty = 0;
        } else {
            empty++;
        }
    }
    return out;
}

// Runs of ink rows, each as {y0, y1}, split wherever a row holds none: one picture line each.
function bands(px, w, h, ground, rect) {
    var out = [], open = false;
    for (var y = Math.max(0, Math.floor(rect.y)); y < Math.min(h, Math.ceil(rect.y + rect.h)); y++) {
        var any = false;
        for (var x = Math.max(0, Math.floor(rect.x)); x < Math.min(w, Math.ceil(rect.x + rect.w)) && !any; x++)
            any = isInk(px, w, ground, x, y);
        if (any) {
            if (!open)
                out.push({ y0: y, y1: y });
            out[out.length - 1].y1 = y;
        }
        open = any;
    }
    return out;
}

// The facts one document's grab holds, read once so the verdict never touches pixels again.
function facts(px, geo) {
    var pane = { x: 0, y: 0, w: geo.w, h: geo.h };
    var f = { geo: geo, ink: inkBox(px, geo.w, geo.h, geo.ground, pane), chrome: colourCount(px, geo.w, geo.h, geo.chrome, pane), blocks: [] };
    for (var i = 0; i < geo.blocks.length && i < CAPTURED_BLOCKS; i++) {
        var b = geo.blocks[i];
        var one = { box: null, first: null, second: null, clusters: [], right: null, picture: 0, lines: [] };
        if (b.w > 0) {
            if (b.type === "images") {
                one.lines = bands(px, geo.w, geo.h, geo.ground, b).map(function (band) {
                    return { y0: band.y0, y1: band.y1,
                        clusters: clusters(px, geo.w, geo.h, geo.ground, { x: b.x, y: band.y0, w: b.w, h: band.y1 - band.y0 + 1 }) };
                });
            }
            one.box = inkBox(px, geo.w, geo.h, geo.ground, b);
            one.picture = pictureRows(px, geo.w, geo.h, b);
            var line = { x: b.x, y: b.y, w: b.w, h: Math.min(b.h, geo.lineBox) };
            one.first = inkBox(px, geo.w, geo.h, geo.ground, line);
            one.second = inkBox(px, geo.w, geo.h, geo.ground, { x: b.x, y: b.y + geo.lineBox, w: b.w, h: geo.lineBox });
            one.clusters = clusters(px, geo.w, geo.h, geo.ground, line);
            one.right = inkBox(px, geo.w, geo.h, geo.ground, { x: b.x + geo.hAdvance, y: b.y, w: b.w - geo.hAdvance, h: b.h });
        }
        f.blocks.push(one);
    }
    f.notice = geo.notice === null ? null : inkBox(px, geo.w, geo.h, geo.ground, geo.notice);
    f.noticeBand = null;
    f.below = null;
    if (geo.notice !== null) {
        var bottom = geo.notice.y + geo.notice.h;
        f.noticeBand = inkBox(px, geo.w, geo.h, geo.ground, { x: 0, y: geo.notice.y, w: geo.w, h: geo.notice.h });
        f.below = inkBox(px, geo.w, geo.h, geo.ground, { x: 0, y: bottom, w: geo.w, h: geo.h - bottom });
    }
    return f;
}

function blockOf(f, type) {
    for (var i = 0; i < f.geo.blocks.length; i++)
        if (f.geo.blocks[i].type === type)
            return i;
    return -1;
}

// Verdicts as [label, ok] pairs over every document's facts, keyed by name.
function verdict(all) {
    var out = [];
    function check(label, ok) { out.push([label, ok === true]); }
    for (var r = 0; r < REQUIRED.length; r++)
        check("fixture " + REQUIRED[r] + " was loaded and captured", all[REQUIRED[r]] !== undefined);
    var names = Object.keys(all);
    for (var n = 0; n < names.length; n++) {
        var f = all[names[n]];
        check(names[n] + " draws ink, never a blank pane", f.ink !== null && f.ink.count > 0);
        check(names[n] + " has delegates for its blocks", f.geo.blocks.length > 0 && f.geo.blocks[0].w > 0);
        for (var k = 0; k < f.blocks.length; k++) {
            // A block below the pane has no delegate yet, so only the blocks the pane shows are judged.
            if (DRAWN_TYPES.indexOf(f.geo.blocks[k].type) >= 0 && f.geo.blocks[k].w > 0 && f.geo.blocks[k].y < f.geo.h)
                check(names[n] + " block " + k + " (" + f.geo.blocks[k].type + ") draws ink", f.blocks[k].box !== null);
        }
    }
    var raw = all["07-rawhtml.md"];
    if (raw !== undefined) {
        var img = blockOf(raw, "image");
        var run = blockOf(raw, "run");
        var captured = raw.geo.blocks.length;
        // The pixel checks index into the captured blocks, so a document that outgrows the cap fails here by name.
        check("07 has no more blocks than the harness captures", raw.geo.texts.length <= CAPTURED_BLOCKS);
        var box = img < 0 ? null : raw.blocks[img].box;
        var pane = raw.geo.w / 2;
        check("07 the logo is an image block", img >= 0 && img < captured);
        check("07 the logo is as wide as its width attribute",
            box !== null && Math.abs((box.x1 - box.x0 + 1) - raw.geo.blocks[img].width) <= SIZE_SLACK);
        check("07 the logo is centred", box !== null && Math.abs((box.x0 + box.x1 + 1) / 2 - pane) <= CENTRE_SLACK);
        check("07 the centred title is a run block", run >= 0 && run < captured);
        var title = run < 0 ? null : raw.blocks[run].first;
        check("07 the centred title is centred", title !== null && Math.abs((title.x0 + title.x1 + 1) / 2 - pane) <= CENTRE_SLACK);
        var plain = all["17-plain-title.md"], bold = all["18-bold-title.md"];
        if (plain !== undefined && bold !== undefined && title !== null)
            check("07 the centred title is bold", Math.abs(title.count - bold.ink.count) < Math.abs(title.count - plain.ink.count));
        // geo.texts holds every block of the document, not only the captured ones.
        for (var i = 0; i < raw.geo.texts.length; i++) {
            var text = raw.geo.texts[i];
            check("07 block " + i + " carries no script, style or on* text",
                text.indexOf("alert") < 0 && text.indexOf("not allowed") < 0 && text.indexOf("color: red") < 0 && text.indexOf("onclick") < 0);
        }
        var all07 = raw.geo.texts.join("|");
        check("07 the div text stays", all07.indexOf("A div with a style attribute") >= 0);
        check("07 the details body is drawn", all07.indexOf("Hidden body text inside details.") >= 0);
        var bodyAt = -1, divAt = -1;
        raw.geo.texts.forEach(function (t, k) {
            if (t.indexOf("Hidden body text") >= 0) bodyAt = k;
            if (t.indexOf("A div with a style attribute") >= 0) divAt = k;
        });
        check("07 the div text starts its own block, never joined to the paragraph above", bodyAt >= 0 && divAt > bodyAt);
    }
    var base = all["16-sub-base.md"], low = all["16-sub-low.md"], high = all["16-sub-high.md"];
    if (base !== undefined && low !== undefined && high !== undefined) {
        var b0 = base.blocks[0].right, l0 = low.blocks[0].right, h0 = high.blocks[0].right;
        check("sub is lowered below the baseline glyph", b0 !== null && l0 !== null && l0.y1 > b0.y1);
        check("sup is raised above the baseline glyph", b0 !== null && h0 !== null && h0.y1 <= b0.y1 - RAISE_PX);
    }
    var key = all["19-key.md"], noKey = all["19-nokey.md"];
    if (key !== undefined && noKey !== undefined) {
        check("kbd draws a key cap on the chrome surface", key.chrome >= MIN_CAP_PIXELS && noKey.chrome < MIN_CAP_PIXELS);
    }
    var sum = all["20-summary.md"];
    if (sum !== undefined) {
        var c = sum.blocks[0].clusters;
        check("details draws its summary behind a disclosure mark and the body open",
            c.length === 2 && c[0].x1 - c[0].x0 + 1 <= MARK_MAX_WIDTH && String(sum.geo.blocks[0].text).indexOf("Body") >= 0);
    }
    var deep = all["15-pathological.md"];
    if (deep !== undefined) {
        check("15 the pane switched to its source", deep.geo.tooDeep === true);
        check("15 the notice is drawn", deep.notice !== null && deep.notice.count > 0);
        check("15 the notice names the limit", String(deep.geo.noticeText).indexOf("32") >= 0);
        // The notice's band holds the notice alone, and the source starts below it across the block gap.
        var noticeBottom = deep.geo.notice === null ? 0 : deep.geo.notice.y + deep.geo.notice.h;
        check("15 the notice band holds only the notice's ink",
            deep.notice !== null && deep.noticeBand !== null && deep.noticeBand.count === deep.notice.count);
        check("15 the source is drawn under the notice, across the block gap",
            deep.notice !== null && deep.below !== null && deep.below.y0 > deep.notice.y1
            && deep.below.y0 >= noticeBottom + deep.geo.blockGap);
    }
    return out;
}
