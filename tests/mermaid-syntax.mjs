// Mermaid's flowchart syntax reads as mermaid.js reads it: every documented link form, and which subgraph a node belongs to.
import { FACES, bounds, frame, groups, load, num, text } from "./mermaid-corpus.mjs";
import { argv, finish } from "./js-runtime.mjs";

const render = await load(argv[0]);
const face = FACES[0];
let checks = 0;
let failures = 0;
function check(ok, why) {
    checks++;
    if (!ok) {
        failures++;
        console.log("FAIL " + why);
    }
}
// A tolerance for the float arithmetic of ELK's coordinates, in px.
const EPSILON = 0.01;
// A link one rank longer must sit at least this much further from its source, in px; the library's layer spacing is 48.
const RANK_STEP_MIN = 40;
// The stroke widths of a plain and a thick link, in px.
const PLAIN_WIDTH = 1;
const THICK_WIDTH = 2;

const edge = (from, to, style, start, end, length = 1, label = "") => ({ from, to, style, start, end, length, label });
// Every documented link form of mermaid's flowchart docs: [source, the edges it draws].
const forms = [
    ["A --> B", [edge("A", "B", "solid", "none", "arrow")]],
    ["A --- B", [edge("A", "B", "solid", "none", "none")]],
    ["A -->|t| B", [edge("A", "B", "solid", "none", "arrow", 1, "t")]],
    ["A ---|t| B", [edge("A", "B", "solid", "none", "none", 1, "t")]],
    ["A -- t --> B", [edge("A", "B", "solid", "none", "arrow", 1, "t")]],
    ["A -- t --- B", [edge("A", "B", "solid", "none", "none", 1, "t")]],
    ["A-- text with spaces -->B", [edge("A", "B", "solid", "none", "arrow", 1, "text with spaces")]],
    ["A-->B", [edge("A", "B", "solid", "none", "arrow")]],
    ["my-node --> other-node", [edge("my-node", "other-node", "solid", "none", "arrow")]],
    ["A -.-> B", [edge("A", "B", "dotted", "none", "arrow")]],
    ["A -.- B", [edge("A", "B", "dotted", "none", "none")]],
    ["A -. t .-> B", [edge("A", "B", "dotted", "none", "arrow", 1, "t")]],
    ["A -. t .- B", [edge("A", "B", "dotted", "none", "none", 1, "t")]],
    ["A ==> B", [edge("A", "B", "thick", "none", "arrow")]],
    ["A === B", [edge("A", "B", "thick", "none", "none")]],
    ["A == t ==> B", [edge("A", "B", "thick", "none", "arrow", 1, "t")]],
    ["A == t === B", [edge("A", "B", "thick", "none", "none", 1, "t")]],
    ["A ---> B", [edge("A", "B", "solid", "none", "arrow", 2)]],
    ["A ----> B", [edge("A", "B", "solid", "none", "arrow", 3)]],
    ["A ----- B", [edge("A", "B", "solid", "none", "none", 3)]],
    ["A -..-> B", [edge("A", "B", "dotted", "none", "arrow", 2)]],
    ["A -...-> B", [edge("A", "B", "dotted", "none", "arrow", 3)]],
    ["A ===> B", [edge("A", "B", "thick", "none", "arrow", 2)]],
    ["A ==== B", [edge("A", "B", "thick", "none", "none", 2)]],
    ["A --->|t| B", [edge("A", "B", "solid", "none", "arrow", 2, "t")]],
    ["A <--> B", [edge("A", "B", "solid", "arrow", "arrow")]],
    ["A <-.-> B", [edge("A", "B", "dotted", "arrow", "arrow")]],
    ["A <==> B", [edge("A", "B", "thick", "arrow", "arrow")]],
    ["A --o B", [edge("A", "B", "solid", "none", "circle")]],
    ["A --x B", [edge("A", "B", "solid", "none", "cross")]],
    ["A o--o B", [edge("A", "B", "solid", "circle", "circle")]],
    ["A x--x B", [edge("A", "B", "solid", "cross", "cross")]],
    ["A & B --> C", [edge("A", "C", "solid", "none", "arrow"), edge("B", "C", "solid", "none", "arrow")]],
    ["A --> B & C", [edge("A", "B", "solid", "none", "arrow"), edge("A", "C", "solid", "none", "arrow")]],
    ["A & B -->|t| C & D", ["A", "B"].flatMap((s) => ["C", "D"].map((d) => edge(s, d, "solid", "none", "arrow", 1, "t")))],
    ["A --> B == t ==> C", [edge("A", "B", "solid", "none", "arrow"), edge("B", "C", "thick", "none", "arrow", 1, "t")]],
    ["A ~~~ B", []]
];

