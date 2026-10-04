// Maths (MathJax) and diagrams (beautiful-mermaid) through a pure ES module shared by node and quickjs-ng.

// Requests carry {id, kind, source, display, theme}; answers carry {id, svg} or {id, error}; FigureService caches by kind, source, display and theme.

export var MATH_LIMIT = 4096;
export var MERMAID_LIMIT = 32768;
export var CACHE_MAX = 64;
// Bound nested variable and color-mix resolution before it can exhaust the stack.
var RESOLVER_DEPTH_MAX = 12;
// MathJax uses a 16 px body when the theme supplies no body size.
var DEFAULT_BODY_PX = 16;
// MathJax's TeX SVG sizes one ex at 442 thousandths of an em.
var EX_PER_EM = 0.442;
// Keep converted SVG dimensions to two decimal places.
var PX_ROUNDING_FACTOR = 100;
// CSS color-mix stops express each share as a percentage.
const PERCENT_SCALE = 100;
// Token lengths for slicing a var( or color-mix( call, and the radix and byte arithmetic of #rrggbb.
const VAR_NAME_LENGTH = "var".length;
const VAR_OPEN_LENGTH = "var(".length;
const MIX_NAME_LENGTH = "color-mix".length;
const MIX_OPEN_LENGTH = "color-mix(".length;
const HEX_RADIX = 16;
const RED_SHIFT = 16;
const GREEN_SHIFT = 8;
const BYTE_MASK = 255;

export function themeKey(t) {
    return [t.bg, t.fg, t.accent || "", t.muted || "", t.line || "", t.surface || "",
        t.border || "", t.font || "", t.bodyPx || 0, t.exPx || 0].join("|");
}

export function cacheKey(kind, source, t, display) {
    return kind + "\n" + themeKey(t) + "\n" + !!display + "\n" + source;
}

// Sample input: #abc or #aabbcc answers [r, g, b] bytes, anything else answers null.
function hexRGB(h) {
    h = String(h).trim();
    if (h.charAt(0) !== "#")
        return null;
    h = h.slice(1);
    if (h.length === 3)
        h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    if (h.length !== 6)
        return null;
    var n = parseInt(h, HEX_RADIX);
    if (isNaN(n))
        return null;
    return [(n >> RED_SHIFT) & BYTE_MASK, (n >> GREEN_SHIFT) & BYTE_MASK, n & BYTE_MASK];
}

function toHex(c) {
    function b(v) {
        var s = Math.max(0, Math.min(BYTE_MASK, Math.round(v))).toString(HEX_RADIX);
        return s.length < 2 ? "0" + s : s;
    }
    return "#" + b(c[0]) + b(c[1]) + b(c[2]);
}

// CSS color-mix(in srgb, ...) mixes in sRGB directly, so plain lerp.
export function mix(h1, h2, p) {
    var a = hexRGB(h1);
    var b = hexRGB(h2);
    if (!a || !b)
        return h1;
    return toHex([a[0] * p + b[0] * (1 - p), a[1] * p + b[1] * (1 - p), a[2] * p + b[2] * (1 - p)]);
}

// Every diagram paint comes from a theme role, including themes with no accent.
function baseVars(t) {
    return { bg: t.bg, fg: t.fg, accent: t.accent || t.fg,
        muted: t.muted || t.fg, line: t.line || t.muted || t.fg,
        surface: t.surface || t.bg, border: t.border || t.muted || t.fg };
}

// Sample input: closeParen("var(--a, #fff)", 3) answers 13, the matching close paren; -1 if unbalanced.
function closeParen(s, i) {
    var depth = 0;
    for (var k = i; k < s.length; k++) {
        if (s[k] === "(")
            depth++;
        else if (s[k] === ")") {
            depth--;
            if (depth === 0)
                return k;
        }
    }
    return -1;
}

