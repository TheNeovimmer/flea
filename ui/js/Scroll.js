.pragma library

// The wheel's arithmetic, kept pure so tests/js/scroll.js can drive it without a Flickable.

// One discrete notch is 120 units of angleDelta, Qt's own convention for a wheel click.
var NOTCH_UNITS = 120
// Qt's own lines per notch when the platform reports none: the one fallback, so the handler passes the raw hint.
var DEFAULT_LINES = 3
// A scrollbar sits above a view's delegates and its FastScrollHandler (z 1000), so it takes its own presses.
var BAR_Z = 2000
// A dragged handle's MouseArea moves onto the window's content item, above everything that window draws.
var GRAB_Z = 1000000
// Less than half a pixel of range is rounding in the layout, not content worth a bar.
var OVERFLOW_PX = 0.5

// How far a wheel event moves the content: a mouse notch is the platform's lines times
// notchPx times the multiplier. A touchpad never reaches here, see touchDistance below.
// Sample input: pixelDeltaY 0, angleDeltaY -120, lines 3, notchPx 24, multiplier 4 gives -288.
function distance(pixelDeltaY, angleDeltaY, lines, notchPx, multiplier) {
    var pixels = Number(pixelDeltaY) || 0
    if (pixels !== 0)
        return pixels
    var perNotch = Number(lines) > 0 ? Number(lines) : DEFAULT_LINES
    return (Number(angleDeltaY) || 0) / NOTCH_UNITS * perNotch * notchPx * multiplier
}

// GM 2026-10-01: touchpad input answers Finder's feel, so the Motion.js animation-free rule and the old
// touchpad 1:1 no longer hold for it; a mouse wheel notch is unchanged. Touchpad gain is GTK4's own
// factor, what gtkscrolledwindow.c multiplies touchpad deltas and fling velocity by.
var TOUCH_GAIN = 2.5
// Apple's curve: velocity decays by 0.998 per millisecond, so the tail is about 0.5 s of lift velocity.
var MOMENTUM_DECAY = 0.998
// The lift velocity is measured over the stroke's last 100 ms by arrival time, QML has no timestamp.
var VELOCITY_WINDOW_MS = 100
// Two events in one millisecond take the floor, so they cannot fling.
var MIN_SPAN_MS = 16
// 6 px/ms coasts about 3000 px, two screens, so a 1 ms double event cannot fling further.
var MAX_V_PX_PER_MS = 6
// Below half a pixel a 60 Hz frame, where the crawl is no longer visible.
var STOP_V_PX_PER_MS = 0.03
// Injected for the headless probe; production reads the wall clock.
var testNowMs = -1
function now() {
    return testNowMs >= 0 ? testNowMs : Date.now()
}

// A touchpad event is any event whose phase is not Qt.NoScrollPhase (0); a wheel carries none.
function isTouchpad(phase) {
    return Number(phase) !== 0
}

// A touchpad stroke moves by pixelDelta only, never angleDelta: a sub-pixel frame arrives as
// pixelDelta 0 with a nonzero angleDelta and must move nothing, never a wheel notch.
function touchDistance(pixelDelta) {
    var pixels = Number(pixelDelta) || 0
    if (pixels === 0)
        return 0
    return pixels * TOUCH_GAIN
}

// The handler's one entry: touchpad by pixels with gain, a wheel by the notch rule.
function strokeDistance(pixelDelta, angleDelta, phase, lines, notchPx, multiplier) {
    if (isTouchpad(phase))
        return touchDistance(pixelDelta)
    return distance(pixelDelta, angleDelta, lines, notchPx, multiplier)
}

// One tail state per Flickable, shared by its body handler and its scrollbar lane handler.
var _tails = []
function tailState(view, create) {
    for (var i = 0; i < _tails.length; i++)
        if (_tails[i].view === view)
            return _tails[i].state
    if (!create)
        return null
    var made = { samples: [], vx: 0, vy: 0, active: false, lastY: null, lastX: null, overY: 0, overX: 0, retActive: false, retElapsed: 0, retDur: 0, retFromY: 0, retToY: 0, retFromX: 0, retToX: 0 }
    _tails.push({ view: view, state: made })
    return made
}

function stopTail(view) {
    var found = tailState(view, false)
    if (found !== null) {
        found.active = false
        found.vx = 0
        found.vy = 0
        found.samples = []
    }
}

function forgetTail(view) {
    for (var i = 0; i < _tails.length; i++)
        if (_tails[i].view === view) {
            _tails.splice(i, 1)
            return
        }
}

function pushSample(view, t, dx, dy) {
    // dx is across (horizontal), dy is down (vertical), both gained pixels.
    var found = tailState(view, true)
    found.samples.push({ t: Number(t) || 0, x: Number(dx) || 0, y: Number(dy) || 0 })
    while (found.samples.length > 0 && found.samples[0].t <= Number(t) - VELOCITY_WINDOW_MS - 50)
        found.samples.shift()
}

