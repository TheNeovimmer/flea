import { postMermaid } from '../ui/js/FigureWorker.mjs';

const assert = {
    ok(value, why) { if (!value) throw new Error(why); },
    match(value, pattern) { this.ok(pattern.test(value), 'missing ' + pattern); },
    doesNotMatch(value, pattern) { this.ok(!pattern.test(value), 'unexpected ' + pattern); }
};
const theme = { bg: '#101315', fg: '#c0caf5', accent: '#7aa2f7', font: 'monospace', bodyPx: 14 };
const cases = [];
let checks = 0;
const marker = '<defs><marker id="tip" markerWidth="8" markerHeight="5" refX="8" refY="2.5" orient="auto-start-reverse"><polygon points="0 0, 8 2.5, 0 5" fill="#7aa2f7"/></marker></defs>';
for (const atStart of [false, true]) {
    for (const angle of [0, 45, 90, 135, 180, 225, 270, 315]) {
        const radians = angle * Math.PI / 180;
        const dx = Math.round(30 * Math.cos(radians)), dy = Math.round(30 * Math.sin(radians));
        const first = `${60 - dx},${60 - dy}`, last = `${60 + dx},${60 + dy}`;
        const points = `${first} ${last} ${last}`;
        const edge = `<polyline class="edge" points="${points}" fill="none" stroke="#c0caf5" stroke-width="1" marker-${atStart ? 'start' : 'end'}="url(#tip)"/>`;
        const svg = postMermaid(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" width="120" height="120">${marker}${edge}</svg>`, theme);
        assert.match(svg, /<path\b/);
        assert.doesNotMatch(svg, /<polyline\b[^>]*marker-(?:start|end)=/);
        assert.ok(svg.includes(marker), 'marker orient, reference point and default stroke units are preserved');
        checks += 3;
        cases.push({ name: `${atStart ? 'start' : 'end'} ${angle} degrees`, svg, atStart });
    }
}
const plain = '<polyline points="10,10 20,20" fill="none" stroke="#c0caf5"/>';
const line = '<line x1="10" y1="20" x2="80" y2="20" stroke="#c0caf5" marker-end="url(#tip)"/>';
const canvas = `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120">${marker}${plain}${line}</svg>`;
const unchanged = postMermaid(canvas, theme);
assert.ok(unchanged.includes(plain), 'unmarked polylines stay unchanged');
assert.ok(unchanged.includes(line), 'horizontal sequence lines stay unchanged');
const scientific = postMermaid(`<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120">${marker}<polyline points="+1e1,-2e-1 3.5E1,.4" marker-end="url(#tip)"/></svg>`, theme);
assert.match(scientific, /d="M\+1e1 -2e-1 L3\.5E1 \.4"/);
checks += 3;
console.log(`MARKDOWN_PATHS ${checks} checks, 0 failed`);
console.log(JSON.stringify(cases));