// Sample input: splitTop("in srgb, var(--a, #fff) 25%, #000", ",") answers three parts, none cut inside parens.
function splitTop(s, sep) {
    var parts = [];
    var depth = 0;
    var cur = "";
    for (var k = 0; k < s.length; k++) {
        var c = s[k];
        if (c === "(")
            depth++;
        else if (c === ")")
            depth--;
        if (c === sep && depth === 0) {
            parts.push(cur);
            cur = "";
        } else {
            cur += c;
        }
    }
    parts.push(cur);
    return parts;
}

// Sample input: in srgb, var(--fg) 25%, var(--bg).
function parseMix(inner, table, depth, trail) {
    var args = splitTop(inner, ",").map(function (x) { return x.trim(); });
    if (args.length < 3 || args[0] !== "in srgb")
        return null;
    var stops = args.slice(1).map(function (a) {
        var m = a.match(/^(.*?)\s+([\d.]+)%\s*$/);
        if (m)
            return [resolveValue(m[1].trim(), table, depth + 1, trail), parseFloat(m[2]) / PERCENT_SCALE];
        return [resolveValue(a, table, depth + 1, trail), -1];
    });
    var named = stops.filter(function (s) { return s[1] >= 0; });
    var share = 0;
    if (named.length < stops.length) {
        var rest = 1 - named.reduce(function (t, s) { return t + s[1]; }, 0);
        share = rest / (stops.length - named.length);
    }
    if (stops.length !== 2)
        return null;
    var p0 = stops[0][1] < 0 ? share : stops[0][1];
    if (!hexRGB(stops[0][0]) || !hexRGB(stops[1][0]))
        return null;
    return mix(stops[0][0], stops[1][0], p0);
}

// Sample input: var(--accent, color-mix(in srgb, var(--fg) 25%, var(--bg))).
function resolveValue(s, table, depth, trail) {
    if (depth > RESOLVER_DEPTH_MAX)
        throw new Error("diagram style exceeds resolver depth cap");
    trail = trail || [];
    var out = s;
    var again = true;
    while (again) {
        again = false;
        var i = out.indexOf("var(");
        if (i >= 0) {
            var j = closeParen(out, i + VAR_NAME_LENGTH);
            if (j < 0)
                return out;
            var inner = out.slice(i + VAR_OPEN_LENGTH, j);
            var parts = splitTop(inner, ",");
            var name = parts[0].trim().replace(/^--/, "");
            var val;
            if (Object.prototype.hasOwnProperty.call(table, name)) {
                if (trail.indexOf(name) >= 0)
                    throw new Error("diagram style variable cycle at --" + name);
                val = resolveValue(table[name], table, depth + 1, trail.concat(name));
            } else if (parts.length > 1)
                val = resolveValue(parts.slice(1).join(","), table, depth + 1, trail);
            else
                return out;
            out = out.slice(0, i) + val + out.slice(j + 1);
            again = true;
            continue;
        }
        var m = out.indexOf("color-mix(");
        if (m >= 0) {
            var e = closeParen(out, m + MIX_NAME_LENGTH);
            if (e < 0)
                return out;
            var got = parseMix(out.slice(m + MIX_OPEN_LENGTH, e), table, depth, trail);
            if (got === null)
                return out;
            out = out.slice(0, m) + got + out.slice(e + 1);
            again = true;
        }
    }
    return out;
}

