// Figure engine for rendered Markdown: maths (MathJax) and diagrams
// (beautiful-mermaid). Pure logic with no QML imports; node runs it direct,
// and the assembler (tools/vendor-js/assemble-figure-workers.py) strips its
// export prefixes into the classic worker Qt's WorkerScript can load.
//
// Requests carry {id, kind, source, display, theme} plus bundleText on the
// first request of a kind, and answers carry {id, svg}, {id, error} or
// {id, needBundle}. The bundle travels as text because the worker engine
// parses neither module syntax (a parse-time SyntaxError, measured) nor a
// 2.8 MB compiled source (it wedges), while one eval of the text parses in
// milliseconds. The service reads the text off disk; parsing and rendering
// stay off the thread. Identical (kind, source, theme) answers come from a
// 64-entry in-worker LRU.
// Browser aliases for bundle global sniffs. The worker global object
// exists but carries neither the window nor the self name, so isomorphic
// checks fall through to an undefined alias and every `v.Math` read throws.
// Aliasing both to the worker global mirrors a browser tab. Node skips this
// whole block, where window stays undefined and nothing changes.
if (typeof WorkerScript !== "undefined" && typeof window === "undefined") {
    var window = this;
    var self = this;
}

var MATH_LIMIT = 4096;
var MERMAID_LIMIT = 32768;
var CACHE_MAX = 64;
var cache = new Map();
var textApi = {};

export function themeKey(t) {
    return [t.bg, t.fg, t.accent || "", t.font || "", t.bodyPx || 0].join("|");
}

