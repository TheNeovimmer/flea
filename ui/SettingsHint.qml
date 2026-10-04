import QtQuick

// A settings hint's type: the caption face, and for a board hint the board's line box of 1.5 times the caption, so a wrapped hint keeps the board's rhythm; the pane's footer line keeps the font's own line.
Text {
    property bool footer: false

    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    textFormat: Text.PlainText
    lineHeightMode: footer ? Text.ProportionalHeight : Text.FixedHeight
    lineHeight: footer ? 1 : SettingsMetrics.hintLine
}
