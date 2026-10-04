// The Mermaid test corpus, and the readers the layout and fit checks share: one render through the real figure path, SVG parts as numbers.
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

export const ARROW_LABEL_PAD = 8;
// Em advances the fit checks run at: JetBrains Mono, and a narrower monospace face.
export const ADVANCES = [0.6, 0.5];
const theme = { bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 13 };

// Graphs whose edges the layering check reads back; fixture 10 is first, then mermaid's own docs examples, cycles, and the state, class and ER layouts.
export const layered = [
    ["fixture 10", "flowchart TD\nA[Start] --> B{Is it working?}\nB -->|Yes| C[Ship it]\nB -->|No| D[Debug]\nD --> B\nC --> E((Done))"],
    ["docs loop", "flowchart TD\nA[Start] --> B{Is it?}\nB -->|Yes| C[OK]\nC --> D[Rethink]\nD --> B\nB -->|No| E[End]"],
    ["docs subgraphs", "flowchart TB\nc1 --> a2\nsubgraph one\na1 --> a2\nend\nsubgraph two\nb1 --> b2\nend\nsubgraph three\nc1 --> c2\nend"],
    ["nested subgraphs", "flowchart TB\nsubgraph outer [Outer]\nsubgraph inner [Inner]\na1 --> a2\nend\na2 --> b1\nb1 --> a1\nend\ns --> a1\nb1 --> t"],
    ["branches and a join", "flowchart TD\nS --> A\nA --> B\nA --> C\nB --> D\nC --> D\nD --> A\nD --> E"],
    ["late source", "flowchart TD\nB --> C\nC --> D\nD --> B\nA --> C"],
    ["left to right back edges", "flowchart LR\nA --> B --> C --> D\nD --> B\nC --> A"],
    ["bottom to top triangle", "flowchart BT\nX --> Y\nY --> Z\nZ --> X\nY --> W"],
    ["two loops one entry", "flowchart RL\nIn --> P\nP --> Q\nQ --> P\nQ --> R\nR --> S\nS --> Q\nS --> Out"],
    ["plain dag", "flowchart TD\nA --> B\nA --> C\nB --> D\nC --> D"],
    ["state loop", "stateDiagram-v2\nStart --> Check\nCheck --> Ship\nCheck --> Debug\nDebug --> Check\nShip --> End"],
    ["state late source", "stateDiagram-v2\nB --> C\nC --> D\nD --> B\nA --> C"],
    ["class loop", "classDiagram\nA --> B\nB --> C\nB --> D\nD --> B\nC --> E"],
    ["class late source", "classDiagram\nB --> C\nC --> D\nD --> B\nA --> C"],
    ["er loop", "erDiagram\nA ||--o{ B : a\nB ||--o{ C : b\nB ||--o{ D : c\nD ||--o{ B : d\nC ||--o{ E : e"],
    ["er late source", "erDiagram\nB ||--o{ C : a\nC ||--o{ D : b\nD ||--o{ B : c\nA ||--o{ C : d"]
];

export const sequences = [
    ["fixture 11", "sequenceDiagram\nparticipant A as Alice\nparticipant B as Bob\nA->>B: Hello Bob, how are you?\nB-->>A: Fine, thanks\nA->>B: See you later"],
    ["long message and a note", "sequenceDiagram\nparticipant A as Alice\nparticipant B as Bob\nA->>B: A very long message that needs the lifelines far apart\nNote over A,B: A note over both lifelines\nB-->>A: ok"],
    ["three participants and a self message", "sequenceDiagram\nparticipant U as User\nparticipant S as Server\nparticipant D as Database\nU->>S: request the report\nS->>S: validate the session token\nS->>D: select rows\nD-->>U: rows straight back to the user"]
];

// Other kinds join the fit check only; the layering reference is flowchart syntax.
export const others = [
    ["state", "stateDiagram-v2\n[*] --> Still\nStill --> Moving: go and keep going\nMoving --> Still\nMoving --> Crash\nCrash --> [*]"],
    ["class", "classDiagram\nclass Animal {\n+String name\n+makeSound() void\n}\nclass Duck {\n+swim() void\n}\nAnimal <|-- Duck : extends"],
    ["er", "erDiagram\nCUSTOMER ||--o{ ORDER : places\nCUSTOMER {\nstring name PK\nstring email\n}\nORDER {\nint number PK\n}"]
];

