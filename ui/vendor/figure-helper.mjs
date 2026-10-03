// One sandboxed figure renderer: newline-delimited JSON in and out, started by flea --figure-helper under bwrap with no network or writable paths.
import * as std from "qjs:std";
import * as os from "qjs:os";

// ELK's GWT code takes Error from global and its in-process FakeWorker posts through setTimeout; neither exists until named here.
globalThis.global = globalThis;
globalThis.setTimeout = os.setTimeout;
globalThis.clearTimeout = os.clearTimeout;

// Sample input: {"id":3,"kind":"math","source":"\\frac{a}{b}","display":true,"theme":{"bg":"#101315","fg":"#c0caf5"}}.
var worker = await import("../js/FigureWorker.mjs");
var mathApi = null;
var mermaidApi = null;
var ERROR_WORDS = 160;

function failText(e) {
    var msg = String((e && e.message) || e).split("\n")[0].slice(0, ERROR_WORDS);
    return msg || "render failed";
}

function answer(out) {
    std.out.puts(JSON.stringify(out) + "\n");
    std.out.flush();
}

function themeOf(req) {
    return req.theme || {};
}

async function renderOne(req) {
    var kind = req.kind;
    var source = String(req.source || "");
    var theme = themeOf(req);
    if (kind === "math") {
        if (!mathApi)
            mathApi = await import("./math.mjs");
        return worker.renderFigure(kind, source, !!req.display, theme, mathApi);
    }
    if (kind === "mermaid") {
        if (!mermaidApi)
            mermaidApi = await import("./mermaid.mjs");
        var got = worker.renderFigure(kind, source, !!req.display, theme, mermaidApi);
        return (got && got.then) ? await got : got;
    }
    throw new Error("unknown figure kind");
}

// A bad line answers error under its own id, or id 0 when it names none; the loop survives it and EOF ends the process.
var line;
while ((line = std.in.getline()) !== null) {
    if (line === "" || line === "\n")
        continue;
    var req = null;
    try {
        req = JSON.parse(line);
    } catch (e) {
        answer({ id: 0, error: failText(e) });
        continue;
    }
    var id = (req && typeof req.id === "number") ? req.id : 0;
    try {
        answer({ id: id, svg: await renderOne(req) });
    } catch (e) {
        answer({ id: id, error: failText(e) });
    }
}