// The stroke's velocity over the last 100 ms of deltas; fingers paused before the lift give none.
function liftVelocity(samples, endTime) {
    var end = Number(endTime) || 0
    var xs = 0, ys = 0, first = -1, last = -1, n = 0
    for (var i = 0; i < samples.length; i++) {
        var s = samples[i]
        if (s.t > end - VELOCITY_WINDOW_MS && s.t <= end) {
            xs += s.x
            ys += s.y
            if (first < 0)
                first = s.t
            last = s.t
            n += 1
        }
    }
    if (n === 0)
        return { vx: 0, vy: 0 }
    var span = Math.max(MIN_SPAN_MS, last - first)
    var vx = xs / span, vy = ys / span
    var speed = Math.sqrt(vx * vx + vy * vy)
    if (speed > MAX_V_PX_PER_MS) {
        vx *= MAX_V_PX_PER_MS / speed
        vy *= MAX_V_PX_PER_MS / speed
        speed = MAX_V_PX_PER_MS
    }
    if (speed <= STOP_V_PX_PER_MS)
        return { vx: 0, vy: 0 }
    return { vx: vx, vy: vy }
}

// Wheel-space pixels travelled in ms at v0, the closed form of the decay.
function tailTravel(v0, ms) {
    var v = Number(v0) || 0
    var t = Math.max(0, Number(ms) || 0)
    if (v === 0 || t === 0)
        return 0
    return v * (Math.pow(MOMENTUM_DECAY, t) - 1) / Math.log(MOMENTUM_DECAY)
}

// The whole tail of v0 until it falls below the stop speed, as a positive distance.
function tailTotal(v0) {
    var v = Math.abs(Number(v0) || 0)
    if (v <= STOP_V_PX_PER_MS)
        return 0
    return (v - STOP_V_PX_PER_MS) / -Math.log(MOMENTUM_DECAY)
}

// One frame's exact integral at v over dtMs, so summed frames equal the closed form.
function tailStep(v, dtMs) {
    var vel = Number(v) || 0
    var dt = Math.max(0, Number(dtMs) || 0)
    if (vel === 0 || dt === 0)
        return { dx: 0, v: 0 }
    var grown = Math.pow(MOMENTUM_DECAY, dt)
    return { dx: vel * (grown - 1) / Math.log(MOMENTUM_DECAY), v: vel * grown }
}

function tailSpeed(vx, vy) {
    return Math.sqrt(Math.pow(Number(vx) || 0, 2) + Math.pow(Number(vy) || 0, 2))
}

function tailLive(vx, vy) {
    return tailSpeed(vx, vy) > STOP_V_PX_PER_MS
}

// A content position kept inside the Flickable: never above its origin less the leading
// margin, never past its last page plus the trailing one. A grid with a gap margin rests at -gap.
function bounded(value, originY, contentHeight, viewHeight, startMargin, endMargin) {
    var lim = limits(originY, contentHeight, viewHeight, startMargin, endMargin)
    return Math.max(lim.min, Math.min(lim.max, value))
}

// Apple's rubber-band: UIKit/AppKit use 0.55, so shown travel stays under the viewport length.
var RESIST_K = 0.55
// Shown overscroll for raw travel x past the bound over viewport d: 0 at 0, monotone, under d.
function overResist(x, d) {
    var raw = Math.max(0, Number(x) || 0)
    var len = Math.max(0, Number(d) || 0)
    if (raw === 0 || len === 0)
        return 0
    return (1 - 1 / (raw * RESIST_K / len + 1)) * len
}
// The bounds a content sits in: min origin less the leading margin, max last page plus the
// trailing one, short content pins to min. Margins default to 0, so margin-less callers read as before.
function limits(origin, contentLength, viewportLength, startMargin, endMargin) {
    var lead = Number(startMargin) || 0
    var min = (Number(origin) || 0) - lead
    var max = Math.max(min, min + lead + Math.max(0, Number(contentLength) || 0) - Math.max(0, Number(viewportLength) || 0) + (Number(endMargin) || 0))
    return { min: min, max: max }
}
// Margin-aware bounds off a Flickable itself, so grid and list call sites cannot drift apart.
function limitsY(f) { return limits(f.originY, f.contentHeight, f.height, f.topMargin, f.bottomMargin) }
function limitsX(f) { return limits(f.originX, f.contentWidth, f.width, f.leftMargin, f.rightMargin) }
// No range, no delta: a vertical list reports contentWidth -1, so any x would steal the lift's tail.
function rangesX(f) { return (Number(f.contentWidth) || 0) + (Number(f.leftMargin) || 0) + (Number(f.rightMargin) || 0) - Math.max(0, Number(f.width) || 0) > 0 }
function rangesY(f) { return (Number(f.contentHeight) || 0) + (Number(f.topMargin) || 0) + (Number(f.bottomMargin) || 0) - Math.max(0, Number(f.height) || 0) > 0 }
// Past the bound the tail brakes hard, so the overshoot peaks in a few frames like Finder.
var OVER_DECAY = 0.98
function overDecel(v, dtMs) { return (Number(v) || 0) * Math.pow(OVER_DECAY, Math.max(0, Number(dtMs) || 0)) }
// OutCubic return step: at elapsed past dur lands on to, so the overscroll reaches its bound.
function returnAt(from, to, elapsed, dur) {
    var t = Math.max(0, Math.min(1, Number(elapsed) / Math.max(1, Number(dur) || 1)))
    var k = 1 - Math.pow(1 - t, 3)
    return Number(from) + (Number(to) - Number(from)) * k
}

