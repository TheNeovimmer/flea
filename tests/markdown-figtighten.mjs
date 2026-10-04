// The canvas trim of ui/js/FigureWorker.mjs over real library output and over hand-built shapes: never a broken viewBox, never a label cut.
import { postMermaid } from '../ui/js/FigureWorker.mjs';

globalThis.global = globalThis;
if (!globalThis.setTimeout) {
    const os = await import('qjs:os');
    globalThis.setTimeout = os.setTimeout;
    globalThis.clearTimeout = os.clearTimeout;
}
const { mermaidToSvg } = await import('../ui/vendor/mermaid.mjs');

const theme = { bg: '#101315', fg: '#c0caf5', accent: '#7aa2f7', font: 'sans-serif', bodyPx: 14 };
// A full-width or other non-ASCII glyph advances one em, the widest a label's glyph goes.
const FULL_WIDTH_ADVANCE_EM = 1;
// Per-glyph maximum advance in em over DejaVu Sans, Liberation Sans and Noto Sans, measured with PIL at 1000 px.
const MAX_ADVANCE_EM = {
    '0': 0.636, '1': 0.636, '2': 0.636, '3': 0.636, '4': 0.636, '5': 0.636, '6': 0.636, '7': 0.636, '8': 0.636,
    '9': 0.636, 'a': 0.613, 'b': 0.635, 'c': 0.55, 'd': 0.635, 'e': 0.615, 'f': 0.352, 'g': 0.635, 'h': 0.634,
    'i': 0.278, 'j': 0.278, 'k': 0.579, 'l': 0.278, 'm': 0.974, 'n': 0.634, 'o': 0.612, 'p': 0.635, 'q': 0.635,
    'r': 0.413, 's': 0.521, 't': 0.392, 'u': 0.634, 'v': 0.592, 'w': 0.818, 'x': 0.592, 'y': 0.592, 'z': 0.525,
    'A': 0.684, 'B': 0.686, 'C': 0.722, 'D': 0.77, 'E': 0.667, 'F': 0.611, 'G': 0.778, 'H': 0.752, 'I': 0.339,
    'J': 0.5, 'K': 0.667, 'L': 0.557, 'M': 0.907, 'N': 0.76, 'O': 0.787, 'P': 0.667, 'Q': 0.787, 'R': 0.722,
    'S': 0.667, 'T': 0.611, 'U': 0.732, 'V': 0.684, 'W': 0.989, 'X': 0.685, 'Y': 0.667, 'Z': 0.685, '!': 0.401,
    '"': 0.46, '#': 0.838, '$': 0.636, '%': 0.95, '&': 0.78, '\'': 0.275, '(': 0.39, ')': 0.39, '*': 0.551,
    '+': 0.838, ',': 0.318, '-': 0.361, '.': 0.318, '/': 0.372, ':': 0.337, ';': 0.337, '<': 0.838, '=': 0.838,
    '>': 0.838, '?': 0.556, '@': 1.015, '[': 0.39, '\\': 0.372, ']': 0.39, '^': 0.838, '_': 0.556, '`': 0.5,
    '{': 0.636, '|': 0.551, '}': 0.636, '~': 0.838, ' ': 0.318
};
const ASCII_LIMIT = 0x7f;
const LABEL_FONT_PX = 13;
// A label of twelve narrow glyphs reaches 125 less about 75 at 13 px, inside these bounds with the stroke pad.
const NARROW_FLOOR = 70;
const NARROW_CEILING = 76;
const failures = [];
let checks = 0;
function check(ok, why) {
    checks++;
    if (!ok) failures.push(why);
}
// Sample input: <svg viewBox="0 0 100 50"/> answers [0, 0, 100, 50].
function box(svg) {
    return svg.match(/<svg\b[^>]*>/)[0].match(/viewBox="([^"]*)"/)[1].split(/\s+/).map(Number);
}
// Sample input: <svg width="100" height="50"/> answers 100 for "width".
function rootNumber(svg, name) { return Number(svg.match(/<svg\b[^>]*>/)[0].match(new RegExp('\\s' + name + '="([^"]*)"'))[1]); }
function sound(svg, why) {
    const view = box(svg);
    check(view.length === 4 && view.every(Number.isFinite) && view[2] > 0 && view[3] > 0
        && Number.isFinite(rootNumber(svg, 'width')) && rootNumber(svg, 'width') > 0, why + ': the canvas stays finite, got [' + view.join(' ') + ']');
}
// Sample input: "iW" advances 1.267 em, the measured maxima 0.278 and 0.989; "&lt;" is one glyph and a non-ASCII glyph advances one em.
function glyphEm(content) {
    const text = content.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
    return Array.from(text).reduce((em, glyph) => em + (glyph.codePointAt(0) > ASCII_LIMIT ? FULL_WIDTH_ADVANCE_EM : MAX_ADVANCE_EM[glyph]), 0);
}
// Sample input: <text x="70" font-size="13" text-anchor="middle"><tspan x="70">ab</tspan></text> reaches 70 less the glyphs' measured em, halved; a tspan inherits both from its text.
function reachLeft(svg) {
    let left = Infinity;
    let parent = '';
    for (const tag of svg.match(/<\/?(?:text|tspan)\b[^<>]*>[^<]*/g) || []) {
        if (tag.startsWith('</')) {
            if (tag.startsWith('</text')) parent = '';
            continue;
        }
        const head = tag.match(/^<(?:text|tspan)\b[^<>]*>/)[0];
        const content = tag.slice(head.length);
        const isText = head.startsWith('<text');
        if (isText) parent = head;
        const x = head.match(/\sx="([^"]*)"/);
        if (!x || content.trim() === '') continue;
        const anchor = (head.match(/text-anchor="([^"]*)"/) || parent.match(/text-anchor="([^"]*)"/) || [0, 'start'])[1];
        const share = anchor === 'middle' ? 0.5 : anchor === 'end' ? 1 : 0;
        const size = Number((head.match(/font-size="([^"]*)"/) || parent.match(/font-size="([^"]*)"/) || [0, LABEL_FONT_PX])[1]);
        left = Math.min(left, Number(x[1]) - share * glyphEm(content) * size);
    }
    return left;
}
function real(source) {
    return postMermaid(mermaidToSvg(source, theme.bg, theme.fg, { font: theme.font, padding: 1 }), theme);
}
const canvas = (inner) => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 100" width="300" height="100">' + inner + '</svg>';
const frame = '<rect x="100" y="10" width="50" height="40" stroke="#fff" stroke-width="1"/>';