export function cacheKey(kind, source, t) {
    return kind + "\n" + themeKey(t) + "\n" + source;
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

// Base table: the theme's own colours. --accent and friends stay undefined
// unless the theme names them, so each var() falls back to the library's own
// derivation (itself a color-mix the resolver then computes).
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

function forceFont(svg, family) {
    var f = escAttr(family);
    return svg.replace(/<text(\s[^<>]*?)?>/g, function (tag) {
        var t = tag.replace(/\sfont-family="[^"]*"/, "");
        return t.replace(/>$/, " font-family=\"" + f + "\">");
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
    var exPx = (t.bodyPx || 16) / 2;
    out = out.replace(/(-?\d+(?:\.\d+)?)ex/g, function (m, v) {
        var px = Math.round(parseFloat(v) * exPx * 100) / 100;
        return String(px) + "px";
    });
    var bad = checkSafe(out);
    if (bad)
        throw new Error("unsafe formula: " + bad);
    return out;
}

export function render(req) {
    var kind = req.kind;
    var source = String(req.source || "");
    var t = req.theme || {};
    var key = cacheKey(kind, source, t);
    if (cache.has(key)) {
        var hit = cache.get(key);
        cache.delete(key);
        cache.set(key, hit);
        return Promise.resolve({ id: req.id, svg: hit });
    }
    if (kind !== "math" && kind !== "mermaid")
        return Promise.resolve({ id: req.id, error: "unknown figure kind" });
    if (kind === "math" && source.length > MATH_LIMIT)
        return Promise.resolve({ id: req.id, error: "formula over 4 KiB" });
    if (kind === "mermaid" && source.length > MERMAID_LIMIT)
        return Promise.resolve({ id: req.id, error: "diagram over 32 KiB" });
    if (!textApi[kind]) {
        if (req.bundleText) {
            try {
                installBundle(kind, req.bundleText);
            } catch (e) {
                return Promise.resolve(fail(req.id, e));
            }
        } else {
            return Promise.resolve({ id: req.id, needBundle: kind });
        }
    }
    try {
        return Promise.resolve(done(req.id, key, renderNow(kind, source, req, t)));
    } catch (e) {
        return Promise.resolve(fail(req.id, e, "render"));
    }
}

function kindApi(kind) {
    return textApi[kind];
}

// One eval of the whole bundle text: the engine parses megabytes in
// milliseconds, while compiling the same bytes as a worker source wedges it.
// The completion value of the trailing name expression is the API, so no
// global is ever named and no remote reference can hitchhike in.
// The pinned bundles were built for modern runtimes; the worker engine
// predates some builtins, so each proven-missing one gets a guarded
// polyfill here before any bundle text evaluates.
function polyfillEngine() {
    if (typeof Object.hasOwn !== "function") {
        Object.hasOwn = function (o, p) {
            return Object.prototype.hasOwnProperty.call(o, p);
        };
    }
    // The bundles address the global object by name. Node and browsers bind
    // it; this engine leaves the identifier undeclared, so a dummy stands
    // in. Reached only where it is missing, never where it exists.
    if (typeof globalThis === "undefined") {
        globalThis = {};
    }
    // beautiful-mermaid decodes embedded resources with atob() when it
    // exists and only then reaches for Node's Buffer; the worker has
    // neither, so a local base64 decoder keeps it off the Buffer path.
    if (typeof atob !== "function") {
        atob = function (input) {
            var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
            var str = String(input).replace(/[^A-Za-z0-9+/=]/g, "");
            var out = "";
            for (var i = 0; i < str.length; i += 4) {
                var e1 = chars.indexOf(str.charAt(i));
                var e2 = chars.indexOf(str.charAt(i + 1));
                var e3 = chars.indexOf(str.charAt(i + 2));
                var e4 = chars.indexOf(str.charAt(i + 3));
                out += String.fromCharCode((e1 << 2) | (e2 >> 4));
                if (e3 !== 64)
                    out += String.fromCharCode(((e2 & 15) << 4) | (e3 >> 2));
                if (e4 !== 64)
                    out += String.fromCharCode(((e3 & 3) << 6) | e4);
            }
            return out;
        };
    }
}

// Splits bundle text into evaluable chunks at top-level semicolons. One
// eval of megabytes wedges the worker engine's whole-unit analysis, while
// hundred-kilobyte pieces evaluate in milliseconds. The scanner tracks
// strings, template holes, comments and regex literals, so a semicolon
// inside any of those never splits.
var CHUNK_RX_WORDS = { "return": 1, "typeof": 1, "instanceof": 1, "in": 1,
    "of": 1, "new": 1, "delete": 1, "void": 1, "throw": 1, "case": 1,
    "do": 1, "else": 1, "yield": 1, "await": 1 };

function chunkWord(src, k) {
    var j = k - 1;
    while (j >= 0 && (src[j] === " " || src[j] === "\t" || src[j] === "\n" || src[j] === "\r")) j--;
    var end = j;
    while (j >= 0 && /[a-zA-Z0-9_$]/.test(src[j])) j--;
    return src.slice(j + 1, end + 1);
}

function splitChunks(src, target) {
    var parts = [];
    var depth = 0;
    var start = 0;
    var stack = [];
    var i = 0;
    while (i < src.length) {
        var c = src[i];
        var top = stack.length ? stack[stack.length - 1] : null;
        if (top === "sq" || top === "dq") {
            if (c === "\\") { i += 2; continue; }
            if ((top === "sq" && c === "'") || (top === "dq" && c === '"')) stack.pop();
            i++;
            continue;
        }
        if (top === "tpl") {
            if (c === "\\") { i += 2; continue; }
            if (c === "`") { stack.pop(); i++; continue; }
            if (c === "$" && src[i + 1] === "{") { stack.push("code"); depth++; i += 2; continue; }
            i++;
            continue;
        }
        if (top === "lc") {
            if (c === "\n") stack.pop();
            i++;
            continue;
        }
        if (top === "bc") {
            if (c === "*" && src[i + 1] === "/") { stack.pop(); i += 2; continue; }
            i++;
            continue;
        }
        if (top === "rx") {
            if (c === "\\") { i += 2; continue; }
            if (c === "[") { stack.push("rc"); i++; continue; }
            if (c === "/") { stack.pop(); i++; continue; }
            i++;
            continue;
        }
        if (top === "rc") {
            if (c === "\\") { i += 2; continue; }
            if (c === "]") stack.pop();
            i++;
            continue;
        }
        if (c === "'") { stack.push("sq"); i++; continue; }
        if (c === '"') { stack.push("dq"); i++; continue; }
        if (c === "`") { stack.push("tpl"); i++; continue; }
        if (c === "/" && src[i + 1] === "/") { stack.push("lc"); i += 2; continue; }
        if (c === "/" && src[i + 1] === "*") { stack.push("bc"); i += 2; continue; }
        if (c === "/") {
            var w = chunkWord(src, i);
            var pj = i - 1;
            while (pj >= 0 && (src[pj] === " " || src[pj] === "\t" || src[pj] === "\n" || src[pj] === "\r")) pj--;
            var pc = pj >= 0 ? src[pj] : "";
            var isRx = CHUNK_RX_WORDS[w] === 1 || ("([{=,:;!&|?+-*%~^<>".indexOf(pc) >= 0)
                || (pc === ">" && src[pj - 1] === "=");
            if (isRx) { stack.push("rx"); i++; continue; }
            i++;
            continue;
        }
        if (c === "(" || c === "[" || c === "{") depth++;
        else if (c === ")" || c === "]" || c === "}") {
            depth--;
            if (top === "code" && c === "}") {
                stack.pop();
                if (stack.length && stack[stack.length - 1] === "tpl") { i++; continue; }
            }
        } else if (c === ";" && depth === 0 && i - start >= target) {
            parts.push(src.slice(start, i + 1));
            start = i + 1;
        }
        i++;
    }
    if (start < src.length) parts.push(src.slice(start));
    return parts;
}

// Engine-compat patch for bundle text, applied before splitting. The lane
// engine predates Unicode property escapes (measured): `new
// RegExp("\\p{...}","u")` throws, and `/[\w\p{L}-]/u` literals parse but
// never match. The emoji detector degrades to never-match behind a
// try/catch (emoji width measurement only), and `\p{L}` becomes an explicit
// range list covering Latin, Greek, Cyrillic, CJK and kana, which is exact
// for ASCII names. On a modern engine the patch is behaviour-preserving:
// the try succeeds and the ranges match what `\p{L}` matches for these
// scripts. Math needs no patch.
var LATIN_LETTERS = "\\u00C0-\\u024F\\u0370-\\u03FF\\u0400-\\u04FF\\u1E00-\\u1EFF\\u3040-\\u30FF\\u4E00-\\u9FFF";

function compatPatchBundle(kind, text) {
    if (kind !== "mermaid")
        return text;
    var out = String(text).split("\\p{L}").join(LATIN_LETTERS);
    var helper = "function FigEmojiRegExp(){ try { return new RegExp(\"\\\\p{Emoji_Presentation}|\\\\p{Extended_Pictographic}\",\"u\"); } catch (e) { return /$^/; } }\n";
    out = out.split("new RegExp(\"\\\\p{Emoji_Presentation}|\\\\p{Extended_Pictographic}\",\"u\")").join("FigEmojiRegExp()");
    return helper + out;
}

function installBundle(kind, text) {
    polyfillEngine();
    var clean = compatPatchBundle(kind, String(text)).replace(/export\{\w+ as \w+\};?\s*$/, "");
    var local = kind === "math" ? "vu" : "Ubt";
    // Chunked: one eval of megabytes wedges the engine, hundred-kilobyte
    // pieces evaluate in milliseconds. In the worker the pieces run as
    // direct evals inside one sloppy call, so every chunk shares that
    // call's scope and its `this`, which an eval scope may not bind at all
    // ("this is not defined", measured in the lane). Under node they stay
    // indirect into the global scope, because a module is strict. Either way
    // the API name rides the last piece's completion value, so no global is
    // ever named.
    var parts = splitChunks(clean, 100000);
    var fn = null;
    if (typeof WorkerScript !== "undefined")
        fn = figRunDirect(parts, local);
    else {
        for (var i = 0; i < parts.length; i++) {
            try {
                if (i < parts.length - 1)
                    (0, eval)(parts[i]);
                else
                    fn = (0, eval)(parts[i] + "\n" + local + ";");
            } catch (e) {
                throw new Error("chunk " + i + "/" + parts.length + ": " + String((e && e.message) || e));
            }
        }
    }
    if (typeof fn !== "function")
        throw new Error("figure engine did not install");
    textApi[kind] = kind === "math" ? { texToSvg: fn } : { mermaidToSvg: fn };
}

// One sloppy call whose direct evals share its scope and its `this`. Never
// called under node, where the module around it is strict.
function figRunDirect(parts, local) {
    for (var i = 0; i < parts.length; i++) {
        try {
            if (i < parts.length - 1)
                eval(parts[i]);
            else
                return eval(parts[i] + "\n" + local + ";");
        } catch (e) {
            throw new Error("chunk " + i + "/" + parts.length + ": " + String((e && e.message) || e));
        }
    }
    throw new Error("figure engine did not install");
}

function renderNow(kind, source, req, t) {
    if (kind === "math")
        return postMath(textApi[kind].texToSvg(source, !!req.display), t);
    return postMermaid(textApi[kind].mermaidToSvg(source, t.bg, t.fg), t);
}

function done(id, key, svg) {
    cache.set(key, svg);
    if (cache.size > CACHE_MAX) {
        var first = cache.keys().next().value;
        cache.delete(first);
    }
    return { id: id, svg: svg };
}

function fail(id, e) {
    var msg = String((e && e.message) || e).split("\n")[0].slice(0, 160);
    return { id: id, error: msg || "render failed" };
}

// WorkerScript wiring: the assembler carries this block into the classic
// worker, where WorkerScript exists and the message pump runs. Under node it
// is skipped and render() is called direct.
if (typeof WorkerScript !== "undefined") {
    WorkerScript.onMessage = function (m) {
        render(m).then(function (r) {
            WorkerScript.sendMessage(r);
        });
    };
}
