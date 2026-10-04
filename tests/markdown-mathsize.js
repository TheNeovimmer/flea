// Display maths size checks over the drawn SVG, shared by the mathsize shell.
var MATH_UNITS_PER_EX = 442; // MathJax's TeX SVG draws one ex as 442 viewBox units.
var MATH_EX_TOLERANCE = 0.005; // The helper sets the measured x-height exactly (hundredth-pixel rounding), so the 1.2 em rule, 0.9% to 1.1% off the real font, still fails.
var MATH_ROUNDING_PX = 1; // Integer geometry may move a fitted formula's height by this many pixels.

// Sample input: <svg width="2.28px" height="15.04px" viewBox="0 -883.9 1008.6 894.9"> draws one ex at 7.43 px, its height over its viewBox height in ex.
function svgExPx(svg) {
    var root = svg.match(/<svg\b[^>]*>/)[0];
    var height = Number(root.match(/\sheight="([\d.]+)px"/)[1]);
    var box = Number(root.match(/\sviewBox="([^"]*)"/)[1].trim().split(/\s+/)[3]);
    return height / (box / MATH_UNITS_PER_EX);
}

// A display formula's ex, as drawn after the width fit, against the body font's x-height.
function mathExError(figure, image, xHeight) {
    var drawn = svgExPx(figure.svg) * image.width / figure.naturalWidth;
    return Math.abs(drawn - xHeight) <= MATH_EX_TOLERANCE * xHeight ? ""
        : "formula ex " + drawn.toFixed(2) + "px, body x-height " + xHeight.toFixed(2) + "px";
}

// A formula wider than the pane fits it with its aspect kept.
function mathFitError(figure, image, paneWidth) {
    if (!(figure.naturalWidth > paneWidth))
        return "fixture formula is only " + figure.naturalWidth + "px, not wider than the " + paneWidth + "px pane";
    if (image.width > paneWidth)
        return "formula draws " + image.width + "px in a " + paneWidth + "px pane";
    var kept = figure.naturalHeight * image.width / figure.naturalWidth;
    return Math.abs(image.height - kept) <= MATH_ROUNDING_PX ? ""
        : "formula height " + image.height + "px, aspect-kept " + kept.toFixed(2) + "px";
}