// A text the left scan cannot read must leave the library's canvas alone, never an Infinity viewBox.
for (const [name, text] of [
    ['a self-closing text', '<text x="50" y="40" font-size="13"/>'],
    ['a text holding a title', '<text x="50" y="40" font-size="13"><title>a</title>hi</text>'],
    ['a text whose tspan sets no x after the first line', '<text x="50" y="40" font-size="13"><tspan>a</tspan><tspan dy="14">b</tspan></text>'],
    ['a text taking its anchor from a style', '<text x="50" y="40" font-size="13" style="text-anchor: middle">hi</text>']
]) {
    const out = postMermaid(canvas(text), theme);
    sound(out, name);
    check(box(out)[0] === 0 && box(out)[2] === 300, name + ': the library canvas is kept, got [' + box(out).join(' ') + ']');
}
// With a rect beside it the bounds are finite, so only the count of texts the scan read keeps the canvas.
for (const [name, text] of [
    ['a self-closing text beside a rect', '<text x="50" y="40" font-size="13"/>'],
    ['a text holding a title beside a rect', '<text x="50" y="40" font-size="13"><title>a</title>hi</text>']
]) {
    const out = postMermaid(canvas(frame + text), theme);
    sound(out, name);
    check(box(out)[0] === 0 && box(out)[2] === 300, name + ': the library canvas is kept, got [' + box(out).join(' ') + ']');
}

// A text with tspan children bounds the canvas by each tspan's own x and anchor, and a stack of lines by its dy steps.
const own = postMermaid(canvas(frame + '<text x="125" y="30" font-size="13" text-anchor="middle"><tspan x="20" text-anchor="start" dy="0">a long label here</tspan></text>'), theme);
sound(own, 'tspan with its own x and anchor');
check(box(own)[0] === 20, 'tspan with its own x and anchor: the canvas starts at 20, got ' + box(own)[0]);
const stack = postMermaid(canvas('<text x="125" y="30" font-size="13" text-anchor="middle"><tspan x="125" dy="-30">top</tspan><tspan x="125" dy="40">bottom</tspan></text>'), theme);
sound(stack, 'two stacked tspans');
check(box(stack)[1] <= 30 - 30 - LABEL_FONT_PX && box(stack)[1] + box(stack)[3] >= 30 + 10, 'two stacked tspans: the canvas holds both lines, got [' + box(stack).join(' ') + ']');

// A tspan takes its anchor and size from its text: the oracle must read them there, and the trim must reach the label.
const inherited = postMermaid(canvas(frame + '<text x="125" y="30" font-size="26" text-anchor="middle"><tspan x="125">会議室会議</tspan><tspan x="125" dy="30">会議室会議室会</tspan></text>'), theme);
sound(inherited, 'tspans inheriting anchor and size');
const inheritedReach = 125 - 7 * 26 * FULL_WIDTH_ADVANCE_EM / 2;
check(reachLeft(inherited) === inheritedReach, 'tspans inheriting anchor and size: the oracle reads the parent, got ' + reachLeft(inherited) + ' want ' + inheritedReach);
check(box(inherited)[0] <= inheritedReach, 'tspans inheriting anchor and size: no label cut, canvas ' + box(inherited)[0]);

