// Maths (MathJax) and diagrams (beautiful-mermaid) through a pure ES module shared by node and quickjs-ng.

// Requests carry {id, kind, source, display, theme}; answers carry {id, svg} or {id, error}; FigureService caches by kind, source, display and theme.

export var MATH_LIMIT = 4096;
export var MERMAID_LIMIT = 32768;
export var CACHE_MAX = 64;

export function themeKey(t) {
    return [t.bg, t.fg, t.accent || "", t.font || "", t.bodyPx || 0,
        t.muted || "", t.surface || ""].join("|");
}

export function cacheKey(kind, source, t, display) {
    return kind + "\n" + themeKey(t) + "\n" + !!display + "\n" + source;
}

function hexRGB(h) {
    h = String(h).trim();
    if (h.charAt(0) !== "#")
        return null;
    h = h.slice(1);
    if (h.length === 3)
        h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    if (h.length !== 6)
        return null;
    var n = parseInt(h, 16);
    if (isNaN(n))
        return null;
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function toHex(c) {
    function b(v) {
        var s = Math.max(0, Math.min(255, Math.round(v))).toString(16);
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

// Find the matching close paren for the open paren at i; -1 if unbalanced.
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

function parseMix(inner, table, depth) {
    var args = splitTop(inner, ",").map(function (x) { return x.trim(); });
    if (args.length < 3 || args[0] !== "in srgb")
        return null;
    var stops = args.slice(1).map(function (a) {
        var m = a.match(/^(.*?)\s+([\d.]+)%\s*$/);
        if (m)
            return [resolveValue(m[1].trim(), table, depth + 1), parseFloat(m[2]) / 100];
        return [resolveValue(a, table, depth + 1), -1];
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

function resolveValue(s, table, depth) {
    if (depth > 12)
        return s;
    var out = s;
    var again = true;
    while (again) {
        again = false;
        var i = out.indexOf("var(");
        if (i >= 0) {
            var j = closeParen(out, i + 3);
            if (j < 0)
                return out;
            var inner = out.slice(i + 4, j);
            var parts = splitTop(inner, ",");
            var name = parts[0].trim().replace(/^--/, "");
            var val;
            if (Object.prototype.hasOwnProperty.call(table, name))
                val = resolveValue(table[name], table, depth + 1);
            else if (parts.length > 1)
                val = resolveValue(parts.slice(1).join(","), table, depth + 1);
            else
                return out;
            out = out.slice(0, i) + val + out.slice(j + 1);
            again = true;
            continue;
        }
        var m = out.indexOf("color-mix(");
        if (m >= 0) {
            var e = closeParen(out, m + 9);
            if (e < 0)
                return out;
            var got = parseMix(out.slice(m + 10, e), table, depth);
            if (got === null)
                return out;
            out = out.slice(0, m) + got + out.slice(e + 1);
            again = true;
        }
    }
    return out;
}

// Null when clean, else a short reason. xmlns is a namespace, never a fetch,
// so it is exempt from the http check.
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

// Inline the library's class rules as presentation attributes, then drop
// every <style> block. Only fill, stroke, widths, opacity and font props
// cross over: the rest is layout Qt SVG never reads.
var INLINE_PROPS = ["fill", "stroke", "stroke-width", "stroke-linecap",
    "stroke-linejoin", "stroke-dasharray", "opacity",
    "font-family", "font-size", "font-weight", "text-anchor"];

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
                add.push(p + "=\"" + r.decls[p] + "\"");
            });
        });
        if (add.length === 0)
            return tag;
        return "<" + name + attrs + (add.length ? " " + add.join(" ") : "") + self + ">";
    });
}

const MERMAID_BODY_PX = 13;
const CANVAS_MARGIN = 1;
const BOUNDS_PRECISION = 10;
const TEXT_DESCENT_RATIO = 0.3;
const DEFAULT_STROKE_WIDTH = 1;
const DEFAULT_MITER_LIMIT = 4;
const MARKER_EXTENT = 4;

