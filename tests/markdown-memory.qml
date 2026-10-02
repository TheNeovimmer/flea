//@ pragma ShellId flea-markdown-memory-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/markdown-memory.sh's harness: the Markdown preview costs nothing at
// settle when no Markdown file is shown. Quick Look's bar+pane and the column's
// pane live behind file-path Loaders that stay unbuilt, so no Markdown object
// and no Layouts module loads. Quits itself.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_MEMORY " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property bool done: false

    FloatingWindow {
        id: window
        implicitWidth: 560
        implicitHeight: 800
        color: "#101315"

        // A text file that is not Markdown: the closest settle gets to one.
        Flea.Preview {
            id: look
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 400
            active: true
            kind: "text"
            path: "/tmp/flea-markdown-memory-note.txt"
            size: 10
        }

        Flea.PreviewColumn {
            id: column
            anchors.top: look.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 380
            row: ({ n: "note.txt", d: false, t: true, s: 10 })
            kindName: "text"
        }
    }

    Timer {
        id: settle
        interval: 2500
        repeat: false
        running: true
        onTriggered: {
            shell.log("lookMarkdown=" + (look.markdownItem === null ? "null" : "built")
                + " columnMarkdown=" + (column.markdown === null ? "null" : "built")
                + " rowState=" + column.rowState + " isMdRow=" + column.isMarkdownRow
                + " state=" + column.previewState)
            shell.done = true
            shell.quit()
        }
    }

    Timer {
        interval: 30000
        repeat: false
        running: !shell.done
        onTriggered: shell.fail("the watchdog outlived the verdict")
    }

    function fail(why) {
        if (shell.done)
            return
        shell.done = true
        shell.log("FAIL " + why)
        shell.quit()
    }
}
