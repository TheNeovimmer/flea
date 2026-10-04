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
// A full-width glyph advances one em, the widest a label's glyph goes.
const WIDE_ADVANCE_EM = 1;
const LABEL_FONT_PX = 13;
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
// Sample input: <text x="70" font-size="13" text-anchor="middle"><tspan x="70">ab</tspan></text> reaches 70 less one em a glyph, halved.
function reachLeft(svg) {
    let left = Infinity;
    for (const tag of svg.match(/<(?:text|tspan)\b[^<>]*>[^<]*/g) || []) {
        const head = tag.match(/^<(?:text|tspan)\b[^<>]*>/)[0];
        const content = tag.slice(head.length);
        const x = head.match(/\sx="([^"]*)"/);
        if (!x || content.trim() === '') continue;
        const anchor = (head.match(/text-anchor="([^"]*)"/) || [0, 'start'])[1];
        const share = anchor === 'middle' ? 0.5 : anchor === 'end' ? 1 : 0;
        const size = Number((head.match(/font-size="([^"]*)"/) || [0, LABEL_FONT_PX])[1]);
        left = Math.min(left, Number(x[1]) - share * Array.from(content).length * size * WIDE_ADVANCE_EM);
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

// A text with tspan children bounds the canvas by each tspan's own x and anchor, and a stack of lines by its dy steps.
const own = postMermaid(canvas(frame + '<text x="125" y="30" font-size="13" text-anchor="middle"><tspan x="20" text-anchor="start" dy="0">a long label here</tspan></text>'), theme);
sound(own, 'tspan with its own x and anchor');
check(box(own)[0] === 20, 'tspan with its own x and anchor: the canvas starts at 20, got ' + box(own)[0]);
const stack = postMermaid(canvas('<text x="125" y="30" font-size="13" text-anchor="middle"><tspan x="125" dy="-30">top</tspan><tspan x="125" dy="40">bottom</tspan></text>'), theme);
sound(stack, 'two stacked tspans');
check(box(stack)[1] <= 30 - 30 - LABEL_FONT_PX && box(stack)[1] + box(stack)[3] >= 30 + 10, 'two stacked tspans: the canvas holds both lines, got [' + box(stack).join(' ') + ']');

// Mermaid's own multi-line labels are tspans: a sequence diagram with one trims to its drawing like one without.
const lines = real('sequenceDiagram\n    A->>B: first<br>second line');
sound(lines, 'real sequence with a two line message');
check(/<tspan\b/.test(lines), 'real sequence with a two line message: the library did emit tspans');
check(box(lines)[0] > 0, 'real sequence with a two line message: trimmed off the library margin, got ' + box(lines)[0]);
check(box(lines)[0] <= reachLeft(lines), 'real sequence with a two line message: no label cut, canvas ' + box(lines)[0] + ' reach ' + reachLeft(lines));
const flow = real('flowchart TD\n    A["line one<br>line two longer"] --> B');
sound(flow, 'real flowchart with a two line node');
check(box(flow)[0] <= reachLeft(flow), 'real flowchart with a two line node: no label cut');

// A glyph wider than the monospace cell must not let a centred label be cut.
const wide = (word) => postMermaid(canvas(frame + '<text x="125" y="30" font-size="13" text-anchor="middle">' + word + '</text>'), theme);
for (const [name, word] of [['CJK', '会議室会議室会議室会議室'], ['capital W', 'WWWWWWWWWWWW']]) {
    const out = wide(word);
    sound(out, name + ' label');
    check(box(out)[0] <= 125 - Array.from(word).length * LABEL_FONT_PX * WIDE_ADVANCE_EM / 2,
        name + ' label: the canvas reaches the label, got ' + box(out)[0]);
}
const narrow = box(wide('iiiiiiiiiiii'))[0];
check(narrow > 70 && narrow <= 78.2, 'a narrow label keeps the tight monospace estimate, got ' + narrow);
// The library leaves a long CJK message inside its canvas between two actors; the trim must not cut it.
const message = real('sequenceDiagram\n    A->>B: ' + '会議室'.repeat(8));
sound(message, 'real sequence with a long CJK message');
check(box(message)[0] <= reachLeft(message), 'real sequence with a long CJK message: no glyph cut, canvas ' + box(message)[0] + ' reach ' + reachLeft(message));

console.log('MARKDOWN_FIGTIGHTEN ' + checks + ' checks, ' + failures.length + ' failed');
failures.forEach(why => console.log('FAIL ' + why));
if (failures.length > 0) throw new Error(failures.length + ' figure trim checks failed');
