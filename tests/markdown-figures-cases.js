// Case data for tests/markdown-figures.qml: ten formulas, six diagrams,
// the malformed pair, the hostile trio and the oversize refusal. Pure data
// with no QML imports, so the harness stays under its line ceiling.
function mathCases(port) {
    return [
        { kind: "math", source: "\\frac{a}{b}", display: true, tag: "frac" },
        { kind: "math", source: "\\int_0^1 x^2\\,dx", display: true, tag: "int" },
        { kind: "math", source: "\\sum_{n=1}^{\\infty}\\frac{1}{n^2}", display: true, tag: "sum" },
        { kind: "math", source: "\\begin{matrix}a&b\\\\c&d\\end{matrix}", display: true, tag: "matrix" },
        { kind: "math", source: "\\begin{aligned}x&=1\\\\y&=2\\end{aligned}", display: true, tag: "align" },
        { kind: "math", source: "x^2", display: false, tag: "inline" },
        { kind: "math", source: "\\sqrt{2}", display: true, tag: "sqrt" },
        { kind: "math", source: "\\alpha+\\beta=\\gamma", display: false, tag: "greek" },
        { kind: "math", source: "\\lim_{x\\to0}\\frac{\\sin x}{x}", display: true, tag: "lim" },
        { kind: "math", source: "\\binom{n}{k}=\\frac{n!}{k!(n-k)!}", display: true, tag: "binom" },
        { kind: "math", source: "\\frac{unclosed", display: true, tag: "badformula" },
        { kind: "math", source: "\\href{http://127.0.0.1:" + port + "/x}{click}", display: true, tag: "hosthref" },
        { kind: "math", source: "\\url{http://127.0.0.1:" + port + "/y}", display: true, tag: "hosturl" }
    ];
}

function diagCases(port) {
    var big = "flowchart TD\n";
    for (var i = 0; i < 8000; i++)
        big += "A-->B\n";
    return [
        { kind: "mermaid", source: "flowchart TD\n    A --> B", display: true, tag: "flow" },
        { kind: "mermaid", source: "sequenceDiagram\n    A->>B: hi", display: true, tag: "seq" },
        { kind: "mermaid", source: "stateDiagram-v2\n    A --> B", display: true, tag: "state" },
        { kind: "mermaid", source: "classDiagram\n    A <|-- B", display: true, tag: "class" },
        { kind: "mermaid", source: "erDiagram\n    A ||--|| B : has", display: true, tag: "er" },
        { kind: "mermaid", source: "xychart-beta\n    x-axis [a, b]\n    bar [1, 2]", display: true, tag: "xy" },
        { kind: "mermaid", source: "not a diagram {{{", display: true, tag: "baddiagram" },
        { kind: "mermaid", source: "flowchart TD\n    A --> B\n    click A href \"http://127.0.0.1:" + port + "/evil\"", display: true, tag: "hostclick" },
        { kind: "mermaid", source: big, display: true, tag: "oversize" }
    ];
}

function fenceTags() {
    return ["badformula", "hosthref", "hosturl"];
}

function diagFenceTags() {
    return ["baddiagram", "oversize"];
}

// Pixel facts off a grabbed figure: ink against the suite background,
// near-theme hits (fractional geometry resamples edges, so exact matches
// undercount), exact pure black or white the theme never names, and the five
// most common non-background colours for the report. analyzeRegion reads one
// rectangle out of a whole-frame grab; analyzePixels covers the whole frame.
function analyzeRegion(pixels, fullW, x0, y0, w, h) {
    function at(x, y) {
        var o = ((y0 + y) * fullW + (x0 + x)) * 4;
        return [pixels[o], pixels[o + 1], pixels[o + 2], pixels[o + 3]];
    }
    function dist(c, t) {
        return Math.abs(c[0] - t[0]) + Math.abs(c[1] - t[1]) + Math.abs(c[2] - t[2]);
    }
    var fg = [192, 202, 245];
    var accent = [122, 162, 247];
    var ink = 0;
    var black = 0;
    var white = 0;
    var theme = 0;
    var near = 0;
    var transparent = 0;
    var tops = {};
    for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
            var c = at(x, y);
            if (c[3] < 128) {
                transparent++;
                continue;
            }
            if (Math.abs(c[0] - 16) + Math.abs(c[1] - 19) + Math.abs(c[2] - 21) > 36)
                ink++;
            if (c[0] === 0 && c[1] === 0 && c[2] === 0)
                black++;
            if (c[0] === 255 && c[1] === 255 && c[2] === 255)
                white++;
            if ((c[0] === 192 && c[1] === 202 && c[2] === 245)
                    || (c[0] === 122 && c[1] === 162 && c[2] === 247))
                theme++;
            if (dist(c, fg) <= 48 || dist(c, accent) <= 48)
                near++;
            if (Math.abs(c[0] - 16) + Math.abs(c[1] - 19) + Math.abs(c[2] - 21) > 36) {
                var k = c[0] + "," + c[1] + "," + c[2];
                tops[k] = (tops[k] || 0) + 1;
            }
        }
    }
    var keys = Object.keys(tops).sort(function (a, b) { return tops[b] - tops[a]; });
    return { ink: ink, black: black, white: white, theme: theme, near: near,
        transparent: transparent,
        tops: keys.slice(0, 5).map(function (k) { return k + "x" + tops[k]; }).join(" ") };
}

function countRed(pixels) {
    var red = 0;
    for (var i = 0; i < pixels.length; i += 4) {
        if (pixels[i] === 255 && pixels[i + 1] === 0 && pixels[i + 2] === 0)
            red++;
    }
    return red;
}

function countRedRegion(pixels, fullW, x0, y0, w, h) {
    var red = 0;
    for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
            var o = ((y0 + y) * fullW + (x0 + x)) * 4;
            if (pixels[o] === 255 && pixels[o + 1] === 0 && pixels[o + 2] === 0)
                red++;
        }
    }
    return red;
}