// Load the renderer pair of one tree, so the same checks run on a scratch copy of an older commit.
export async function load(root) {
    globalThis.global = globalThis;
    const base = resolve(root || new URL("..", import.meta.url).pathname);
    const worker = await import(pathToFileURL(resolve(base, "ui/js/FigureWorker.mjs")));
    const api = await import(pathToFileURL(resolve(base, "ui/vendor/mermaid.mjs")));
    return (source, advance) => worker.renderFigure("mermaid", source, false, { ...theme, advance, boldAdvance: advance }, api);
}

// Sample input: &lt;b&gt; reads <b>.
export function decode(text) {
    return text.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&");
}
// Sample input: <rect x="3" width="40"/> answers 40 for "width", or NaN.
export function num(tag, name) {
    const found = tag.match(new RegExp("\\s" + name + '="([^"]*)"'));
    return found ? Number(found[1]) : NaN;
}
export function text(tag, name) {
    const found = tag.match(new RegExp("\\s" + name + '="([^"]*)"'));
    return found ? decode(found[1]) : "";
}
// Sample input: <g class="node" data-id="A">...\n</g> reads attrs ' data-id="A"' and its body; a nested group closes indented, so only the outer closes at column 0.
export function groups(svg, cls) {
    const found = [];
    svg.replace(new RegExp('<g class="' + cls + '"([^>]*)>([\\s\\S]*?)\\n</g>', "g"), (all, attrs, body) => found.push({ attrs, body }));
    return found;
}
// The text elements of a body with their anchor, font size and plain content.
export function texts(body) {
    const found = [];
    body.replace(/<text\b([^>]*)>([\s\S]*?)<\/text>/g, (all, attrs, content) => {
        found.push({ x: num(attrs, "x"), y: num(attrs, "y"), size: num(attrs, "font-size"), anchor: text(attrs, "text-anchor") || "start",
            string: decode(content.replace(/<[^>]*>/g, "")) });
    });
    return found;
}
// Sample input: a 5 character label at 0.6 em and 13 px reaches 39, the library's measure with no padding.
export function labelWidth(string, size, advance) {
    return Array.from(string).length * advance * size;
}
// The bounding box [left, top, right, bottom] of the first shape in a body, or null.
export function bounds(body) {
    const rect = body.match(/<rect\b[^>]*>/);
    if (rect) {
        const x = num(rect[0], "x"), y = num(rect[0], "y");
        return [x, y, x + num(rect[0], "width"), y + num(rect[0], "height")];
    }
    const poly = body.match(/<polygon\b[^>]*points="([^"]*)"/);
    if (poly) {
        const p = poly[1].trim().split(/[\s,]+/).map(Number);
        const xs = p.filter((v, i) => i % 2 === 0), ys = p.filter((v, i) => i % 2 === 1);
        return [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
    }
    const circles = [...body.matchAll(/<circle\b[^>]*>/g)].map((m) => [num(m[0], "cx"), num(m[0], "cy"), num(m[0], "r")]);
    if (circles.length === 0)
        return null;
    const r = Math.max(...circles.map((c) => c[2]));
    return [circles[0][0] - r, circles[0][1] - r, circles[0][0] + r, circles[0][1] + r];
}
// A text's [left, right] by anchor and measured width.
export function extent(t, advance) {
    const w = labelWidth(t.string, t.size, advance);
    return t.anchor === "middle" ? [t.x - w / 2, t.x + w / 2] : t.anchor === "end" ? [t.x - w, t.x] : [t.x, t.x + w];
}
// The viewBox [x, y, width, height] of a figure.
export function view(svg) {
    return svg.match(/<svg\b[^>]*>/)[0].match(/viewBox="([^"]*)"/)[1].split(/\s+/).map(Number);
}
