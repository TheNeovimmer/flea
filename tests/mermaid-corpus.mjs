// The Mermaid test corpus, and the readers the layout and fit checks share: one render through the real figure path, SVG parts as numbers.
import { absolute, importFile, prepareEngine, repoRoot, resolve } from "./js-runtime.mjs";

export const ARROW_LABEL_PAD = 8;
// A face is a per-character advance table for printable ASCII, 32 to 126, in thousandths of an em, regular and bold.
const TABLE_FIRST = 32;
const TABLE_LENGTH = 95;
const THOUSAND = 1000;
function flat(em) {
    return Array(TABLE_LENGTH).fill(Math.round(em * THOUSAND));
}
// A proportional face: narrow strokes, narrow punctuation, wide capitals and the widest letters, so a mean over the table fits none of them.
const NARROW_GLYPHS = "il.,:;'|!`jI";
const SLIM_GLYPHS = "frt()[]{} -\"/\\";
const WIDEST_GLYPHS = "mwMW@%";
const GLYPH_EM = { narrow: 0.25, slim: 0.36, widest: 0.92, capital: 0.68, digit: 0.62, other: 0.56 };
const BOLD_WIDENING = 1.1;
function proportional() {
    return Array.from({ length: TABLE_LENGTH }, (unused, i) => {
        const ch = String.fromCharCode(TABLE_FIRST + i);
        const em = NARROW_GLYPHS.includes(ch) ? GLYPH_EM.narrow : SLIM_GLYPHS.includes(ch) ? GLYPH_EM.slim : WIDEST_GLYPHS.includes(ch) ? GLYPH_EM.widest
            : /[A-Z]/.test(ch) ? GLYPH_EM.capital : /[0-9]/.test(ch) ? GLYPH_EM.digit : GLYPH_EM.other;
        return Math.round(em * THOUSAND);
    });
}
// The faces the fit checks run at: JetBrains Mono, a narrower monospace, a monospace whose bold is wider, and a proportional face.
const regularProportional = proportional();
export const FACES = [
    { name: "mono 0.6", regular: flat(0.6), bold: flat(0.6) },
    { name: "mono 0.5", regular: flat(0.5), bold: flat(0.5) },
    { name: "mono 0.6 bold 0.7", regular: flat(0.6), bold: flat(0.7) },
    { name: "proportional", regular: regularProportional, bold: regularProportional.map((v) => Math.round(v * BOLD_WIDENING)) }
];
export const theme = { bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 13 };

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
    ["docs link length", "flowchart TD\nA[Start] --> B{Is it?}\nB -->|Yes| C[OK]\nC --> D[Rethink]\nD --> B\nB ----->|No| E[End]"],
    ["wide and narrow glyphs", "flowchart LR\nA[WWW MMM WWW] --> B[illi lilii lil]\nB --> C[你好 世界]\nC --> A"],
    ["state loop", "stateDiagram-v2\nStart --> Check\nCheck --> Ship\nCheck --> Debug\nDebug --> Check\nShip --> End"],
    ["state late source", "stateDiagram-v2\nB --> C\nC --> D\nD --> B\nA --> C"],
    ["class loop", "classDiagram\nA --> B\nB --> C\nB --> D\nD --> B\nC --> E"],
    ["class late source", "classDiagram\nB --> C\nC --> D\nD --> B\nA --> C"],
    ["er loop", "erDiagram\nA ||--o{ B : a\nB ||--o{ C : b\nB ||--o{ D : c\nD ||--o{ B : d\nC ||--o{ E : e"],
    ["er late source", "erDiagram\nB ||--o{ C : a\nC ||--o{ D : b\nD ||--o{ B : c\nA ||--o{ C : d"]
];

// Notes in every form, over two and three lifelines, beside the first and the last, and over one.
export const notes = ["notes in every form",
    "sequenceDiagram\nparticipant A as Alice\nparticipant B as Bob\nparticipant C as Carol\nA->>C: hello\nNote over A,C: spans all three\nNote over A,B: spans two\nNote left of A: left of Alice\nNote right of C: right of Carol\nNote over B: only Bob\nNote right of A: right of Alice\nNote over B,C: a long note over two lifelines that needs them far apart"];

