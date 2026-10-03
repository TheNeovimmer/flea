// Maths (MathJax) and diagrams (beautiful-mermaid) through a pure ES module shared by node and quickjs-ng.

// Requests carry {id, kind, source, display, theme}; answers carry {id, svg} or {id, error}; FigureService caches by kind, source, display and theme.

export var MATH_LIMIT = 4096;
export var MERMAID_LIMIT = 32768;
export var CACHE_MAX = 64;
// Bound nested variable and color-mix resolution before it can exhaust the stack.
var RESOLVER_DEPTH_MAX = 12;
// MathJax uses a 16 px body when the theme supplies no body size.
var DEFAULT_BODY_PX = 16;
// MathJax's ex size is half its body size.
var EX_BODY_FRACTION = 0.5;
// Keep converted SVG dimensions to two decimal places.
var PX_ROUNDING_FACTOR = 100;
// CSS color-mix stops express each share as a percentage.
const PERCENT_SCALE = 100;

export function themeKey(t) {
    return [t.bg, t.fg, t.accent || "", t.muted || "", t.line || "", t.surface || "",
        t.border || "", t.font || "", t.bodyPx || 0].join("|");
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

// Theme roles stay undefined unless named, so var() can fall back to the library's color-mix derivations.
function baseVars(t) {
    var v = { bg: t.bg, fg: t.fg };
    if (t.accent)
        v.accent = t.accent;
    if (t.muted)
        v.muted = t.muted;
    if (t.line)
        v.line = t.line;
    if (t.surface)
        v.surface = t.surface;
    if (t.border)
        v.border = t.border;
    return v;
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
            var j = closeParen(out, i + 3);
            if (j < 0)
                return out;
            var inner = out.slice(i + 4, j);
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
            var e = closeParen(out, m + 9);
            if (e < 0)
                return out;
            var got = parseMix(out.slice(m + 10, e), table, depth, trail);
            if (got === null)
                return out;
            out = out.slice(0, m) + got + out.slice(e + 1);
            again = true;
        }
    }
    return out;
}

// Null when clean, else a short reason; xmlns is a namespace and exempt from the http check.
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
                add.push(p + "=\"" + r.decls[p] + "\"");
            });
        });
        if (add.length === 0)
            return tag;
        return "<" + name + attrs + (add.length ? " " + add.join(" ") : "") + self + ">";
    });
}

function forceFont(svg, family) {
    var f = escAttr(family);
    return svg.replace(/<text(\s[^<>]*?)?>/g, function (tag) {
        var t = tag.replace(/\sfont-family="[^"]*"/, "");
        return t.replace(/>$/, " font-family=\"" + f + "\">");
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
    out = forceFont(out, t.font || "sans-serif");
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
    // The bundle sets em 16 ex 8, so one ex is half the body size in px.
    var exPx = (t.bodyPx || DEFAULT_BODY_PX) * EX_BODY_FRACTION;
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
    return postMermaid(apis.mermaidToSvg(source, theme.bg, theme.fg), theme);
}