// The lane every listing reserves at its right edge so rows never reflow under the bar.
// Sample input: lane(14) is 14, the board's own lane at base size 14.
function lane(rowPaddingX) {
    return Math.max(0, Number(rowPaddingX) || 0)
}

// The width a scrolling listing's content may use: the view less the lane it always keeps clear.
// Sample input: contentWidth(700, 14) is 686, a 700 px listing holding 686 px of rows.
function contentWidth(viewWidth, rowPaddingX) {
    return Math.max(0, (Number(viewWidth) || 0) - lane(rowPaddingX))
}

// Whether a wheel event is consumed: only when it actually moved the content, so an event at the
// edge keeps propagating to whatever holds this Flickable.
function moved(previous, current) {
    return Math.abs(current - previous) > 0.01
}

// Geometry over the Flickable's own range, never its delegates, so a 100,000-row model costs what a short one does.
function range(contentLength, viewportLength) {
    return Math.max(0, (Number(contentLength) || 0) - Math.max(0, Number(viewportLength) || 0))
}

function handleLength(trackLength, contentLength, viewportLength, minimumLength) {
    var track = Math.max(0, Number(trackLength) || 0)
    var content = Math.max(0, Number(contentLength) || 0)
    var viewport = Math.max(0, Number(viewportLength) || 0)
    if (track === 0 || content <= viewport || content === 0)
        return track
    return Math.min(track, Math.max(Math.max(0, Number(minimumLength) || 0), track * viewport / content))
}

// Finder's overlay scroller at base size 14 (the 0.3.3 design canvas): knob widths, its inset from the edge, in px.
var KNOB_REST_PX = 6
var KNOB_WIDE_PX = 10
var KNOB_INSET_PX = 2
// Alphas of the theme's foreground: the knob at rest, with the pointer in the lane, pressed; the track fill.
var KNOB_ALPHA = 0.5
var KNOB_HOVER_ALPHA = 0.6
var KNOB_PRESSED_ALPHA = 0.7
var TRACK_ALPHA = 0.05

// The thumb follows Hyprland rounding: square at 0, clamped at half the thinner side.
function knobRadius(cornerRadius, width, height) {
    var rounding = Number(cornerRadius) || 0
    if (rounding <= 0)
        return 0
    var half = Math.min(Math.max(0, Number(width) || 0), Math.max(0, Number(height) || 0)) / 2
    return Math.min(rounding, half)
}
// Finder's timing: shown this long after the view stops, then faded out over FADE_MS.
var HOLD_MS = 1000
var FADE_MS = 300

// Shown while the view moves, the pointer is in the lane or a press is down, and never over content that fits.
function revealed(overflow, moving, inLane, pressed) {
    return !!overflow && (!!moving || !!inLane || !!pressed)
}

// A track press puts the knob's centre under the pointer, Finder's jump to the spot clicked, clamped to the travel.
function jumpOffset(at, handleLengthValue, travelLength) {
    var room = Math.max(0, Number(travelLength) || 0)
    return Math.max(0, Math.min(room, (Number(at) || 0) - (Number(handleLengthValue) || 0) / 2))
}

// How far the handle can move; none on a track no longer than the minimum handle, where a drag moves nothing.
function travel(trackLength, contentLength, viewportLength, minimumLength) {
    return Math.max(0, (Number(trackLength) || 0) - handleLength(trackLength, contentLength, viewportLength, minimumLength))
}

function handleOffset(contentPosition, origin, contentLength, viewportLength, trackLength, minimumLength) {
    var room = travel(trackLength, contentLength, viewportLength, minimumLength)
    var span = range(contentLength, viewportLength)
    if (room === 0 || span === 0)
        return 0
    var at = Math.max(0, Math.min(span, (Number(contentPosition) || 0) - (Number(origin) || 0)))
    return room * at / span
}

function positionForHandle(handleOffsetValue, origin, contentLength, viewportLength, trackLength, minimumLength) {
    var room = travel(trackLength, contentLength, viewportLength, minimumLength)
    var span = range(contentLength, viewportLength)
    if (room === 0 || span === 0)
        return Number(origin) || 0
    var at = Math.max(0, Math.min(room, Number(handleOffsetValue) || 0))
    return (Number(origin) || 0) + span * at / room
}
