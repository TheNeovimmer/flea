// Exercise SVG post-processing directly, with the cyclic fixture confined to a child process.
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { postMermaid, postMath, renderFigure } from "../ui/js/FigureWorker.mjs";

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
    // Sample input: MathJax's x^2 SVG, 2.025ex tall over a 894.9 unit viewBox at 442 units per ex.
    const formula = '<svg width="2.282ex" height="2.025ex" viewBox="0 -883.9 1008.6 894.9"><path fill="currentColor"/></svg>';
    const MATH_UNITS_PER_EX = 442;
    const EX_PER_EM = 0.442;
    // The exPx path is exact up to the hundredth-pixel rounding of the drawn height, so one percent leaves the 1.2 em rule (3.6% off at 12 and 14) red.
    const EX_PATH_TOLERANCE = 0.01;
    // The ex the formula takes through the helper's own entry point, read back from its height, or NaN when no pixel height was written.
    function drawnExPx(theme, display) {
        let asked = null;
        const svg = renderFigure("math", "x^2", display, theme, { texToSvg: (source, wantDisplay) => { asked = wantDisplay; return formula; } });
        check(asked === display, `a ${display ? "display" : "inline"} formula reaches MathJax as ${display ? "display" : "inline"}, asked ${asked}`);
        const match = svg.match(/height="([\d.]+)px"/);
        return match ? Number(match[1]) / (894.9 / MATH_UNITS_PER_EX) : NaN;
    }
    function exMatches(drawn, expected) {
        return Math.abs(drawn - expected) <= EX_PATH_TOLERANCE * expected;
    }
    // An inline and a display formula both take the body font's measured x-height at any body size, so each stands level with the prose.
    for (const display of [false, true]) {
        const kind = display ? "display" : "inline";
        for (const [bodyPx, xHeight] of [[12, 6.6], [14, 7.7], [14, 9]]) {
            const exPx = drawnExPx({ fg: "#ffffff", bodyPx, exPx: xHeight }, display);
            check(exMatches(exPx, xHeight), `${kind} maths ex ${exPx.toFixed(2)}px follows the body x-height ${xHeight}px at body ${bodyPx}px`);
        }
        // Without a measured x-height the em rule stays.
        const EM_BODY_PX = 14;
        const EM_RULE_EX_PX = EM_BODY_PX * EX_PER_EM;
        const fallbackEx = drawnExPx({ fg: "#ffffff", bodyPx: EM_BODY_PX }, display);
        check(exMatches(fallbackEx, EM_RULE_EX_PX), `${kind} maths ex ${fallbackEx.toFixed(2)}px falls back to the em rule ${EM_RULE_EX_PX.toFixed(2)}px without a measured x-height`);
    }
    console.log(`figure-worker: ${checks} check(s), ${failures} failed`);
    process.exitCode = failures > 0 ? 1 : 0;
}