// Sample input: <polyline class="edge" data-from="A" data-to="B" data-style="dotted" data-arrow-start="false" data-end-mark="circle" stroke-width="1" stroke-dasharray="4 4" /> reads the edge A to B.
function drawnEdges(svg) {
    return [...svg.matchAll(/<(?:path|polyline) class="edge"([^>]*)>/g)].map((m) => ({ from: text(m[1], "data-from"), to: text(m[1], "data-to"),
        style: text(m[1], "data-style"), start: text(m[1], "data-start-mark"), end: text(m[1], "data-end-mark"), label: text(m[1], "data-label"),
        width: num(m[1], "stroke-width"), dashed: m[1].includes("stroke-dasharray") }));
}
const key = (e) => [e.from, e.to, e.style, e.start, e.end, e.label].join(" ");
for (const [source, want] of forms) {
    const svg = render("flowchart TD\n" + source, face);
    const drawn = drawnEdges(svg);
    check(JSON.stringify(drawn.map(key).sort()) === JSON.stringify(want.map(key).sort()),
        `${source}: draws [${drawn.map(key).join("; ")}], want [${want.map(key).join("; ")}]`);
    check(drawn.every((e) => (e.style === "dotted") === e.dashed && e.width === (e.style === "thick" ? THICK_WIDTH : PLAIN_WIDTH)),
        `${source}: dotted is dashed and thick is heavier`);
    const labels = groups(svg, "edge-label").map((g) => text(g.attrs, "data-label"));
    check(JSON.stringify(labels.sort()) === JSON.stringify(want.map((e) => e.label).filter((l) => l !== "").sort()), `${source}: labels [${labels}]`);
    const nodes = groups(svg, "node").map((g) => text(g.attrs, "data-id")).sort();
    const wantNodes = want.length === 0 ? ["A", "B"] : [...new Set(want.flatMap((e) => [e.from, e.to]))].sort();
    check(JSON.stringify(nodes) === JSON.stringify(wantNodes), `${source}: nodes [${nodes}], want [${wantNodes}]`);
}

// How far node B sits below node A, in px, in a top-down graph.
function drop(link) {
    const svg = render("flowchart TD\nA " + link + " B", face);
    const box = new Map(groups(svg, "node").map((g) => [text(g.attrs, "data-id"), bounds(g.body)]));
    return box.has("A") && box.has("B") ? box.get("B")[1] - box.get("A")[3] : NaN;
}
// A longer link spans more ranks: each extra dash, dot or equals sign moves the target a rank further down.
for (const [family, links] of [["solid", ["-->", "--->", "---->", "----->"]], ["dotted", ["-.->", "-..->", "-...->"]], ["thick", ["==>", "===>", "====>"]]]) {
    const drops = links.map(drop);
    for (let i = 1; i < drops.length; i++)
        check(drops[i] >= drops[0] + i * RANK_STEP_MIN - EPSILON, `${family} link ${links[i]} drops ${drops[i].toFixed(1)}, want at least ${(drops[0] + i * RANK_STEP_MIN).toFixed(1)} beyond ${links[0]} at ${drops[0].toFixed(1)}`);
}
// The edge a longer link draws is one unbroken line from its source to its target, not one piece per rank.
const longEdge = render("flowchart TD\nA ------> B", face).match(/<(?:path|polyline) class="edge"[^>]*>/g);
check(longEdge !== null && longEdge.length === 1, `a long link draws one edge, got ${longEdge === null ? 0 : longEdge.length}`);
// An invisible link orders its ends and draws nothing.
const invisible = render("flowchart TD\nA ~~~ B", face);
const invisibleBoxes = new Map(groups(invisible, "node").map((g) => [text(g.attrs, "data-id"), bounds(g.body)]));
check(invisibleBoxes.has("B") && invisibleBoxes.get("A")[3] <= invisibleBoxes.get("B")[1] + EPSILON, "an invisible link still ranks B below A");

