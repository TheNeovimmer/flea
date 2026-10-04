import QtQuick
import qs.Commons
import "." as Flea
import "js/Buttons.js" as Buttons

// A live chrome control inks in foreground; an active one uses the accent and the keyboard draws a 2 px foreground ring.
Item {
    id: root

    property string glyph: "file"
    property bool active: false
    property bool keyboardFocused: false
    // False while something the chrome sits under takes the pointer; the handlers stop, the drawing does not.
    property bool inputLive: true
    property color restingColor: Theme.color.foreground
    // DragThreshold lets a drag that starts on a chrome bar button move the window; an overlay's instance passes ReleaseWithinBounds.
    property int gesturePolicy: TapHandler.DragThreshold
    property real glyphSize: Theme.chromeMarkSize
    // Rows at the bottom of the hit box that a strip's own rule takes; the ring keeps a hairline clear of them and the glyph stays put.
    property int ruleRows: 0

    signal activated()

    // A control with nowhere to go keeps its slot so the bar never reflows, and says so by dimming.
    property real disabledOpacity: Theme.disabledOpacity

    property string accessName: {
        if (root.glyph === "arrow-left")
            return "Back"
        if (root.glyph === "arrow-up")
            return "Parent folder"
        if (root.glyph === "search")
            return "Search"
        if (root.glyph === "list")
            return "List view"
        if (root.glyph === "columns")
            return "Columns view"
        if (root.glyph === "grid")
            return "Grid view"
        return root.glyph
    }

    // The pointer's own state, read by Quick Look's IPC and by the native capture harness to prove a driven hover or press landed.
    readonly property bool hovered: hover.hovered
    readonly property bool pressed: tap.pressed
    // The ring and the glyph, read by tests/chromering.sh.
    readonly property Item ringItem: ring
    readonly property Item markItem: mark

    // The mark stays the chrome token; the hit box is at least 24 px wide and the strip's height.
    implicitWidth: Math.max(Theme.hitMin, Theme.chromeMarkSize)
    implicitHeight: Theme.chromeHeight
    scale: tap.pressed && root.enabled && !Theme.reducedMotion ? 0.96 : 1

    Accessible.role: Accessible.Button
    Accessible.name: root.accessName
    Accessible.onPressAction: if (root.enabled) root.activated()

    Behavior on scale {
        enabled: !Theme.reducedMotion
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    // ButtonSystem040 A: the keyboard rings the mark, 24 square, centred in the rows above a strip's rule and trimmed to a hairline clear and the glyph's parity.
    Item {
        id: ringBand
        width: root.width
        height: root.height - root.ruleRows
        Rectangle {
            id: ring
            readonly property int room: Math.min(Math.max(Theme.hitMin, root.glyphSize), ringBand.height - 2 * Theme.spacing.hairline)
            anchors.centerIn: parent
            width: ring.room - (ring.room - root.glyphSize) % 2
            height: width
            color: "transparent"
            border.width: Buttons.RING
            border.color: Theme.color.foreground
            visible: root.keyboardFocused && root.enabled
        }
    }

    Flea.Glyph {
        id: mark
        anchors.centerIn: parent
        width: root.glyphSize
        height: root.glyphSize
        name: root.glyph
        color: !root.enabled ? Theme.color.muted
             : root.active ? Theme.color.accent
             : root.keyboardFocused ? Theme.color.foreground : root.restingColor
        opacity: root.enabled ? 1 : root.disabledOpacity
    }

    HoverHandler {
        id: hover
        enabled: root.inputLive
        cursorShape: Qt.PointingHandCursor
    }

    // overlay-tap-exempt: the instance chooses, and tests/shellload.sh holds every overlay's instance to ReleaseWithinBounds.
    TapHandler {
        id: tap
        enabled: root.inputLive
        acceptedButtons: Qt.LeftButton
        gesturePolicy: root.gesturePolicy
        onTapped: root.activated()
    }
}
