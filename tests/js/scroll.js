.import "../../ui/js/Scroll.js" as Scroll
.import "sourcefixture.js" as Source

// The wheel arithmetic behind ui/FastScrollHandler.qml: notch distance, write bounds, and when an event counts as consumed.
function run(check) {
    // A notch: 120 units, the platform's lines, the pixels a line is worth, and the multiplier.
    check("one notch down moves lines times notch pixels times the multiplier",
          Scroll.distance(0, -120, 3, 24, 4), -288)
    check("one notch up moves the same distance the other way", Scroll.distance(0, 120, 3, 24, 4), 288)
    check("two notches move twice", Scroll.distance(0, -240, 3, 24, 4), -576)
    // The one fallback: the handler passes the platform's hint raw, and no lines means Qt's own three.
    check("a platform that reports no lines moves Qt's three", Scroll.distance(0, -120, 0, 24, 4), -288)
    check("and so does one that reports a negative count", Scroll.distance(0, -120, -1, 24, 4), -288)
    // A touchpad hands pixels, which win over any angle that rides along and move one to one.
    check("a pixel delta moves one to one, no multiplier", Scroll.distance(-10, -120, 3, 24, 4), -10)
    check("a fractional pixel delta keeps its fraction", Scroll.distance(-2.5, 0, 3, 24, 4), -2.5)
    check("no delta at all moves nothing", Scroll.distance(0, 0, 3, 24, 4), 0)
    check("garbage reads as no movement", Scroll.distance("x", undefined, 3, 24, 4), 0)

    // Bounds: the origin and the last page, and a short content pinned to the origin.
    check("a write above the origin lands on it", Scroll.bounded(-50, 0, 1000, 400), 0)
    check("a write past the end lands on the last page", Scroll.bounded(5000, 0, 1000, 400), 600)
    check("a write inside stays where it was asked", Scroll.bounded(250, 0, 1000, 400), 250)
    check("a content shorter than the view pins to the origin", Scroll.bounded(100, 0, 300, 400), 0)
    check("an origin below zero is honoured", Scroll.bounded(-100, -20, 1000, 400), -20)
    check("an unknown content height reads as empty", Scroll.bounded(100, 0, undefined, 400), 0)

    // Consumed only when the content moved, so an event at an edge keeps propagating.
    check("a moved content consumes the event", Scroll.moved(100, 388), true)
    check("a content that did not move does not", Scroll.moved(600, 600), false)
    check("a sub-pixel jitter does not count as movement", Scroll.moved(600, 600.005), false)

    // A scrollbar describes the viewport, so a scale listing keeps the 24 px minimum handle everywhere travel is measured.
    check("fitting content has no scroll range", Scroll.range(400, 400), 0)
    check("a listing shorter than the viewport has no range either", Scroll.range(1, 400), 0)
    check("overflow is the content left below one viewport", Scroll.range(1000, 400), 600)
    check("a proportional handle names the visible fraction", Scroll.handleLength(500, 1000, 400, 24), 200)
    check("the handle travels the track less itself", Scroll.travel(500, 1000, 400, 24), 300)
    check("a track no longer than the minimum handle leaves it no travel", Scroll.travel(20, 1000, 400, 24), 0)
    check("and with no travel the map answers the origin, which the bar never asks for", Scroll.positionForHandle(10, -20, 1000, 400, 20, 24), -20)

    // Finder's reveal: nothing over content that fits, and any one of moving, pointer in the lane or a press shows it.
    check("a scroller over content that fits never shows", Scroll.revealed(false, true, true, true), false)
    check("at rest it hides", Scroll.revealed(true, false, false, false), false)
    check("the view moving shows it", Scroll.revealed(true, true, false, false), true)
    check("the pointer in the lane shows it and keeps it", Scroll.revealed(true, false, true, false), true)
    check("a press down keeps it", Scroll.revealed(true, false, false, true), true)
    // A track press centres the knob on the pointer, clamped to the travel at both ends.
    check("a press mid-track centres the knob there", Scroll.jumpOffset(250, 100, 400), 200)
    check("a press near the top clamps to the top", Scroll.jumpOffset(20, 100, 400), 0)
    check("a press near the bottom clamps to the last page", Scroll.jumpOffset(495, 100, 400), 400)
    check("with no travel the knob stays put", Scroll.jumpOffset(250, 100, 0), 0)
    check("a scale listing keeps a usable minimum handle", Scroll.handleLength(500, 3700000, 500, 24), 24)
    check("the top maps to the top of the track", Scroll.handleOffset(0, 0, 1000, 400, 500, 24), 0)
    check("the last page maps to the end of the track", Scroll.handleOffset(600, 0, 1000, 400, 500, 24), 300)
    // Mid-track, so a mapping that kept the origin would land 10 px off rather than on the same clamp.
    check("a non-zero origin is removed before mapping", Scroll.handleOffset(280, -20, 1000, 400, 500, 24), 150)
    check("a position above the origin maps to the top of the track", Scroll.handleOffset(-100, 0, 1000, 400, 500, 24), 0)
    check("a position past the last page maps to the end of the track", Scroll.handleOffset(900, 0, 1000, 400, 500, 24), 300)
    check("dragging the handle to the middle maps to the middle page",
          Scroll.positionForHandle(150, 0, 1000, 400, 500, 24), 300)
    check("dragging beyond the track clamps to the last page",
          Scroll.positionForHandle(900, 0, 1000, 400, 500, 24), 600)
    check("dragging above the track clamps to the origin",
          Scroll.positionForHandle(-50, -20, 1000, 400, 500, 24), -20)
    // A scale listing (content 100000, viewport 400, track 400) clamps its 1.6 px handle to 24, so travel is 376, not 398.4.
    check("a clamped handle starts at the top of the track", Scroll.handleOffset(0, 0, 100000, 400, 400, 24), 0)
    check("a clamped handle maps the middle page to the middle of the track", Scroll.handleOffset(49800, 0, 100000, 400, 400, 24), 188)
    check("a clamped handle maps the last page to the end of the track", Scroll.handleOffset(99600, 0, 100000, 400, 400, 24), 376)
    check("a clamped handle maps the middle of the track to the middle page", Scroll.positionForHandle(188, 0, 100000, 400, 400, 24), 49800)
    check("a clamped handle clamps a drag past the track to the last page", Scroll.positionForHandle(900, 0, 100000, 400, 400, 24), 99600)
    check("a clamped handle removes a non-zero origin before mapping", Scroll.handleOffset(49900, 100, 100000, 400, 400, 24), 188)
    check("a clamped handle adds the origin back to a dragged position", Scroll.positionForHandle(188, 100, 100000, 400, 400, 24), 49900)

    // The lane stays reserved, so rows never reflow under the bar.
    check("the lane is the row padding itself", Scroll.lane(14), 14)
    check("the lane scales with text size", Scroll.lane(16), 16)
    check("no padding leaves no lane", Scroll.lane(0), 0)
    check("garbage leaves no lane", Scroll.lane("x"), 0)
    // The width content may use: the view less the lane it always keeps clear.
    // Sample input: contentWidth(700, 14) is 686, a 700 px listing holding 686 px of rows.
    check("content ends one lane short of the view", Scroll.contentWidth(700, 14), 686)
    check("content fills a view with no padding", Scroll.contentWidth(700, 0), 700)
    check("a view narrower than its lane holds nothing", Scroll.contentWidth(9, 14), 0)
    check("garbage holds nothing", Scroll.contentWidth("x", "y"), 0)

    // The thumb follows Hyprland rounding: square at 0, clamped at half the thinner side.
    check("square corners stay square", Scroll.knobRadius(0, 6, 100), 0)
    check("rounding clamps at half the thinner side", Scroll.knobRadius(8, 6, 100), 3)
    check("a rounding past half the knob clamps to the knob's own half", Scroll.knobRadius(8, 10, 100), 5)
    check("a rounding below the clamp holds as it is", Scroll.knobRadius(3, 10, 100), 3)
    check("garbage rounding stays square", Scroll.knobRadius("x", 6, 100), 0)
    // GM 2026-09-29: no line or border along the lane in any state, only the space itself.
    check("the bar binds its thumb to Hyprland rounding",
          Source.source("ui/ViewportScrollBar.qml").indexOf("radius: Scroll.knobRadius(Style.cornerRadius, width, height)") >= 0, true)
    check("no track-line constant survives in Scroll.js",
          Source.source("ui/js/Scroll.js").indexOf("TRACK_LINE"), -1)
    check("no track-line reader survives in the bar",
          Source.source("ui/ViewportScrollBar.qml").indexOf("TRACK_LINE"), -1)
    check("no hairline element survives in the bar",
          Source.source("ui/ViewportScrollBar.qml").indexOf("hairline"), -1)

    // GM 2026-10-01: touchpad input answers Finder's feel; the wheel notch above is unchanged.
    check("phase 0 is a wheel, any other phase is a touchpad", Scroll.isTouchpad(0), false)
    check("begin is a touchpad", Scroll.isTouchpad(1), true)
    check("update is a touchpad", Scroll.isTouchpad(2), true)
    check("end is a touchpad", Scroll.isTouchpad(3), true)
    check("touchpad pixels gain GTK4's 2.5", Scroll.touchDistance(-10), -25)
    check("a sub-pixel frame moves nothing, never a notch",
          Scroll.strokeDistance(0, -4, 2, 3, 24, 4), 0)
    check("a touchpad stroke ignores the angle riding along",
          Scroll.strokeDistance(-10, -120, 2, 3, 24, 4), -25)
    check("a notch through the same entry is still 288",
          Scroll.strokeDistance(0, -120, 0, 3, 24, 4), -288)
    // The lift is the stroke's last 100 ms; fingers paused before it give no tail.
    check("a pause before the lift gives no tail",
          Scroll.liftVelocity([{ t: 0, x: -50, y: 0 }], 500).vx, 0)
    check("a steady stroke reads its own rate",
          Scroll.liftVelocity([{ t: 0, x: 0, y: 0 }, { t: 50, x: -100, y: 0 }], 50).vx, -2)
    check("three 25 px frames at 8 ms read 3.125 off the stale Begin anchor",
          Scroll.liftVelocity([{ t: 0, x: 0, y: 0 }, { t: 8, x: 25, y: 0 }, { t: 16, x: 25, y: 0 }, { t: 24, x: 25, y: 0 }], 104).vx, 3.125)
    check("two events in one millisecond take the 16 ms floor",
          Scroll.liftVelocity([{ t: 100, x: 25, y: 0 }, { t: 100, x: 25, y: 0 }], 100).vx, 3.125)
    check("the lift caps at the named maximum",
          Scroll.liftVelocity([{ t: 0, x: 500, y: 0 }, { t: 90, x: 500, y: 0 }], 90).vx, 6)
    check("below the stop speed there is no tail", Scroll.tailTotal(0.02), 0)
    check("above it the tail lives", Scroll.tailLive(1, 0), true)
    check("at rest it does not", Scroll.tailLive(0.02, 0), false)
    var steppedV = 2, steppedDt = 16.7, steppedSum = 0, steppedGuard = 0
    while (Scroll.tailLive(steppedV, 0) && steppedGuard < 10000) {
        var stepped = Scroll.tailStep(steppedV, steppedDt)
        steppedSum += stepped.dx
        steppedV = stepped.v
        steppedGuard += 1
    }
    check("the stepped tail equals the closed form within 1 px",
          Math.abs(steppedSum - Scroll.tailTotal(2)) < 1, true)
    check("a tail past the end still lands on the last page",
          Scroll.bounded(600 + Scroll.tailTravel(2, 500), 0, 1000, 400), 600)
    // Elastic edges: resisted overscroll, the return landing on its bound, wheel never leaving it.
    check("no raw travel past the bound shows no overscroll",
          typeof Scroll.overResist === "function" && Scroll.overResist(0, 400) === 0, true)
    check("a small push past shows a smaller resisted one",
          typeof Scroll.overResist === "function"
          && Scroll.overResist(100, 400) > 0 && Scroll.overResist(100, 400) < 100, true)
    check("more raw travel shows more, never past the viewport",
          typeof Scroll.overResist === "function"
          && Scroll.overResist(200, 400) > Scroll.overResist(100, 400)
          && Scroll.overResist(100000, 400) < 400, true)
    check("no viewport shows none",
          typeof Scroll.overResist === "function" && Scroll.overResist(100, 0) === 0, true)
    check("the return starts where the lift left it",
          typeof Scroll.returnAt === "function" && Scroll.returnAt(80, 0, 0, 200) === 80, true)
    check("the return reaches its bound",
          typeof Scroll.returnAt === "function" && Scroll.returnAt(80, 0, 200, 200) === 0, true)
    check("a wheel notch past the top stays on the bound, never past it",
          Scroll.bounded(0 - 288, 0, 1000, 400), 0)
    check("a wheel notch past the end stays on the last page",
          Scroll.bounded(600 + 288, 0, 1000, 400), 600)
    // tp2-r2: margins move the rest, dead axes take no delta, the tail brakes past the bound.
    check("a gap margin rests below the origin",
          typeof Scroll.limits === "function" && Scroll.limits(0, 1000, 400, 8, 0).min === -8, true)
    check("a gap margin keeps the last page",
          typeof Scroll.limits === "function" && Scroll.limits(0, 1000, 400, 8, 0).max === 600, true)
    check("margins default to the old bounds",
          typeof Scroll.limits === "function"
          && Scroll.limits(0, 1000, 400).min === 0 && Scroll.limits(0, 1000, 400).max === 600, true)
    check("a bounded write honours the margins",
          typeof Scroll.limits === "function" && Scroll.bounded(-8, 0, 1000, 400, 8, 0) === -8, true)
    check("a vertical list has no X range",
          typeof Scroll.rangesX === "function" && Scroll.rangesX({ contentWidth: -1, width: 400 }) === false, true)
    check("a fitting content has no Y range",
          typeof Scroll.rangesY === "function" && Scroll.rangesY({ contentHeight: 100, height: 400 }) === false, true)
    check("an overflowing content ranges",
          typeof Scroll.rangesY === "function" && Scroll.rangesY({ contentHeight: 1000, height: 400 }), true)
    check("the past-bound brake is strong but nonzero",
          typeof Scroll.overDecel === "function"
          && Scroll.overDecel(6, 16.7) > 0 && Scroll.overDecel(6, 16.7) < 6 * Math.pow(0.998, 16.7), true)
    check("the handler resists touchpad edges and returns with Omarchy motion",
          Source.source("ui/FastScrollHandler.qml").indexOf("overResist") >= 0
          && Source.source("ui/FastScrollHandler.qml").indexOf("startReturn") >= 0
          && Source.source("ui/FastScrollHandler.qml").indexOf("Motion.durMs.open") >= 0
          && Source.source("ui/FastScrollHandler.qml").indexOf("Theme.reducedMotion") >= 0, true)
    check("the handler routes a touchpad by phase",
          Source.source("ui/FastScrollHandler.qml").indexOf("Scroll.isTouchpad") >= 0, true)
}
