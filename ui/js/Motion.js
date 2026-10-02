.pragma library

// Every Flea transition uses Omarchy's Easing.OutCubic, 180 ms to reveal and 140 ms to hide, never lengthened to match the curve.
// Scroll, cursor and hover fills stay animation-free, except Scroll.js touchpad momentum; reduced motion snaps.

var durMs = {
    // A reveal reads slower than a hide.
    open: 180,
    close: 140
}

// Open rises into place from this far below its resting position; close does not translate,
// opacity only (see the Preview/ShareBrowser/NetworkDialog verticalCenterOffset/y bindings).
var translateUpPx = 10
