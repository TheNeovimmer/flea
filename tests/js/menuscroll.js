.import "../../ui/js/MenuWheel.js" as Wheel

// The menu wheel rule behind ui/FastScrollHandler.qml's stepMode: a notch steps the highlight
// one row, a touchpad stroke one row per row height of gained travel, with no momentum tail.
function run(check) {
    // One notch is one row, down for a downward notch, whatever the notch is worth in pixels.
    check("a downward notch steps the highlight down one row", Wheel.notchStep(-288), 1)
    check("an upward notch steps it up one row", Wheel.notchStep(288), -1)
    check("a fractional wheel steps the same single row", Wheel.notchStep(-0.5), 1)
    check("no travel steps nowhere", Wheel.notchStep(0), 0)
    check("garbage steps nowhere", Wheel.notchStep("x"), 0)
    // The sign is writeY's: negative gained travel moves later rows into view, like Down.
    check("the notch sign follows the content, not the finger", Wheel.notchStep(-120), 1)

    // Touchpad: one row per row height of gained travel, the leftover riding to the next event.
    var one = Wheel.touchSteps(0, -37, 37)
    check("one row height down steps one row", one.steps, 1)
    check("and holds no leftover", one.rest, 0)
    var two = Wheel.touchSteps(0, -74, 37)
    check("two row heights step two rows", two.steps, 2)
    var part = Wheel.touchSteps(0, -20, 37)
    check("a partial row steps nowhere", part.steps, 0)
    check("but keeps its travel", part.rest, -20)
    var cont = Wheel.touchSteps(part.rest, -20, 37)
    check("the next event spends what the last one kept", cont.steps, 1)
    check("leaving three pixels over", cont.rest, -3)
    var up = Wheel.touchSteps(0, 40, 37)
    check("upward travel steps the highlight up", up.steps, -1)
    check("no travel is no step", Wheel.touchSteps(5, 0, 37).steps, 0)
    // No tail: each call folds only what it was handed, so a stroke that ends steps nothing more.
    check("a zero row height falls back to one pixel rows", Wheel.touchSteps(0, -100, 0).steps, 100)
}
