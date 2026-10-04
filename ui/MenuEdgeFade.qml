import QtQuick

// One edge of a menu that scrolls, fading the surface out where more rows wait: the Menus board's "Edges fade to say so".
Rectangle {
    // The card's own padding between its border and its rows, which the fade crosses before it reaches a cut row.
    property real inset: 0
    // How far the fade reaches past that padding into the row the edge cuts.
    property real reach: Theme.spacing.gap
    // The frame Rectangle's border width: the fade lies inside it, so the hairline frame stays whole, corners included.
    readonly property real frameBorder: parent.border.width
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: frameBorder
    anchors.rightMargin: frameBorder
    anchors.topMargin: frameBorder
    anchors.bottomMargin: frameBorder
    // Measured from the inner edge, so it still ends where the card's padding plus reach ends.
    height: inset + reach - frameBorder
    radius: Math.max(0, parent.radius - frameBorder)
    gradient: Gradient {
        GradientStop { position: 0; color: Theme.color.surface }
        GradientStop { position: 1; color: Qt.rgba(Theme.color.surface.r, Theme.color.surface.g, Theme.color.surface.b, 0) }
    }
}