// A node belongs to the first subgraph whose block closes with it named, as mermaid's flowDb keeps it; an earlier mention outside any block does not count.
const subgraphs = [
    ["docs example", "flowchart TB\nc1 --> a2\nsubgraph one\na1 --> a2\nend\nsubgraph two\nb1 --> b2\nend\nsubgraph three\nc1 --> c2\nend",
        { one: ["a1", "a2"], two: ["b1", "b2"], three: ["c1", "c2"] }],
    ["a node named in two sibling blocks", "flowchart TB\nsubgraph s1\nx --> y\nend\nsubgraph s2\ny --> z\nend",
        { s1: ["x", "y"], s2: ["z"] }],
    ["a node named outside, then in a block", "flowchart LR\nlone --> p\nsubgraph box\nq\np\nend\nlone --> q",
        { box: ["p", "q"] }],
    ["an inner block takes a node its outer block names", "flowchart TB\nsubgraph outer\nn --> m\nsubgraph inner\nm --> k\nend\nend",
        { outer: ["n", "m", "k"], inner: ["m", "k"] }]
];
for (const [name, source, members] of subgraphs) {
    const svg = render(source, face);
    const box = new Map(groups(svg, "node").map((g) => [text(g.attrs, "data-id"), bounds(g.body)]));
    for (const [id, nodes] of Object.entries(members)) {
        const outline = frame(svg, id);
        check(outline !== null, `${name}: subgraph ${id} is drawn`);
        if (outline === null)
            continue;
        for (const node of box.keys()) {
            const b = box.get(node);
            const inside = b[0] >= outline[0] - EPSILON && b[1] >= outline[1] - EPSILON && b[2] <= outline[2] + EPSILON && b[3] <= outline[3] + EPSILON;
            check(inside === nodes.includes(node), `${name}: ${node} ${inside ? "sits in" : "sits outside"} subgraph ${id}, want ${nodes.includes(node) ? "inside" : "outside"}`);
        }
    }
}
// A later bare mention of a node keeps the shape and label its first definition gave it, as mermaid.js keeps them.
const mentions = [
    ["a bare mention after a diamond", "flowchart TD\nA[Start] --> B{Is it?}\nB --> C", { B: ["diamond", "Is it?"], C: ["rectangle", "C"] }],
    ["docs link length, D --> B after the diamond", "flowchart TD\nA[Start] --> B{Is it?}\nB -->|Yes| C[OK]\nC --> D[Rethink]\nD --> B\nB ----->|No| E[End]", { B: ["diamond", "Is it?"], D: ["rectangle", "Rethink"] }]
];
for (const [name, source, expected] of mentions) {
    const svg = render(source, face);
    for (const [id, [shape, label]] of Object.entries(expected)) {
        const node = groups(svg, "node").find((g) => text(g.attrs, "data-id") === id);
        check(node !== undefined && text(node.attrs, "data-shape") === shape && text(node.attrs, "data-label") === label,
            `${name}: ${id} keeps ${shape} "${label}", got ${node === undefined ? "nothing" : text(node.attrs, "data-shape") + ' "' + text(node.attrs, "data-label") + '"'}`);
    }
}
console.log(`mermaid-syntax: ${checks} check(s), ${failures} failed`);
finish(failures);
