// Pin the QML cache-key mirror to the shared ES module, including both layouts of one source.
import { argv, finish, importFile, readText, resolve, absolute } from "./js-runtime.mjs";

const tree = absolute(argv[0] || ".");
const { cacheKey, tableDigest } = await importFile(resolve(tree, "ui/js/FigureWorker.mjs"));
const service = readText(resolve(tree, "ui/FigureService.qml"));
// Sample input: function name(a, b) { body with { nested } braces } answers the text between the outer braces.
function functionBody(source, name) {
    const at = source.indexOf("function " + name + "(");
    if (at < 0)
        throw new Error("FigureService function " + name + " is missing");
    const open = source.indexOf("{", at);
    let depth = 0;
    for (let i = open; i < source.length; i++) {
        depth += source[i] === "{" ? 1 : source[i] === "}" ? -1 : 0;
        if (depth === 0)
            return source.slice(open + 1, i);
    }
    throw new Error("FigureService function " + name + " does not close");
}
const digestOf = new Function("table", functionBody(service, "tableDigestOf"));
const qmlKeyOf = new Function("root", "kind", "source", "t", "display", functionBody(service, "cacheKeyOf"));
const qmlKey = (kind, source, t, display) => qmlKeyOf({ tableDigestOf: digestOf }, kind, source, t, display);
// A printable ASCII advance table in thousandths of an em, 95 entries, and the same table with one entry changed.
const TABLE_LENGTH = 95;
const table = Array.from({ length: TABLE_LENGTH }, (unused, i) => 500 + (i % 7) * 20);
const nudged = table.map((v, i) => (i === TABLE_LENGTH - 1 ? v + 1 : v));
const themes = [{ bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 14, exPx: 7.7, advances: table, boldAdvances: table },
    { bg: "#fff", fg: "#000" }];
// The key stands a table in by a short digest, so a request's key stays far shorter than the table's text.
const DIGEST_LENGTH_MAX = 8;
let checks = 0;
let failures = 0;
function check(ok, why) {
    checks++;
    if (!ok) {
        failures++;
        console.log("FAIL " + why);
    }
}
for (const theme of themes) {
    for (const display of [false, true])
        check(qmlKey("math", "x^2", theme, display) === cacheKey("math", "x^2", theme, display), "service and worker agree on a formula key");
    check(qmlKey("math", "x^2", theme, false) !== qmlKey("math", "x^2", theme, true), "one source has separate inline and display cache keys");
    for (const role of ["bg", "fg", "accent", "muted", "line", "surface", "border", "font", "bodyPx", "exPx", "advances", "boldAdvances"]) {
        const value = role === "advances" || role === "boldAdvances" ? nudged : ["bodyPx", "exPx"].includes(role) ? 20 : "changed " + role;
        const changed = { ...theme, [role]: value };
        check(cacheKey("mermaid", "A --> B", theme, true) !== cacheKey("mermaid", "A --> B", changed, true), "worker cache key includes theme role " + role);
        check(qmlKey("mermaid", "A --> B", changed, true) === cacheKey("mermaid", "A --> B", changed, true), "service and worker agree on theme role " + role);
    }
}
check(tableDigest(table).length <= DIGEST_LENGTH_MAX && digestOf(table) === tableDigest(table), "the service's digest is the worker's, " + tableDigest(table));
check(tableDigest(table) !== tableDigest(nudged) && tableDigest([]) === tableDigest(undefined), "one changed entry changes the digest, and no table digests as none");
console.log(`figure-cache: ${checks} check(s), ${failures} failed`);
finish(failures);