// Sample input: <svg xmlns="http://www.w3.org/2000/svg"><use href="#a"/></svg> answers null; a remote reference answers its reason, and xmlns is exempt.
export function checkSafe(svg) {
    var s = svg.replace(/xmlns(?::\w+)?="[^"]*"/g, "");
    if (s.indexOf("@import") >= 0)
        return "remote import";
    if (/<image[\s/>]/.test(s))
        return "image element";
    if (/<foreignObject[\s/>]/.test(s))
        return "foreign object";
    if (/<script[\s/>]/.test(s))
        return "script element";
    if (s.indexOf("http:") >= 0 || s.indexOf("https:") >= 0)
        return "remote reference";
    if (/url\((?!\s*#)/.test(s))
        return "non-local url";
    // Sample input: href="#glyph" or xlink:href="https://example.com/icon.svg".
    var href = s.match(/(?:href|xlink:href)\s*=\s*"([^"]*)"/g) || [];
    for (var k = 0; k < href.length; k++) {
        var v = href[k].replace(/^[^"]*"/, "").replace(/"$/, "");
        if (v.indexOf("//") >= 0 || /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(v))
            return "remote link";
    }
    if (s.indexOf("var(") >= 0 || s.indexOf("color-mix(") >= 0)
        return "unresolved style";
    return null;
}

function escAttr(s) {
    return String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
}

// Inline only fill, stroke, widths, opacity and font class rules as SVG attributes, then drop style blocks Qt never reads.
var INLINE_PROPS = ["fill", "stroke", "stroke-width", "stroke-linecap",
    "stroke-linejoin", "stroke-dasharray", "opacity",
    "font-family", "font-size", "font-weight", "text-anchor"];

// Sample input: <style>rect.node { fill: #ffffff; }</style><rect class="node"/>.
function inlineClasses(svg) {
    var styles = [];
    svg = svg.replace(/<style>([\s\S]*?)<\/style>/g, function (m, css) {
        styles.push(css);
        return "";
    });
    var rules = [];
    styles.join("\n").replace(/\/\*[\s\S]*?\*\//g, "").split("}").forEach(function (block) {
        var kv = block.split("{");
        if (kv.length !== 2)
            return;
        var sel = kv[0].trim();
        if (!sel || sel.indexOf("@") === 0 || sel === "svg" || sel === "text")
            return;
        var decls = {};
        kv[1].split(";").forEach(function (d) {
            var p = d.split(":");
            if (p.length < 2)
                return;
            var name = p[0].trim();
            if (INLINE_PROPS.indexOf(name) < 0)
                return;
            decls[name] = p.slice(1).join(":").trim();
        });
        if (Object.keys(decls).length === 0)
            return;
        sel.split(",").forEach(function (one) {
            one = one.trim();
            var m = one.match(/^([a-zA-Z]+)?((?:\.[a-zA-Z0-9_-]+)+)$/);
            if (!m)
                return;
            rules.push({ tag: m[1] || null, classes: m[2].split(".").filter(function (x) { return x; }), decls: decls });
        });
    });
    if (rules.length === 0)
        return svg;
    return svg.replace(/<([a-zA-Z]+)((?:\s[^<>]*?)?)(\/?)>/g, function (tag, name, attrs, self) {
        var cm = attrs.match(/class="([^"]*)"/);
        if (!cm)
            return tag;
        var have = cm[1].split(/\s+/);
        var add = [];
        rules.forEach(function (r) {
            if (r.tag && r.tag !== name)
                return;
            var ok = r.classes.every(function (c) { return have.indexOf(c) >= 0; });
            if (!ok)
                return;
            Object.keys(r.decls).forEach(function (p) {
                if (new RegExp("\\s" + p + "\\s*=").test(attrs) || new RegExp("\\s" + p + "\\s*=").test(add.join(" ")))
                    return;
                add.push(p + "=\"" + escAttr(r.decls[p]) + "\"");
            });
        });
        if (add.length === 0)
            return tag;
        return "<" + name + attrs + (add.length ? " " + add.join(" ") : "") + self + ">";
    });
}

const MERMAID_BODY_PX = 13;
// A diagram scales to the theme's body size; this size in px stands in when the request carries none.
const MERMAID_FALLBACK_BODY_PX = 14;
// The padding in px the diagram library lays round the drawing; tightenCanvas re-fits the canvas after it.
const MERMAID_PADDING = 1;
const CANVAS_MARGIN = 1;
// The drawing starts on the canvas's left edge, the content column's, like an image; the library's own 30 unit left margin goes.
const LEFT_MARGIN = 0;
// The wide class: "@" 1.015, W 0.989, m 0.974, % 0.95, M 0.907 (DejaVu, Liberation, Noto Sans maxima, PIL at 1000 px), and any non-ASCII glyph at one em.
const WIDE_ADVANCE_EM = 1.02;
const WIDE_GLYPHS = "@Wm%M";
// The symbol class: "#+<=>^~" 0.838 and w 0.818.
const SYMBOL_ADVANCE_EM = 0.84;
const SYMBOL_GLYPHS = "#+<=>^~w";
// The capital class: O and Q 0.787, & 0.78, G 0.778, D 0.77, N 0.76, H 0.752, down to E K P S Y 0.667; the other capitals sit below it.
const CAPITAL_ADVANCE_EM = 0.79;
const CAPITAL_GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ&";
// The rest: digits, "$", "{" and "}" 0.636, lowercase at most 0.635, punctuation below.
const TEXT_ADVANCE_EM = 0.64;
const ASCII_LIMIT = 0x7f;
// A centred label reaches half its width left of its x.
const MIDDLE_SHARE = 0.5;
const BOUNDS_PRECISION = 10;
const TEXT_DESCENT_RATIO = 0.3;
const DEFAULT_STROKE_WIDTH = 1;
const DEFAULT_MITER_LIMIT = 4;
const MARKER_EXTENT = 4;
// A stroke reaches half its width past the geometry on each side.
const HALF_STROKE = 0.5;

// Sample input: <text font-size="13" dy="4.55">A</text> keeps the library's label metrics.
function forceText(svg, family, foreground) {
    var font = escAttr(family);
    return svg.replace(/<(?:text|tspan)(\s[^<>]*?)?>/g, function (tag) {
        var out = tag.replace(/\s(?:font-family|fill)\s*=\s*(?:"[^"]*"|'[^']*')/g, "");
        return out.replace(/>$/, ' font-family="' + font + '" fill="' + escAttr(foreground) + '">');
    });
}

// Sample input: <svg width="100" height="50" viewBox="0 0 100 50"> doubles as one figure at body 26.
function scaleCanvas(svg, px) {
    var scale = px / MERMAID_BODY_PX;
    return svg.replace(/<svg\b[^<>]*>/, function (root) {
        return root.replace(/\s(width|height)="([\d.]+)"/g, function (m, name, value) {
            return ' ' + name + '="' + Number(value) * scale + '"';
        });
    });
}

// Sample input: dy="1.5em" at font 13 shifts a baseline 19.5, and a bare dy="4" shifts 4.
function shift(tag, font) {
    var dy = tag.match(/\sdy="(-?[\d.]+)(em|%)?"/);
    return dy ? Number(dy[1]) * (dy[2] === "em" ? font : dy[2] === "%" ? font / PERCENT_SCALE : 1) : 0;
}

// QtSvg ignores every dy, so a baseline lands on its y alone; the library centres a label with a dy of 0.35 em, which is the whole of the centring.
const BAKED_DECIMALS = 3;
// Sample input: <text x="31" y="19.45" font-size="13" dy="4.55">A</text> reads <text y="24" x="31" font-size="13">A</text>, and a tspan's dy becomes its own y.
function bakeDy(svg) {
    function put(tag, y) {
        var rest = tag.replace(/\sdy="[^"]*"/, "").replace(/\sy="[^"]*"/, "");
        return rest.replace(/^<(text|tspan)/, '<$1 y="' + Number(y.toFixed(BAKED_DECIMALS)) + '"');
    }
    function attr(tag, name) {
        var found = tag.match(new RegExp("\\s" + name + '="([^"]*)"'));
        return found ? Number(found[1]) : NaN;
    }
    return svg.replace(/<text\b([^<>]*)>((?:[^<]|<tspan\b[^<>]*>[^<]*<\/tspan>)*)<\/text>/g, function (all, attrs, content) {
        var head = "<text" + attrs + ">";
        var font = attr(head, "font-size");
        var baseline = attr(head, "y");
        // A text whose size or baseline cannot be read stays as the library drew it.
        if (!Number.isFinite(baseline) || !Number.isFinite(font))
            return all;
        var textShift = shift(head, font);
        var lines = 0;
        var body = content.replace(/<tspan\b[^<>]*>/g, function (tag) {
            var size = Number.isFinite(attr(tag, "font-size")) ? attr(tag, "font-size") : font;
            var pen = Number.isFinite(attr(tag, "y")) ? attr(tag, "y") : baseline;
            // The nearest element naming a dy supplies it, so the text's own moves only a first line that names none.
            baseline = pen + (/\sdy=/.test(tag) ? shift(tag, size) : lines === 0 ? textShift : 0);
            lines++;
            return put(tag, baseline);
        });
        return lines === 0 ? put(head, baseline + textShift) + content + "</text>" : put(head, attr(head, "y")) + body + "</text>";
    });
}

// Sample input: "WOi" advances 2.45 em, the wide glyph at 1.02, the capital at 0.79 and the narrow one at 0.64.
function advance(words) {
    var em = 0;
    Array.from(words).forEach(function (glyph) {
        em += glyph.codePointAt(0) > ASCII_LIMIT || WIDE_GLYPHS.indexOf(glyph) >= 0 ? WIDE_ADVANCE_EM
            : SYMBOL_GLYPHS.indexOf(glyph) >= 0 ? SYMBOL_ADVANCE_EM
            : CAPITAL_GLYPHS.indexOf(glyph) >= 0 ? CAPITAL_ADVANCE_EM : TEXT_ADVANCE_EM;
    });
    return em;
}

// Trim the SVG canvas padding above, below and left of the drawing where every painted primitive has explicit bounds.
function tightenCanvas(svg) {
    var root = svg.match(/<svg\s[^<>]*>/);
    if (!root)
        return svg;
    var view = root[0].match(/viewBox="([^"]+)"/);
    var box = view ? view[1].trim().split(/\s+/).map(Number) : [];
    var body = svg.replace(/<defs>[\s\S]*?<\/defs>/g, "");
    // Unknown paths and transforms retain the library's safe canvas.
    if (box.length !== 4 || !box.every(Number.isFinite) || /\btransform=|<path\b/.test(body)
            || /<(?:g|svg)\b[^>]*\sstroke(?:-width)?=|\sstyle="[^"]*stroke/.test(body))
        return svg;
    var top = Infinity;
    var bottom = -Infinity;
    var left = Infinity;
    var valid = true;
    // Sample input: <rect height="80"/> reads 80 from its height attribute.
    function number(tag, name, fallback) {
        var found = tag.match(new RegExp('\\s' + name + '="([^"]*)"'));
        return found ? (found[1].trim() === "" ? NaN : Number(found[1])) : fallback;
    }
    function include(low, high, pad) {
        if (!Number.isFinite(low) || !Number.isFinite(high) || !Number.isFinite(pad)) {
            valid = false;
            return;
        }
        top = Math.min(top, low - pad);
        bottom = Math.max(bottom, high + pad);
    }
    function includeLeft(x, pad) {
        if (!Number.isFinite(x) || !Number.isFinite(pad)) {
            valid = false;
            return;
        }
        left = Math.min(left, x - pad);
    }
    // Sample input: <polygon stroke="#fff" stroke-width="8" stroke-linejoin="miter"/> includes its joins.
    function strokePad(tag, kind) {
        var stroke = tag.match(/\sstroke="([^"]*)"/);
        var width = number(tag, "stroke-width", DEFAULT_STROKE_WIDTH);
        if (!Number.isFinite(width) || width < 0)
            return NaN;
        if (!stroke || stroke[1] === "none")
            return 0;
        var pad = width * HALF_STROKE;
        if (kind === "polygon" || kind === "polyline") {
            var join = tag.match(/\sstroke-linejoin="([^"]*)"/);
            if (!join || join[1] === "miter") {
                var limit = number(tag, "stroke-miterlimit", DEFAULT_MITER_LIMIT);
                if (!(limit >= 1))
                    return NaN;
                pad *= limit;
            }
            else if (join[1] !== "round" && join[1] !== "bevel")
                return NaN;
        }
        if (kind === "line" || kind === "polyline") {
            var cap = tag.match(/\sstroke-linecap="([^"]*)"/);
            if (cap && cap[1] === "square")
                pad *= Math.SQRT2;
            else if (cap && cap[1] !== "round" && cap[1] !== "butt")
                return NaN;
        }
        if (/marker-/.test(tag))
            pad += MARKER_EXTENT * width;
        return pad;
    }
    body.replace(/<(rect|line|circle|ellipse|polygon|polyline)\b[^<>]*>/g, function (tag, kind) {
        var pad = strokePad(tag, kind);
        if (kind === "rect") {
            var y = number(tag, "y", 0);
            include(y, y + number(tag, "height", NaN), pad);
            includeLeft(number(tag, "x", 0), pad);
        } else if (kind === "line") {
            var y1 = number(tag, "y1", 0), y2 = number(tag, "y2", 0);
            include(Math.min(y1, y2), Math.max(y1, y2), pad);
            includeLeft(Math.min(number(tag, "x1", 0), number(tag, "x2", 0)), pad);
        } else if (kind === "circle" || kind === "ellipse") {
            var cy = number(tag, "cy", 0);
            var radius = number(tag, kind === "circle" ? "r" : "ry", NaN);
            include(cy - radius, cy + radius, pad);
            includeLeft(number(tag, "cx", 0) - (kind === "circle" ? radius : number(tag, "rx", NaN)), pad);
        } else if (kind === "polygon" || kind === "polyline") {
            var points = tag.match(/\spoints="([^"]*)"/);
            var numbers = points ? points[1].trim().split(/[\s,]+/).map(Number) : [];
            if (numbers.length < 2 || numbers.length % 2 !== 0)
                valid = false;
            for (var i = 1; i < numbers.length; i += 2) {
                include(numbers[i], numbers[i], pad);
                includeLeft(numbers[i - 1], pad);
            }
        }
        return tag;
    });
    // Sample input: <text x="70" y="50" font-size="13" text-anchor="middle"><tspan x="70" dy="-4">a</tspan><tspan x="70" dy="17">b</tspan></text> holds two lines.
    var texts = body.match(/<text\b/g) || [];
    var read = 0;
    body.replace(/<text\b([^<>]*)>((?:[^<]|<tspan\b[^<>]*>[^<]*<\/tspan>)*)<\/text>/g, function (all, attrs, content) {
        read++;
        var lines = [];
        content.replace(/<tspan\b([^<>]*)>([^<]*)<\/tspan>/g, function (m, own, words) {
            lines.push({ attrs: own, words: words });
            return m;
        });
        var bare = content.replace(/<tspan\b[^<>]*>[^<]*<\/tspan>/g, "");
        // A line of its own sits in a tspan, and a text mixing bare words with tspans has no position the scan can read.
        if (lines.length === 0)
            lines.push({ attrs: "", words: content });
        else if (/\S/.test(bare))
            valid = false;
        if (/\sstyle=/.test(attrs))
            valid = false;
        var pad = strokePad(attrs, "text");
        var font = number(attrs, "font-size", NaN);
        var baseline = number(attrs, "y", NaN);
        var textShift = shift(attrs, font);
        lines.forEach(function (line, index) {
            // Without its own x, only the first line starts at the text's; a later one continues from an unknown pen position.
            if (/\sstyle=/.test(line.attrs) || (index > 0 && !/\sx=/.test(line.attrs)))
                valid = false;
            var size = number(line.attrs, "font-size", font);
            var pen = /\sy=/.test(line.attrs) ? number(line.attrs, "y", NaN) : baseline;
            // SVG takes a glyph's dy from the nearest element naming one, so the text's own dy moves only a first line that names none.
            baseline = pen + (/\sdy=/.test(line.attrs) ? shift(line.attrs, size) : index === 0 ? textShift : 0);
            var linePad = Math.max(pad, strokePad(line.attrs, "text"));
            include(baseline - size, baseline + TEXT_DESCENT_RATIO * size, linePad);
            var anchor = line.attrs.match(/\stext-anchor="([^"]*)"/) || attrs.match(/\stext-anchor="([^"]*)"/);
            var share = !anchor || anchor[1] === "start" ? 0 : anchor[1] === "middle" ? MIDDLE_SHARE : anchor[1] === "end" ? 1 : NaN;
            includeLeft(number(line.attrs, "x", number(attrs, "x", NaN)), share * advance(line.words) * size + linePad);
        });
        return all;
    });
    // A text the scan could not read whole, a self-closing one or one holding another element, keeps the library's canvas.
    if (read !== texts.length)
        valid = false;
    if (!valid || !Number.isFinite(top) || !(bottom > top) || !Number.isFinite(left))
        return svg;
    var y = Math.floor((top - CANVAS_MARGIN) * BOUNDS_PRECISION) / BOUNDS_PRECISION;
    var height = Math.ceil((bottom + CANVAS_MARGIN - y) * BOUNDS_PRECISION) / BOUNDS_PRECISION;
    var head = root[0].replace(/height="[^"]*"/, 'height="' + height + '"');
    // Only ever shrink: a primitive painted left of the library's canvas keeps the canvas it had.
    var x = Math.max(box[0], Math.floor((left - LEFT_MARGIN) * BOUNDS_PRECISION) / BOUNDS_PRECISION);
    var width = box[2] - (x - box[0]);
    head = head.replace(/\swidth="[\d.]+"/, ' width="' + width + '"');
    head = head.replace(/viewBox="[^"]*"/, 'viewBox="' + x + ' ' + y + ' ' + width + ' ' + height + '"');
    return svg.replace(root[0], head);
}

