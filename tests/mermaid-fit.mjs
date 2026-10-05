// No Mermaid label overflows: each label, measured as characters times the font's advance times its size, fits its shape and its lifelines.
import { ARROW_LABEL_PAD, FACES, bounds, extent, groups, labelWidth, layered, lifelines, load, notes, num, others, sequences, text, texts, theme, view } from "./mermaid-corpus.mjs";
import { argv, finish } from "./js-runtime.mjs";

const render = await load(argv[0]);
let checks = 0;
let failures = 0;
function check(ok, why) {
    checks++;
    if (!ok) {
        failures++;
        console.log("FAIL " + why);
    }
}
// The library's padding inside a node box, inside an actor box, inside a note, and beside a class or entity row; in px.
const NODE_PAD = 20;
const ACTOR_PAD = 16;
const NOTE_PAD = 12;
const ROW_PAD = 4;
// A tolerance for the float arithmetic of ELK's coordinates, in px.
const EPSILON = 0.01;
// The half stroke a drawn edge may reach past the canvas, in px.
const STROKE_PAD = 1;
const SELF_LOOP_WIDTH = 30;
const SELF_LABEL_GAP = 8;

function width(rect) { return rect[2] - rect[0]; }

for (const face of FACES) {
    const tag = ` on ${face.name}`;
    for (const [name, source] of [...layered, ...sequences, notes, ...others]) {
        const svg = render(source, face);
        const canvas = view(svg);
        for (const t of texts(svg)) {
            const [left, right] = extent(t, face);
            check(left >= canvas[0] - EPSILON && right <= canvas[0] + canvas[2] + EPSILON, `${name}${tag}: "${t.string}" stays inside the canvas, ${left.toFixed(1)} to ${right.toFixed(1)} of ${canvas[0]} to ${canvas[0] + canvas[2]}`);
        }
        // A box or a pill is drawn whole: the canvas holds every rect, less its stroke.
        for (const m of svg.matchAll(/<rect\b[^>]*>/g)) {
            const r = [num(m[0], "x"), num(m[0], "y"), num(m[0], "x") + num(m[0], "width"), num(m[0], "y") + num(m[0], "height")];
            check(r[0] >= canvas[0] - STROKE_PAD && r[1] >= canvas[1] - STROKE_PAD && r[2] <= canvas[0] + canvas[2] + STROKE_PAD && r[3] <= canvas[1] + canvas[3] + STROKE_PAD,
                `${name}${tag}: the rect ${r.map((v) => v.toFixed(1))} stays inside the canvas ${canvas}`);
        }
        for (const node of groups(svg, "node")) {
            const rect = bounds(node.body);
            for (const t of texts(node.body))
                check(labelWidth(t.string, t.size, face, t.bold) + 2 * NODE_PAD <= width(rect) + EPSILON, `${name}${tag}: node "${t.string}" fits its shape ${width(rect).toFixed(1)} wide`);
        }
        for (const label of groups(svg, "edge-label")) {
            const rect = bounds(label.body);
            for (const t of texts(label.body))
                check(labelWidth(t.string, t.size, face, t.bold) + 2 * ARROW_LABEL_PAD <= width(rect) + EPSILON, `${name}${tag}: edge label "${t.string}" fits its pill ${width(rect).toFixed(1)} wide`);
        }
        for (const group of groups(svg, "subgraph")) {
            const rect = bounds(group.body);
            for (const t of texts(group.body))
                check(extent(t, face)[1] <= rect[2] + EPSILON, `${name}${tag}: subgraph title "${t.string}" fits its frame`);
        }
        for (const actor of groups(svg, "actor")) {
            const rect = bounds(actor.body);
            for (const t of texts(actor.body))
                check(labelWidth(t.string, t.size, face, t.bold) + 2 * ACTOR_PAD <= width(rect) + EPSILON, `${name}${tag}: participant "${t.string}" fits its box ${width(rect)} wide`);
        }
        for (const note of groups(svg, "note")) {
            const rect = bounds(note.body);
            for (const t of texts(note.body))
                check(labelWidth(t.string, t.size, face, t.bold) + 2 * NOTE_PAD <= width(rect) + EPSILON, `${name}${tag}: note "${t.string}" fits its box ${width(rect)} wide`);
        }
        const lifelineXs = lifelines(svg).map((l) => l.x).sort((a, b) => a - b);
        for (const m of groups(svg, "message")) {
            const label = texts(m.body)[0];
            if (!label)
                continue;
            const w = labelWidth(label.string, label.size, face, label.bold);
            if (text(m.attrs, "data-self") === "true") {
                // Sample input: <path d="M140 120 L170 120 L170 140 L140 140" fill="none"/> is a loop leaving the lifeline at x 140.
                const loopX = lifelineXs.find((x) => Math.abs(x - num(m.body.match(/<path\b[^>]*>/)[0].replace(/ d="M([\d.]+) .*"/, ' x="$1"'), "x")) < EPSILON);
                const next = lifelineXs.find((x) => x > loopX + EPSILON);
                check(label.x === loopX + SELF_LOOP_WIDTH + SELF_LABEL_GAP, `${name}${tag}: self message "${label.string}" starts beside its loop`);
                check(next === undefined || label.x + w + ARROW_LABEL_PAD <= next + EPSILON, `${name}${tag}: self message "${label.string}" ends before the next lifeline ${next}`);
                continue;
            }
            const arrow = m.body.match(/<line\b[^>]*>/)[0];
            const apart = Math.abs(num(arrow, "x2") - num(arrow, "x1"));
            check(w + 2 * ARROW_LABEL_PAD <= apart + EPSILON, `${name}${tag}: message "${label.string}" (${w.toFixed(1)}) fits between its lifelines ${apart} apart`);
        }
        // A class box or an entity holds each of its rows between its own edges, and a row's texts do not overlap.
        for (const kind of ["class-node", "entity"]) {
            for (const box of groups(svg, kind)) {
                const rect = bounds(box.body);
                const rows = new Map();
                for (const t of texts(box.body)) {
                    const [left, right] = extent(t, face);
                    check(left >= rect[0] - EPSILON && right <= rect[2] + EPSILON, `${name}${tag}: ${kind} "${t.string}" stays inside its box ${rect[0].toFixed(1)} to ${rect[2].toFixed(1)}`);
                    rows.set(t.y, [...(rows.get(t.y) ?? []), [left, right, t.string]]);
                }
                // The size table is the theme font's, so a row drawn in any other face would be sized with the wrong table.
                for (const m of box.body.matchAll(/<(?:text|tspan)\b[^>]*>/g))
                    check(text(m[0], "font-family") === theme.font, `${name}${tag}: ${kind} row text is drawn in the theme font ${theme.font}, got ${text(m[0], "font-family")}`);
                for (const [, row] of rows) {
                    row.sort((a, b) => a[0] - b[0]);
                    for (let i = 1; i < row.length; i++)
                        check(row[i - 1][1] + ROW_PAD <= row[i][0] + EPSILON, `${name}${tag}: "${row[i - 1][2]}" and "${row[i][2]}" do not overlap in their row`);
                }
            }
        }
    }
}
console.log(`mermaid-fit: ${checks} check(s), ${failures} failed`);
finish(failures);
