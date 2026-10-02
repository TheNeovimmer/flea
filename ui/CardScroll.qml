import QtQuick
import "." as Flea

// A card body taller than the window: this viewport clamps to the card and scrolls the rest by wheel,
// touchpad, keys and focus moves, with no bar and no lane, since a card never lists files.
Flickable {
    id: root

    default property alias content: holder.data
    // What the content wants, for the card to clamp against the window.
    readonly property real wanted: holder.childrenRect.height
    // Menus step the highlight instead of pixel scrolling: one row a notch through stepBy, one
    // row per stepRowHeight of gained touchpad travel, with no tail. See FastScrollHandler.
    property bool highlightSteps: false
    property real stepRowHeight: 0
    property var stepBy: null
    // The holder's drawn width, so a probe reads it without walking children.
    readonly property real holderWidth: holder.width

    clip: true
    contentWidth: width
    contentHeight: root.wanted
    boundsBehavior: Flickable.StopAtBounds
    // A highlight-stepped menu follows through reveal(); the Flickable takes no wheel itself.
    interactive: !root.highlightSteps

    // Tab into a field below the fold scrolls it into view, so a form is never typed into blind.
    function reveal(item) {
        if (!item || root.contentHeight <= root.height || !root.holds(item))
            return
        var top = item.mapToItem(holder, 0, 0).y
        var bottom = top + item.height
        if (top < root.contentY)
            root.contentY = Math.max(0, top)
        else if (bottom > root.contentY + root.height)
            root.contentY = Math.min(root.contentHeight - root.height, bottom - root.height)
    }

    function holds(item) {
        for (var it = item; it; it = it.parent) {
            if (it === holder)
                return true
        }
        return false
    }

    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() { root.reveal(root.Window.window.activeFocusItem) }
    }

    Flea.FastScrollHandler {
        id: wheel
        parent: root
        flickable: root
        stepMode: root.highlightSteps
        stepRowHeight: root.stepRowHeight
        stepBy: root.stepBy
    }

    // Drops every wheel remainder, so a menu opening never spends the last one's travel.
    function resetSteps() { wheel.resetSteps() }

    Item {
        id: holder
        // No lane: rows fill to the frame's padding on every surface using this.
        width: Math.max(0, root.width)
    }
}