// Sample input: <polyline points="10,10 40,40 40,40" marker-end="url(#tip)"/> becomes a path, since QtSvg's polyline end tangent uses last-to-last.
function markerPaths(svg) {
    return svg.replace(/<polyline\b[^<>]*\/>/g, function (tag) {
        if (!/\smarker-(?:start|mid|end)=/.test(tag))
            return tag;
        var found = tag.match(/\spoints="([^"]*)"/);
        var numbers = found ? found[1].match(/[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?/g) : null;
        if (!numbers || numbers.length < 4 || numbers.length % 2 !== 0)
            return tag;
        var points = [];
        for (var i = 0; i < numbers.length; i += 2) {
            if (i > 0 && Number(numbers[i]) === Number(numbers[i - 2])
                    && Number(numbers[i + 1]) === Number(numbers[i - 1]))
                continue;
            points.push(numbers[i] + " " + numbers[i + 1]);
        }
        if (points.length < 2)
            return tag;
        return tag.replace(/^<polyline\b/, "<path")
            .replace(/\spoints="[^"]*"/, ' d="M' + points.join(" L") + '"');
    });
}

export function postMermaid(svg, t) {
    var table = baseVars(t);
    // Sample input: <style>svg { --_text: var(--fg); --xychart-color-0: var(--accent); }</style>.
    svg.replace(/<style>([\s\S]*?)<\/style>/g, function (m, css) {
        css.replace(/\/\*[\s\S]*?\*\//g, "").split(";").forEach(function (d) {
            var p = d.split(":");
            if (p.length < 2)
                return;
            // The first declaration's selector prefix ("svg { --_text") ends at the last brace before the variable name.
            var name = p[0].trim();
            var brace = Math.max(name.lastIndexOf("{"), name.lastIndexOf("}"));
            if (brace >= 0)
                name = name.slice(brace + 1).trim();
            if (name.indexOf("--") !== 0)
                return;
            table[name.replace(/^--/, "")] = p.slice(1).join(":").trim();
        });
        return m;
    });
    // Every label uses foreground; the remaining paints use theme edge and surface roles.
    table["_text-sec"] = "var(--fg)";
    table["_text-muted"] = "var(--fg)";
    table["_text-faint"] = "var(--fg)";
    if (table.line !== undefined)
        table["_inner-stroke"] = "var(--line)";
    table["_group-hdr"] = "var(--surface)";
    table["_key-badge"] = "var(--surface)";
    Object.keys(table).forEach(function (k) {
        table[k] = resolveValue(table[k], table, 0);
    });
    var out = resolveValue(svg, table, 0);
    // Surviving @import lines are remote; match the paren because font URLs carry semicolons.
    out = out.replace(/@import\s+url\([^)]*\)\s*;?/g, "");
    // A non-local url() is a fetch; a local #fragment (arrow markers) stays.
    out = out.replace(/url\((?!\s*#)[^)]*\)/g, "none");
    out = inlineClasses(out);
    out = out.replace(/<style>([\s\S]*?)<\/style>/g, "");
    // The root style only carried the theme vars and a background paint.
    out = out.replace(/<svg([^<>]*?)\sstyle="[^"]*"/, "<svg$1");
    // A click directive unwraps to its content; the link never ships.
    out = out.replace(/<a\s[^<>]*>/g, "").replace(/<\/a>/g, "");
    out = scaleCanvas(tightenCanvas(bakeDy(forceText(out, t.font || "sans-serif", t.fg))), t.bodyPx || MERMAID_FALLBACK_BODY_PX);
    out = markerPaths(out);
    var bad = checkSafe(out);
    if (bad)
        throw new Error("unsafe diagram: " + bad);
    if (out.indexOf("var(") >= 0)
        throw new Error("unresolved diagram style");
    return out;
}

export function postMath(svg, t) {
    if (svg.indexOf("merror") >= 0 || svg.indexOf("data-mjx-error") >= 0)
        throw new Error("formula did not render");
    var out = svg.split("currentColor").join(t.fg);
    // MathJax's TeX SVG has 442 units per ex; a formula draws its ex at the body x-height the pane measured, or the em rule when none came.
    var exPx = t.exPx > 0 ? t.exPx : (t.bodyPx || DEFAULT_BODY_PX) * EX_PER_EM;
    out = out.replace(/(-?\d+(?:\.\d+)?)ex/g, function (m, v) {
        var px = Math.round(parseFloat(v) * exPx * PX_ROUNDING_FACTOR) / PX_ROUNDING_FACTOR;
        return String(px) + "px";
    });
    var bad = checkSafe(out);
    if (bad)
        throw new Error("unsafe formula: " + bad);
    return out;
}

// Render through the two bundle entry points in apis, returning SVG or throwing a reason the caller puts in {id, error}.
export function renderFigure(kind, source, display, theme, apis) {
    if (kind !== "math" && kind !== "mermaid")
        throw new Error("unknown figure kind");
    if (kind === "math" && source.length > MATH_LIMIT)
        throw new Error("formula over 4 KiB");
    if (kind === "mermaid" && source.length > MERMAID_LIMIT)
        throw new Error("diagram over 32 KiB");
    if (kind === "math")
        return postMath(apis.texToSvg(source, !!display), theme);
    return postMermaid(apis.mermaidToSvg(source, theme.bg, theme.fg, { font: theme.font, padding: MERMAID_PADDING }), theme);
}
