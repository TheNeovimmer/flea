// Mermaid lays out as mermaid.js does: dagre's cycle breaking in flowcharts, the mirrored boxes and message spacing of a sequence.
import { FACES, bounds, edgePaths, groups, layered, lifelines, load, notes, num, sequences, text, texts } from "./mermaid-corpus.mjs";
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
const LAYOUT_FACE = FACES[0];
// A tolerance for the float arithmetic of ELK's coordinates, in px.
const EPSILON = 0.01;
// The gap between a message label's descent and its arrow stays at least this, so a label never sits on its arrow.
const MESSAGE_GAP_MIN = 2;
const DESCENT_RATIO = 0.3;

// Sample input: "A -->|Yes| B" reads the pair [A, B]; "A --> B --> C" reads two; "X ||--o{ Y : a" is an entity pair; the header line is skipped.
function readSource(source) {
    const order = [];
    const edges = [];
    const see = (id) => { if (!order.includes(id)) order.push(id); };
    const arrow = /\s*(?:-{2,}>|={2,}>|-{3,})(?:\|[^|]*\|)?\s*/;
    for (const line of source.split("\n").slice(1)) {
        if (/^(subgraph|end$|direction)/.test(line))
            continue;
        const relation = line.match(/^(\w+) \|\|--o\{ (\w+) : /);
        const ids = relation ? [relation[1], relation[2]] : line.split(arrow).map((piece) => piece.match(/^[A-Za-z0-9_]+/)[0]);
        ids.forEach(see);
        for (let i = 1; i < ids.length; i++)
            edges.push([ids[i - 1], ids[i]]);
    }
    return { order, edges };
}
// What each diagram kind draws: its node group, the attributes its edges carry, and the direction it flows.
function kindOf(source) {
    if (/^erDiagram/.test(source))
        return { node: "entity", edge: /<polyline class="er-relationship"([^>]*)>/g, ends: ["data-entity1", "data-entity2"], direction: "LR" };
    if (/^classDiagram/.test(source))
        return { node: "class-node", edge: /<(?:path|polyline) class="class-relationship"([^>]*)>/g, ends: ["data-from", "data-to"], direction: "TD" };
    return { node: "node", edge: /<(?:path|polyline) class="edge"([^>]*)>/g, ends: ["data-from", "data-to"], direction: (source.match(/^flowchart (\w+)/) ?? [0, "TD"])[1] };
}
// dagre's acyclic pass (dfsFAS): nodes in declaration order, out edges in declaration order, an edge to a node on the DFS stack is reversed.
function dagreReversed(order, edges) {
    const visited = new Set();
    const stack = new Set();
    const reversed = new Set();
    function dfs(v) {
        if (visited.has(v))
            return;
        visited.add(v);
        stack.add(v);
        for (const [from, to] of edges) {
            if (from !== v || from === to)
                continue;
            if (stack.has(to))
                reversed.add(from + ">" + to);
            else
                dfs(to);
        }
        stack.delete(v);
    }
    order.forEach(dfs);
    return reversed;
}

for (const [name, source] of layered) {
    const svg = render(source, LAYOUT_FACE);
    const { order, edges } = readSource(source);
    const { node: nodeGroup, edge: edgePattern, ends, direction } = kindOf(source);
    const box = new Map();
    for (const node of groups(svg, nodeGroup))
        box.set(text(node.attrs, "data-id"), bounds(node.body));
    const drawn = [...svg.matchAll(edgePattern)].map((m) => text(m[1], ends[0]) + ">" + text(m[1], ends[1])).sort();
    check(JSON.stringify(drawn) === JSON.stringify(edges.map((e) => e.join(">")).sort()), `${name}: the reader and the figure agree on the edge set, ${drawn.join(" ")}`);
    // Flow position along the direction: a larger value is later in the flow.
    const horizontal = direction === "LR" || direction === "RL";
    const sign = direction === "BT" || direction === "RL" ? -1 : 1;
    const span = (id) => horizontal ? [box.get(id)[0], box.get(id)[2]] : [box.get(id)[1], box.get(id)[3]];
    const start = (id) => sign > 0 ? span(id)[0] : -span(id)[1];
    const end = (id) => sign > 0 ? span(id)[1] : -span(id)[0];
    if (!edges.every((e) => e.every((id) => box.has(id)))) {
        check(false, `${name}: every edge end is a drawn node`);
        continue;
    }
    const against = new Set(edges.filter(([from, to]) => from !== to && start(to) < start(from)).map((e) => e.join(">")));
    const expected = dagreReversed(order, edges);
    check(JSON.stringify([...against].sort()) === JSON.stringify([...expected].sort()),
        `${name}: edges drawn against the flow [${[...against].sort()}] equal dagre's reversed set [${[...expected].sort()}]`);
    for (const [from, to] of edges) {
        if (from === to || expected.has(from + ">" + to))
            continue;
        check(start(to) > end(from) - EPSILON, `${name}: ${to} sits in a layer after its predecessor ${from}`);
    }
    // A forward edge never doubles back: along the flow, each point of its line is no earlier than the one before.
    if (nodeGroup === "node") {
        for (const drawnEdge of edgePaths(svg)) {
            if (expected.has(drawnEdge.from + ">" + drawnEdge.to) || drawnEdge.from === drawnEdge.to)
                continue;
            const along = drawnEdge.points.map((p) => sign * (horizontal ? p[0] : p[1]));
            check(along.every((v, i) => i === 0 || v >= along[i - 1] - EPSILON), `${name}: the forward edge ${drawnEdge.from} to ${drawnEdge.to} runs one way along the flow, ${along.map((v) => v.toFixed(0))}`);
        }
    }
}

// A note stands beside its lifeline within this, in px; mermaid's own margin is 25.
const NOTE_BESIDE_MAX = 40;
const noteSvg = render(notes[1], LAYOUT_FACE);
const lifelineX = new Map(lifelines(noteSvg).map((l) => [l.id, l.x]));
for (const note of groups(noteSvg, "note")) {
    const [left, , right] = bounds(note.body);
    const ids = text(note.attrs, "data-actors").split(",");
    const position = text(note.attrs, "data-position");
    const first = lifelineX.get(ids[0]);
    const last = lifelineX.get(ids[ids.length - 1]);
    const name = `note "${texts(note.body)[0].string}"`;
    if (position === "over" && ids.length > 1) {
        check(left < first && right > last, `${name} spans lifeline ${ids[0]} at ${first} to ${ids[ids.length - 1]} at ${last}, drawn ${left} to ${right}`);
        const outside = [...lifelineX.values()].filter((x) => x < first - EPSILON || x > last + EPSILON);
        check(outside.every((x) => x < left || x > right), `${name} covers no lifeline outside its own`);
    } else if (position === "over") {
        check(Math.abs((left + right) / 2 - first) < EPSILON, `${name} is centred on its lifeline ${first}, drawn ${left} to ${right}`);
    } else if (position === "left") {
        check(right < first && first - right <= NOTE_BESIDE_MAX, `${name} sits left of its lifeline ${first}, ending at ${right}`);
    } else {
        check(left > first && left - first <= NOTE_BESIDE_MAX, `${name} sits right of its lifeline ${first}, starting at ${left}`);
    }
}

const BOX_GROUP = "actor";
for (const [name, source] of sequences) {
    const svg = render(source, LAYOUT_FACE);
    // Sample input: "participant A as Alice" reads the id A.
    const ids = [...new Set(source.split("\n").filter((l) => /^participant/.test(l)).map((l) => l.split(" ")[1]))];
    const actors = groups(svg, BOX_GROUP);
    const lines = lifelines(svg);
    check(actors.length === ids.length * 2, `${name}: ${ids.length} participants draw ${actors.length} boxes, want one top and one bottom each`);
    for (const id of ids) {
        const own = actors.filter((a) => text(a.attrs, "data-id") === id).map((a) => ({ a, r: bounds(a.body), t: texts(a.body)[0] })).sort((p, q) => p.r[1] - q.r[1]);
        const line = lines.find((l) => l.id === id);
        check(own.length === 2, `${name}: ${id} has a top and a bottom box`);
        if (own.length !== 2)
            continue;
        const [top, bottom] = own;
        check(top.r[2] - top.r[0] === bottom.r[2] - bottom.r[0] && top.r[3] - top.r[1] === bottom.r[3] - bottom.r[1], `${name}: ${id}'s bottom box has the size of its top box`);
        check(top.r[0] === bottom.r[0] && top.t.string === bottom.t.string && top.t.x === bottom.t.x, `${name}: ${id}'s bottom box has the label and column of its top box`);
        check(Math.abs(bottom.r[1] - line.end) < EPSILON, `${name}: ${id}'s bottom box begins where its lifeline ends, ${bottom.r[1]} against ${line.end}`);
    }
    for (const m of groups(svg, "message")) {
        const label = texts(m.body)[0];
        const arrow = m.body.match(/<line\b[^>]*>/);
        if (!arrow || !label)
            continue;
        const y = num(arrow[0], "y1");
        check(label.y + DESCENT_RATIO * label.size <= y - MESSAGE_GAP_MIN, `${name}: "${label.string}" sits above its arrow, baseline ${label.y} against ${y}`);
    }
}
console.log(`mermaid-layout: ${checks} check(s), ${failures} failed`);
finish(failures);