export const sequences = [
    ["fixture 11", "sequenceDiagram\nparticipant A as Alice\nparticipant B as Bob\nA->>B: Hello Bob, how are you?\nB-->>A: Fine, thanks\nA->>B: See you later"],
    ["long message and a note", "sequenceDiagram\nparticipant A as Alice\nparticipant B as Bob\nA->>B: A very long message that needs the lifelines far apart\nNote over A,B: A note over both lifelines\nB-->>A: ok"],
    ["wide and narrow glyphs", "sequenceDiagram\nparticipant W as WWW MMM\nparticipant I as illi lilii\nW->>I: WMWMW MWMWM WMWM\nI-->>W: iiiiillll lllii\nNote over W,I: WMWM MWMW iiii llll"],
    ["three participants and a self message", "sequenceDiagram\nparticipant U as User\nparticipant S as Server\nparticipant D as Database\nU->>S: request the report\nS->>S: validate the session token\nS->>D: select rows\nD-->>U: rows straight back to the user"]
];

// Other kinds join the fit check only; the layering reference is flowchart syntax.
export const others = [
    ["state", "stateDiagram-v2\n[*] --> Still\nStill --> Moving: go and keep going\nMoving --> Still\nMoving --> Crash\nCrash --> [*]"],
    ["bold headers", "classDiagram\nclass AVeryLongClassNameWiderThanTheMinimumBox {\n+id\n}\nAVeryLongClassNameWiderThanTheMinimumBox --> B"],
    ["bold entity header", "erDiagram\nA_VERY_LONG_ENTITY_NAME_FOR_THE_HEADER ||--o{ B : has\nA_VERY_LONG_ENTITY_NAME_FOR_THE_HEADER {\nint id PK\n}"],
    ["bold subgraph title", "flowchart TD\nsubgraph t [A subgraph title much wider than its one small node]\nx\nend"],
    ["flattened frames, docs example", "flowchart TB\nc1 --> a2\nsubgraph one\na1 --> a2\nend\nsubgraph two\nb1 --> b2\nend\nsubgraph three\nc1 --> c2\nend"],
    ["flattened nested frames", "flowchart TB\nsubgraph outer\nsubgraph inner\nm --> k\nend\nn --> m\nend\nk --> z"],
    ["left to right subgraph title", "flowchart LR\nsubgraph t [A subgraph title much wider than its two small nodes]\nx --> y\nend"],
    ["right to left subgraph title", "flowchart RL\nsubgraph t [A subgraph title much wider than its two small nodes]\nx --> y\nend\ny --> z"],
    ["class", "classDiagram\nclass Animal {\n+String name\n+makeSound() void\n}\nclass Duck {\n+swim() void\n}\nAnimal <|-- Duck : extends"],
    ["er", "erDiagram\nCUSTOMER ||--o{ ORDER : places\nCUSTOMER {\nstring name PK\nstring email\n}\nORDER {\nint number PK\n}"]
];

