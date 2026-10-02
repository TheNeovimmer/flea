.import "../../ui/js/MenuWheel.js" as Wheel

// Menu wheel rule: notches accrue to one row per 120 angleDelta units, pixels and strokes fold by row height, no tail.
function run(check) {
    // A fractional wheel only accrues: one detent of a hi-res wheel never moves a full row alone.
    if (typeof Wheel.notchSteps === "function")
        check("a fractional wheel accrues but steps nowhere alone", Wheel.notchSteps(0, -0.5).steps, 0)

    // Hi-res: eight 15-unit events total one notch and step one row, never eight.
    if (typeof Wheel.notchSteps !== "function") {
        check("notches accumulate to one row per 120 units", "missing notchSteps", "function")
    } else {
        var acc = 0
        var stepped = 0
        for (var h = 0; h < 8; h++) {
            var one = Wheel.notchSteps(acc, 15)
            acc = one.rest
            stepped += one.steps
        }
        check("eight 15-unit events step one row", stepped, -1)
        check("and hold no leftover", acc, 0)
        // Four such events step nowhere, the next four spend what the first kept.
        acc = 0
        stepped = 0
        for (var p = 0; p < 4; p++) {
            var part = Wheel.notchSteps(acc, 15)
            acc = part.rest
            stepped += part.steps
        }
        check("four 15-unit events step nowhere", stepped, 0)
        check("but keep their travel", acc, 60)
        for (var q = 0; q < 4; q++) {
            var cont = Wheel.notchSteps(acc, 15)
            acc = cont.rest
            stepped += cont.steps
        }
        check("the next four spend what the first kept", stepped, -1)
        check("a full notch still steps exactly one row", Wheel.notchSteps(0, -120).steps, 1)
        // A direction flip drops the remainder instead of spending it against the new travel.
        var held = Wheel.notchSteps(0, 60)
        check("a flip drops the held remainder", Wheel.notchSteps(held.rest, -15).rest, -15)
        check("and steps nothing on the flip", Wheel.notchSteps(held.rest, -15).steps, 0)
    }

    // Phaseless pixels fold by row height at gain 1: twenty -2 nudges total -40, one row at 28.
    if (typeof Wheel.pixelSteps !== "function") {
        check("phaseless pixels fold by row height", "missing pixelSteps", "function")
    } else {
        var px = 0
        var pxSteps = 0
        for (var n = 0; n < 20; n++) {
            var folded = Wheel.pixelSteps(px, -2, 28)
            px = folded.rest
            pxSteps += folded.steps
        }
        check("twenty -2 pixel nudges step one row, not twenty", pxSteps, 1)
    }

    // Touchpad: one row per row height of gained travel, the leftover riding to the next event.
    var oneRow = Wheel.touchSteps(0, -37, 37)
    check("one row height down steps one row", oneRow.steps, 1)
    check("and holds no leftover", oneRow.rest, 0)
    var two = Wheel.touchSteps(0, -74, 37)
    check("two row heights step two rows", two.steps, 2)
    var partial = Wheel.touchSteps(0, -20, 37)
    check("a partial row steps nowhere", partial.steps, 0)
    check("but keeps its travel", partial.rest, -20)
    var continued = Wheel.touchSteps(partial.rest, -20, 37)
    check("the next event spends what the last one kept", continued.steps, 1)
    check("leaving three pixels over", continued.rest, -3)
    var up = Wheel.touchSteps(0, 40, 37)
    check("upward travel steps the highlight up", up.steps, -1)
    check("no travel is no step", Wheel.touchSteps(5, 0, 37).steps, 0)
    // A zero row height folds one-pixel rows, so the fold loop always ends.
    check("a zero row height falls back to one pixel rows", Wheel.touchSteps(0, -100, 0).steps, 100)
}