// Sample input: <text font-size="13" dy="4.55">A</text> keeps the library's label metrics.
function forceText(svg, family, foreground) {
    var font = escAttr(family);
    return svg.replace(/<(?:text|tspan)(\s[^<>]*?)?>/g, function (tag) {
        var out = tag.replace(/\s(?:font-family|fill)="[^"]*"/g, "");
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

// Trim vertical SVG canvas padding where every painted primitive has explicit bounds.
function tightenVertical(svg) {
    var root = svg.match(/<svg\s[^<>]*>/);
    if (!root)
        return svg;
    var view = root[0].match(/viewBox="([^"]+)"/);
    var box = view ? view[1].trim().split(/\s+/).map(Number) : [];
    var body = svg.replace(/<defs>[\s\S]*?<\/defs>/g, "");
    // Unknown paths, inherited text positions and transforms retain the library's safe canvas.
    if (box.length !== 4 || !box.every(Number.isFinite) || /\btransform=|<path\b|<tspan\b/.test(body)
            || /<(?:g|svg)\b[^>]*\sstroke(?:-width)?=|\sstyle="[^"]*stroke/.test(body))
        return svg;
    var top = Infinity;
    var bottom = -Infinity;
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
    // Sample input: <polygon stroke="#fff" stroke-width="8" stroke-linejoin="miter"/> includes its joins.
    function strokePad(tag, kind) {
        var stroke = tag.match(/\sstroke="([^"]*)"/);
        var width = number(tag, "stroke-width", DEFAULT_STROKE_WIDTH);
        if (!Number.isFinite(width) || width < 0)
            return NaN;
        if (!stroke || stroke[1] === "none")
            return 0;
        var pad = width / 2;
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
    body.replace(/<(rect|line|circle|ellipse|polygon|polyline|text)\b[^<>]*>/g, function (tag, kind) {
        var pad = strokePad(tag, kind);
        if (kind === "rect") {
            var y = number(tag, "y", 0);
            include(y, y + number(tag, "height", NaN), pad);
        } else if (kind === "line") {
            var y1 = number(tag, "y1", 0), y2 = number(tag, "y2", 0);
            include(Math.min(y1, y2), Math.max(y1, y2), pad);
        } else if (kind === "circle" || kind === "ellipse") {
            var cy = number(tag, "cy", 0);
            var radius = number(tag, kind === "circle" ? "r" : "ry", NaN);
            include(cy - radius, cy + radius, pad);
        } else if (kind === "polygon" || kind === "polyline") {
            var points = tag.match(/\spoints="([^"]*)"/);
            var numbers = points ? points[1].trim().split(/[\s,]+/).map(Number) : [];
            if (numbers.length < 2 || numbers.length % 2 !== 0)
                valid = false;
            for (var i = 1; i < numbers.length; i += 2)
                include(numbers[i], numbers[i], pad);
        } else {
            var font = number(tag, "font-size", NaN);
            var baseline = number(tag, "y", NaN);
            var dy = tag.match(/\sdy="(-?[\d.]+)(em|%)?"/);
            baseline += dy ? Number(dy[1]) * (dy[2] === "em" ? font : dy[2] === "%" ? font / 100 : 1) : 0;
            include(baseline - font, baseline + TEXT_DESCENT_RATIO * font, pad);
        }
        return tag;
    });
    if (!valid || !Number.isFinite(top) || !(bottom > top))
        return svg;
    var y = Math.floor((top - CANVAS_MARGIN) * BOUNDS_PRECISION) / BOUNDS_PRECISION;
    var height = Math.ceil((bottom + CANVAS_MARGIN - y) * BOUNDS_PRECISION) / BOUNDS_PRECISION;
    var head = root[0].replace(/height="[^"]*"/, 'height="' + height + '"');
    head = head.replace(/viewBox="[^"]*"/, 'viewBox="' + box[0] + ' ' + y + ' ' + box[2] + ' ' + height + '"');
    return svg.replace(root[0], head);
}

// QtSvg's polyline end tangent uses last-to-last; a path uses its actual final segment at any angle.
// Sample input: <polyline points="10,10 40,40 40,40" marker-end="url(#tip)"/>.
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
    // Library-defined derivations (--_text etc. plus per-chart vars such as
    // --xychart-color-0) resolve against the theme base above.
    svg.replace(/<style>([\s\S]*?)<\/style>/g, function (m, css) {
        css.replace(/\/\*[\s\S]*?\*\//g, "").split(";").forEach(function (d) {
            var p = d.split(":");
            if (p.length < 2)
                return;
            // The block's first declaration carries its selector prefix
            // ("svg { --_text"), so only the text after the last brace names
            // the variable.
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
    // Whatever @import line survived resolution is remote by definition.
    // The font URLs carry semicolons of their own, so match to the paren.
    out = out.replace(/@import\s+url\([^)]*\)\s*;?/g, "");
    // A non-local url() is a fetch; a local #fragment (arrow markers) stays.
    out = out.replace(/url\((?!\s*#)[^)]*\)/g, "none");
    out = inlineClasses(out);
    out = out.replace(/<style>([\s\S]*?)<\/style>/g, "");
    // The root style only carried the theme vars and a background paint.
    out = out.replace(/<svg([^<>]*?)\sstyle="[^"]*"/, "<svg$1");
    // A click directive unwraps to its content; the link never ships.
    out = out.replace(/<a\s[^<>]*>/g, "").replace(/<\/a>/g, "");
    out = scaleCanvas(tightenVertical(forceText(out, t.font || "sans-serif", t.fg)), t.bodyPx || 14);
    out = markerPaths(out);
    var bad = checkSafe(out);
    if (bad)
        throw new Error("unsafe diagram: " + bad);
    if (out.indexOf("var(") >= 0)
        throw new Error("unresolved diagram style");
    return out;
}

export function postMath(svg, t, display) {
    if (svg.indexOf("merror") >= 0 || svg.indexOf("data-mjx-error") >= 0)
        throw new Error("formula did not render");
    var out = svg.split("currentColor").join(t.fg);
    // MathJax's TeX SVG has 1000 units per em and 442 per ex, independent of the input metrics.
    var exPx = (t.bodyPx || 16) * (display ? 1.2 : 1) * 0.442;
    out = out.replace(/(-?\d+(?:\.\d+)?)ex/g, function (m, v) {
        var px = Math.round(parseFloat(v) * exPx * 100) / 100;
        return String(px) + "px";
    });
    var bad = checkSafe(out);
    if (bad)
        throw new Error("unsafe formula: " + bad);
    return out;
}

// One figure through the loaded bundles: the svg, or a throw the caller
// words into {id, error}. apis carries the two bundle entry points.
export function renderFigure(kind, source, display, theme, apis) {
    if (kind !== "math" && kind !== "mermaid")
        throw new Error("unknown figure kind");
    if (kind === "math" && source.length > MATH_LIMIT)
        throw new Error("formula over 4 KiB");
    if (kind === "mermaid" && source.length > MERMAID_LIMIT)
        throw new Error("diagram over 32 KiB");
    if (kind === "math")
        return postMath(apis.texToSvg(source, !!display), theme, !!display);
    return postMermaid(apis.mermaidToSvg(source, theme.bg, theme.fg, { font: theme.font, padding: 1 }), theme);
}