// Load the renderer pair of one tree, so the same checks run on a scratch copy of an older commit.
export async function load(root) {
    prepareEngine();
    const base = root ? absolute(root) : repoRoot(import.meta.url);
    const worker = await importFile(resolve(base, "ui/js/FigureWorker.mjs"));
    const api = await importFile(resolve(base, "ui/vendor/mermaid.mjs"));
    return (source, face) => worker.renderFigure("mermaid", source, false, { ...theme, advances: face.regular, boldAdvances: face.bold }, api);
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
// Sample input: <g data-label="a &amp; b"> answers "a & b" for "data-label", or an empty string.
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
// The text elements of a body with their anchor, font size, weight and plain content.
// Sample input: <text x="10" y="20" text-anchor="middle" font-size="13" font-weight="700">Animal</text> reads anchor middle, size 13, bold.
export function texts(body) {
    const found = [];
    body.replace(/<text\b([^>]*)>([\s\S]*?)<\/text>/g, (all, attrs, content) => {
        found.push({ x: num(attrs, "x"), y: num(attrs, "y"), size: num(attrs, "font-size"), bold: num(attrs, "font-weight") >= BOLD_WEIGHT,
            anchor: text(attrs, "text-anchor") || "start", string: decode(content.replace(/<[^>]*>/g, "")) });
    });
    return found;
}
// The weight from which the library measures with the bold table.
const BOLD_WEIGHT = 600;
// Sample input: "WM" at 10 px on a face whose W and M are 0.92 em reaches 18.4; a character past ASCII counts the table's mean, a CJK one twice that.
export function labelWidth(string, size, face, bold) {
    const table = bold ? face.bold : face.regular;
    const mean = table.reduce((sum, v) => sum + v, 0) / table.length;
    const CJK_FIRST = 0x2e80;
    let total = 0;
    for (const ch of string) {
        const code = ch.codePointAt(0);
        total += code >= TABLE_FIRST && code < TABLE_FIRST + TABLE_LENGTH ? table[code - TABLE_FIRST] : code >= CJK_FIRST ? 2 * mean : mean;
    }
    return total / THOUSAND * size;
}
// The bounding box [left, top, right, bottom] of the first shape in a body, or null.
// Sample input: <rect x="3" y="4" width="40" height="20"/> reads [3, 4, 43, 24]; a polygon reads its points' extremes, a circle its radius.
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
export function extent(t, face) {
    const w = labelWidth(t.string, t.size, face, t.bold);
    return t.anchor === "middle" ? [t.x - w / 2, t.x + w / 2] : t.anchor === "end" ? [t.x - w, t.x] : [t.x, t.x + w];
}
// The drawn edges of a flowchart-like diagram with their points; the library writes a polyline, and the figure path turns an arrowed one into a path.
// Sample input: <path class="edge" data-from="A" data-to="B" d="M187 81.9 L187 105.9" /> or <polyline class="edge" data-from="A" data-to="B" points="187,81.9 187,105.9" /> reads A to B through [[187, 81.9], [187, 105.9]].
export function edgePaths(svg, cls = "edge", ends = ["data-from", "data-to"]) {
    return [...svg.matchAll(new RegExp('<(?:path|polyline) class="' + cls + '"([^>]*)>', "g"))].map((m) => {
        const d = m[1].match(/\sd="([^"]*)"/);
        const raw = d ? d[1].replace(/[ML]/g, " ") : m[1].match(/\spoints="([^"]*)"/)[1].replace(/,/g, " ");
        const n = raw.trim().split(/\s+/).map(Number);
        return { from: text(m[1], ends[0]), to: text(m[1], ends[1]), points: n.filter((v, i) => i % 2 === 0).map((x, i) => [x, n[2 * i + 1]]) };
    });
}
// The lifelines of a sequence diagram.
// Sample input: <line class="lifeline" data-actor="A" x1="140" y1="70" x2="140" y2="199" stroke="#c0caf5" /> reads [{ id: "A", x: 140, end: 199 }].
export function lifelines(svg) {
    return [...svg.matchAll(/<line class="lifeline"([^>]*)>/g)].map((m) => ({ id: text(m[1], "data-actor"), x: num(m[1], "x1"), end: num(m[1], "y2") }));
}
// The viewBox [x, y, width, height] of a figure.
// Sample input: <svg width="300" height="200" viewBox="0 0 300 200"> reads [0, 0, 300, 200].
export function view(svg) {
    return svg.match(/<svg\b[^>]*>/)[0].match(/viewBox="([^"]*)"/)[1].split(/\s+/).map(Number);
}

// Sample input: <g class="subgraph" data-id="one" data-label="one">\n  <rect x="1" y="1" width="92" height="97" .../> reads [1, 1, 93, 98].
export function frame(svg, id) {
    const found = svg.match(new RegExp('<g class="subgraph" data-id="' + id + '"[^>]*>\\s*<rect\\b[^>]*>'));
    const rect = found ? found[0].match(/<rect\b[^>]*>/)[0] : "";
    return found ? [num(rect, "x"), num(rect, "y"), num(rect, "x") + num(rect, "width"), num(rect, "y") + num(rect, "height")] : null;
}
