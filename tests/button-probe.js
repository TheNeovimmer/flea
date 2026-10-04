.pragma library

// The readers tests/button-members.qml holds the controls to A's numbers with: pure, over the items themselves.

// Sample input: rgba(Qt.rgba(1, 0.5, 0, 0.14)) answers "1,0.5,0,0.14".
function rgba(c) { return [c.r, c.g, c.b, c.a].map(function (v) { return Math.round(v * 1000) / 1000 }).join(",") }
function alphaOf(c) { return Math.round(c.a * 1000) / 1000 }
// A pressed control is scaled, so a position read through it carries float noise.
function thousandth(v) { return Math.round(v * 1000) / 1000 }

function find(item, name) {
    var stack = [item]
    while (stack.length > 0) {
        var o = stack.pop()
        if (o.objectName === name) return o
        var kids = o.children !== undefined ? o.children : []
        for (var i = 0; i < kids.length; i++) stack.push(kids[i])
    }
    return null
}

// How many items under one draw a border, so a frameless mark is proved by finding none.
function bordered(item) {
    var stack = [item]
    var out = 0
    while (stack.length > 0) {
        var o = stack.pop()
        if (o.border !== undefined && o.border.width > 0) out++
        var kids = o.children !== undefined ? o.children : []
        for (var i = 0; i < kids.length; i++) stack.push(kids[i])
    }
    return out
}

// What a DialogButton draws now, read off its own items; a control built any other way reads as missing, so its checks fail by name.
function read(button) {
    var frame = find(button, "buttonFrame")
    var wash = find(button, "buttonWash")
    var label = find(button, "buttonLabel")
    var ring = find(button, "buttonRing")
    if (!frame || !wash || !label || !ring) return { missing: button.toString(), outerHeight: button.height }
    var corner = ring.mapToItem(frame, 0, 0)
    var inner = wash.mapToItem(frame, 0, 0)
    return {
        outerHeight: button.height, frameColor: rgba(frame.border.color), frameWidth: frame.border.width, frameHeight: frame.height, frameFill: alphaOf(frame.color),
        ink: rgba(label.color), labelSize: label.font.pixelSize, washAlpha: alphaOf(wash.color),
        washInsetX: thousandth(inner.x), washInsetY: thousandth(inner.y), washShrink: thousandth(frame.width - wash.width),
        ringShown: ring.visible, ringWidth: ring.border.width, ringColor: rgba(ring.border.color),
        ringOutset: thousandth(-corner.x), scale: button.scale, opacity: button.opacity
    }
}