// Mermaid's own multi-line labels are tspans: a sequence diagram with one trims to its drawing like one without.
const lines = real('sequenceDiagram\n    A->>B: first<br>second line');
sound(lines, 'real sequence with a two line message');
check(/<tspan\b/.test(lines), 'real sequence with a two line message: the library did emit tspans');
check(box(lines)[0] > 0, 'real sequence with a two line message: trimmed off the library margin, got ' + box(lines)[0]);
check(box(lines)[0] <= reachLeft(lines), 'real sequence with a two line message: no label cut, canvas ' + box(lines)[0] + ' reach ' + reachLeft(lines));
// The node's label is short enough that its priced width stays inside the library's node, so the left margin still trims.
const flow = real('flowchart TD\n    A["line one<br>line two"] --> B');
sound(flow, 'real flowchart with a two line node');
check(box(flow)[0] > 0, 'real flowchart with a two line node: trimmed off the library margin, got ' + box(flow)[0]);
check(box(flow)[0] <= reachLeft(flow), 'real flowchart with a two line node: no label cut');

// A glyph wider than the monospace cell must not let a centred label be cut.
const wide = (word) => postMermaid(canvas(frame + '<text x="125" y="30" font-size="13" text-anchor="middle">' + word + '</text>'), theme);
for (const [name, word] of [['CJK', '会議室会議室会議室会議室'], ['capital W', 'WWWWWWWWWWWW'], ['at signs', '@@@@@@@@@@@@'],
    ['capitals and symbols', 'DOMAIN +=^ QUERY'], ['percent runs', '100%%%% #### +++++'], ['capitals', 'OQGDNHUCRBXZ']]) {
    const out = wide(word);
    sound(out, name + ' label');
    check(box(out)[0] <= 125 - glyphEm(word) * LABEL_FONT_PX / 2, name + ' label: the canvas reaches the label, got ' + box(out)[0]);
}
// Every printable ASCII glyph, in a run, must stay inside the canvas at its measured maximum advance.
const escapes = { '<': '&lt;', '>': '&gt;', '&': '&amp;' };
for (const glyph of Object.keys(MAX_ADVANCE_EM)) {
    const out = wide((escapes[glyph] || glyph).repeat(12));
    check(box(out)[0] <= reachLeft(out), 'the glyph "' + glyph + '" run: no label cut, canvas ' + box(out)[0] + ' reach ' + reachLeft(out));
}
// A narrow label keeps a tight estimate: the digit and lowercase price, not the widest class's.
const narrow = box(wide('iiiiiiiiiiii'))[0];
check(narrow > NARROW_FLOOR && narrow <= NARROW_CEILING, 'a narrow label keeps a tight estimate, got ' + narrow);
// A sequence message of capitals and symbols, and an edge label of at signs, must not be cut.
const domain = real('sequenceDiagram\n    A->>B: DOMAIN <=> QUERY @@@@ %%%%');
sound(domain, 'real sequence with a capitals and symbols message');
check(box(domain)[0] <= reachLeft(domain), 'real sequence with a capitals and symbols message: no label cut, canvas ' + box(domain)[0] + ' reach ' + reachLeft(domain));
const edge = real('flowchart LR\n    A -->|"@@@@@@@@ WWWW DOMAIN"| B');
sound(edge, 'real flowchart with an at sign edge label');
check(box(edge)[0] <= reachLeft(edge), 'real flowchart with an at sign edge label: no label cut, canvas ' + box(edge)[0] + ' reach ' + reachLeft(edge));
// The library leaves a long CJK message inside its canvas between two actors; the trim must not cut it.
const message = real('sequenceDiagram\n    A->>B: ' + '会議室'.repeat(8));
sound(message, 'real sequence with a long CJK message');
check(box(message)[0] > 0, 'real sequence with a long CJK message: trimmed off the library margin, got ' + box(message)[0]);
check(box(message)[0] <= reachLeft(message), 'real sequence with a long CJK message: no glyph cut, canvas ' + box(message)[0] + ' reach ' + reachLeft(message));

console.log('MARKDOWN_FIGTIGHTEN ' + checks + ' checks, ' + failures.length + ' failed');
failures.forEach(why => console.log('FAIL ' + why));
if (failures.length > 0) throw new Error(failures.length + ' figure trim checks failed');
