import QtQuick

// One edge of a menu that scrolls, fading the surface out where more rows wait: the Menus board's "Edges fade to say so".
Rectangle {
    // The card's own padding between its border and its rows, which the fade crosses before it reaches a cut row.
    property real inset: 0
    // How far the fade reaches past that padding into the row the edge cuts.
    property real reach: Theme.spacing.gap
    width: parent.width
    height: inset + reach
    gradient: Gradient {
        GradientStop { position: 0; color: Theme.color.surface }
        GradientStop { position: 1; color: Qt.rgba(Theme.color.surface.r, Theme.color.surface.g, Theme.color.surface.b, 0) }
    }
}
