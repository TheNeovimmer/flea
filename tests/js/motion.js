.import "../../ui/js/Motion.js" as Motion

// mo1: every Flea transition uses Omarchy's OutCubic, 180 ms to reveal and 140 ms to hide.

function run(check) {
    check("a reveal reads 180", Motion.durMs.open, 180)
    check("a hide reads 140", Motion.durMs.close, 140)
    check("reveal slower than hide", Motion.durMs.open > Motion.durMs.close, true)
    check("no bezier curve to drift back to", Motion.bezierCurve, undefined)
    check("the rise stays 10 px", Motion.translateUpPx, 10)
}
