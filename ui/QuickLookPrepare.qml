import QtQuick
import Quickshell.Io
import "js/Kinds.js" as Kinds
import "js/ExtThumbs.js" as ExtThumbs
import "js/Markdown.js" as Markdown
import "js/MarkdownPrepared.js" as Prepared

// A cursor resting on a small local Markdown file reads and parses it into the one entry Quick Look takes, so Space only shows it.
// A moving cursor only restarts the timer; no figure is asked and no other file is read.
Item {
    id: root

    property var pane: null
    // False while Quick Look is open: the entry is for the next Space.
    property bool resting: true
    // The rest the preview column's own settle waits, so a sweep reads nothing.
    property int restMs: 120
    // What a suite reads: files read at rest, and the file whose parse the entry last took.
    property int reads: 0
    property string preparedPath: ""

    Timer {
        id: rest
        interval: root.restMs
        onTriggered: root.prepare()
    }

    Connections {
        target: root.pane
        function onCursorIndexChanged() { rest.restart() }
        function onRowsChanged() { rest.restart() }
        function onListInFlightChanged() { rest.restart() }
    }

    // Blocking by design: at most 64 KiB from local storage, read once the cursor has rested.
    FileView {
        id: file
        printErrors: false
        blockLoading: true
    }

    function prepare() {
        var pane = root.pane
        if (!root.resting || !pane || pane.listInFlight || ExtThumbs.present(pane.storageClass))
            return
        var row = pane.rowFor(pane.cursorIndex)
        if (!row || row.d || row.s > Prepared.MAX_BYTES || !Kinds.isMarkdown(row.n))
            return
        var path = pane.join(pane.path, row.n)
        file.path = path
        root.reads++
        var text = file.text()
        file.path = ""
        var dir = Markdown.dirOf(path)
        var chrome = Prepared.hexOf(Theme.color.background)
        var ink = Prepared.hexOf(Theme.color.foreground)
        if (text.length === 0 || text.length > Prepared.MAX_BYTES)
            return
        if (Prepared.take(path, text, dir, chrome, ink) === null) {
            // A parse that throws is Quick Look's to report on Space, so nothing is kept here.
            try {
                Prepared.store(path, text, dir, chrome, ink, Markdown.blocks(text, dir, chrome, ink))
            } catch (e) {
                return
            }
        }
        root.preparedPath = path
    }
}
