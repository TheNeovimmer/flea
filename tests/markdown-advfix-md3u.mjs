import { postMermaid, renderFigure } from '../ui/js/FigureWorker.mjs';

globalThis.global = globalThis;
if (!globalThis.setTimeout) {
    const os = await import('qjs:os');
    globalThis.setTimeout = os.setTimeout;
    globalThis.clearTimeout = os.clearTimeout;
}
const { mermaidToSvg } = await import('../ui/vendor/mermaid.mjs');

const LIBRARY_BODY_PX = 13;
const EPSILON = 0.000001;
const theme = { bg: '#101315', fg: '#c0caf5', accent: '#7aa2f7', font: 'monospace' };
const sizes = [12, 14, 28];
const cases = [];
const failures = [];
let checks = 0;
function check(ok, why) {
    checks++;
    if (!ok) failures.push(why);
}
// Sample input: <rect y="10" height="80" stroke-width="8"/>.
function attr(tag, name) {
    const match = tag.match(new RegExp('\\s' + name + '="([^"]*)"'));
    return match ? match[1] : '';
}
// Sample input: <svg viewBox="0 0 100 50"/> answers [0, 0, 100, 50].
function box(svg) { return attr(svg.match(/<svg\b[^>]*>/)[0], 'viewBox').split(/\s+/).map(Number); }
const sources = {
    F2: 'flowchart TD\n  A["AAAAAAAAAAAA"] --> B["BBBBBBBBBBBB"]',
    F7: 'flowchart TD\nA --> B\nstyle B stroke-width:8'
};
for (const id of Object.keys(sources)) {
    const source = sources[id];
    const raw = mermaidToSvg(source, theme.bg, theme.fg, { font: theme.font, padding: 1 });
    const rawWidth = Number(attr(raw.match(/<svg\b[^>]*>/)[0], 'width'));
    for (const bodyPx of sizes) {
        const svg = renderFigure('mermaid', source, true, { ...theme, bodyPx }, { mermaidToSvg });
        const viewBox = box(svg);
        const width = Number(attr(svg.match(/<svg\b[^>]*>/)[0], 'width'));
        const scale = width / viewBox[2];
        const rectangles = svg.match(/<rect\b[^>]*>/g) || [];
        const rect = rectangles[rectangles.length - 1];
        const labels = svg.match(/<text\b[^>]*>[^<]*<\/text>/g) || [];
        check(Math.abs(width - rawWidth * bodyPx / LIBRARY_BODY_PX) < EPSILON,
            id + ' body ' + bodyPx + ': canvas must scale with labels');
        check(labels.every(tag => Number(attr(tag, 'font-size')) === LIBRARY_BODY_PX),
            id + ' body ' + bodyPx + ': keep library label geometry');
        const paintBottom = Number(attr(rect, 'y')) + Number(attr(rect, 'height'))
            + Number(attr(rect, 'stroke-width')) / 2;
        if (id === 'F7') check(viewBox[1] + viewBox[3] >= paintBottom,
            'F7 body ' + bodyPx + ': thick library stroke clipped');
        cases.push({ id, bodyPx, svg, source, viewBox, scale,
            nodeWidth: Number(attr(rect, 'width')) * scale,
            canvasWidth: width, label: id === 'F2' ? 'AAAAAAAAAAAA' : 'B',
            fontPx: Number(attr(labels[0], 'font-size')) * scale, paintBottom });
    }
}
const primitiveCases = [
    ['rect', '<rect x="5" y="5" width="10" height="10" stroke="#c0caf5" stroke-width="6"/>', 2, 18],
    ['rect-large', '<rect x="10" y="10" width="80" height="80" stroke="#c0caf5" stroke-width="8"/>', 6, 94],
    ['line', '<line x1="5" y1="10" x2="15" y2="10" stroke="#c0caf5" stroke-width="8"/>', 6, 14],
    ['square-cap', '<line x1="5" y1="5" x2="15" y2="15" stroke="#c0caf5" stroke-width="8" stroke-linecap="square"/>', 5 - 4 * Math.SQRT2, 15 + 4 * Math.SQRT2],
    ['circle', '<circle cx="10" cy="10" r="5" stroke="#c0caf5" stroke-width="8"/>', 1, 19],
    ['ellipse', '<ellipse cx="10" cy="10" rx="3" ry="5" stroke="#c0caf5" stroke-width="8"/>', 1, 19],
    ['polygon', '<polygon points="5,5 15,5 10,15" stroke="#c0caf5" stroke-width="8"/>', 1, 19],
    ['polyline', '<polyline points="5,5 10,15 15,5" stroke="#c0caf5" stroke-width="8"/>', 1, 19]
];
for (const [name, primitive, low, high] of primitiveCases) {
    const svg = postMermaid('<svg width="100" height="100" viewBox="0 0 100 100">' + primitive + '</svg>', theme);
    const bounds = box(svg);
    check(bounds[1] <= low && bounds[1] + bounds[3] >= high, 'F7 ' + name + ': stroke extent clipped');
}
for (const unknown of ['stroke-width="8px"', 'stroke-width="inherit"', 'stroke-width=""', 'style="stroke-width:8"']) {
    const svg = postMermaid('<svg width="100" height="100" viewBox="0 0 100 100"><rect y="10" height="80" stroke="#c0caf5" ' + unknown + '/></svg>', theme);
    check(box(svg).join(' ') === '0 0 100 100', 'F7 unknown ' + unknown + ': retain original canvas');
}
console.log('MARKDOWN_MD3U ' + checks + ' checks, ' + failures.length + ' failed');
failures.forEach(why => console.log('FAIL ' + why));
console.log(JSON.stringify(cases));
if (failures.length) throw new Error('md3u figure regressions');
