// Exercise SVG post-processing directly, with the cyclic fixture confined to a child process.
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { postMermaid, postMath } from "../ui/js/FigureWorker.mjs";

// A hung resolver must fail this test without holding the suite open.
const CYCLE_BOUND_MS = 5000;
const theme = { bg: "#000000", fg: "#ffffff", font: "monospace", bodyPx: 14 };
// Sample input: two custom properties refer back to each other inside one style block.
const cyclic = '<svg><style>svg { --a: var(--b); --b: var(--a); }</style><rect fill="var(--a)"/></svg>';
if (process.argv[2] === "cycle") {
    try {
        postMermaid(cyclic, theme);
        console.log("FAIL two-variable cycle did not refuse the SVG");
        process.exitCode = 1;
    } catch (error) {
        const passed = /cycle/i.test(error.message);
        console.log((passed ? "PASS " : "FAIL ") + "two-variable cycle refuses the SVG: " + error.message);
        process.exitCode = passed ? 0 : 1;
    }
} else {
    let checks = 0;
    let failures = 0;
    function check(passed, label) {
        checks++;
        failures += passed ? 0 : 1;
        console.log((passed ? "PASS " : "FAIL ") + label);
    }
    const child = spawnSync(process.execPath, [fileURLToPath(import.meta.url), "cycle"], { timeout: CYCLE_BOUND_MS, encoding: "utf8" });
    check(child.status === 0, "two-variable cycle refuses the SVG" + (child.error ? ": " + child.error.code : ": " + child.stdout.trim()));
    const shared = '<svg><style>svg { --a: #ffffff; --b: var(--a); --c: var(--a); }</style><rect fill="var(--b)" stroke="var(--c)"/></svg>';
    const rendered = postMermaid(shared, theme);
    check(rendered.includes('fill="#ffffff"') && rendered.includes('stroke="#ffffff"'), "shared acyclic variables resolve in both attributes");
    const mixed = postMermaid('<svg><rect fill="color-mix(in srgb, var(--fg) 25%, var(--bg))"/></svg>', theme);
    check(mixed.includes('fill="#404040"'), "nested variable stops resolve inside color-mix");
    const classes = postMermaid('<svg><style>rect.node { fill: var(--fg); stroke-width: 2; }</style><rect class="node"/></svg>', theme);
    check(classes.includes('fill="#ffffff"') && classes.includes('stroke-width="2"') && !classes.includes("<style>"), "style classes become SVG presentation attributes");
    check(postMath('<svg width="1.234ex" height="-2ex" fill="currentColor"/>', theme).includes('width="7.64px" height="-12.38px"'), "ex conversion uses MathJax's 0.442 em and rounds to hundredths");
    console.log(`figure-worker: ${checks} check(s), ${failures} failed`);
    process.exitCode = failures > 0 ? 1 : 0;
}
