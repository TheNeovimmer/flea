// Pin the QML cache-key mirror to the shared ES module, including both layouts of one source.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const tree = resolve(process.argv[2] || ".");
const { cacheKey } = await import(pathToFileURL(resolve(tree, "ui/js/FigureWorker.mjs")));
const service = readFileSync(resolve(tree, "ui/FigureService.qml"), "utf8");
// Sample input: function cacheKeyOf(kind, source, t, display) { var key = [...].join("|"); return ...; }.
const match = /function cacheKeyOf\([^)]*\)\s*\{([^}]+)\}/.exec(service);
if (!match)
    throw new Error("FigureService cache-key function is missing");
const qmlKey = new Function("kind", "source", "t", "display", match[1]);
const themes = [{ bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 14, exPx: 7.7, advance: 0.6, boldAdvance: 0.6 },
    { bg: "#fff", fg: "#000" }];
let checks = 0;
let failures = 0;
for (const theme of themes) {
    for (const display of [false, true]) {
        checks++;
        if (qmlKey("math", "x^2", theme, display) !== cacheKey("math", "x^2", theme, display))
            failures++;
    }
    checks++;
    if (qmlKey("math", "x^2", theme, false) === qmlKey("math", "x^2", theme, true)) {
        failures++;
        console.log("FAIL one source has separate inline and display cache keys");
    }
    for (const role of ["bg", "fg", "accent", "muted", "line", "surface", "border", "font", "bodyPx", "exPx", "advance", "boldAdvance"]) {
        const changed = { ...theme, [role]: ["bodyPx", "exPx", "advance", "boldAdvance"].includes(role) ? 20 : "changed " + role };
        checks++;
        if (cacheKey("mermaid", "A --> B", theme, true) === cacheKey("mermaid", "A --> B", changed, true)) {
            failures++;
            console.log("FAIL worker cache key includes theme role " + role);
        }
        checks++;
        if (qmlKey("mermaid", "A --> B", changed, true) !== cacheKey("mermaid", "A --> B", changed, true)) {
            failures++;
            console.log("FAIL service and worker agree on theme role " + role);
        }
    }
}
console.log(`figure-cache: ${checks} check(s), ${failures} failed`);
process.exitCode = failures > 0 ? 1 : 0;
