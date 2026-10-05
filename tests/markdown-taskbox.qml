import QtQuick
import "../ui/js/Markdown.js" as Markdown

// Draws the box of an open and of a closed task (the item text minus its word) through the real MarkdownText and saves the picture; tests/markdown-taskbox.py judges it.
Window {
    id: win
    visible: true
    width: 240
    height: 80
    color: "#101010"
    readonly property string module: Qt.resolvedUrl(Qt.application.arguments[Qt.application.arguments.length - 2])
    readonly property string picture: Qt.application.arguments[Qt.application.arguments.length - 1]
    readonly property int rowHeight: 40
    property bool grabbed: false

    Item {
        id: sheet
        width: win.width
        height: win.height
    }

    // The first rendered frame holds the laid-out rows, so the grab waits for it and never for a clock.
    onAfterRendering: {
        if (win.grabbed)
            return
        win.grabbed = true
        sheet.grabToImage(function (result) {
            result.saveToFile(win.picture)
            Qt.quit()
        })
    }

    Component.onCompleted: {
        var list = Markdown.blocks("- [ ] a\n- [x] a\n", "/doc", "#181825", "#c0caf5")[0]
        for (var i = 0; i < list.items.length; i++)
            Qt.createQmlObject('import QtQuick\nimport "' + win.module + '" as Flea\nFlea.MarkdownText {\ny: ' + i * win.rowHeight
                + '\nwidth: 200\ncolor: "#cccccc"\ntext: ' + JSON.stringify(list.items[i].replace(/ a$/, "")) + '\n}', sheet)
    }
}
