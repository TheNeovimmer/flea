//@ pragma ShellId flea-markdown-memory-test

import QtQuick
import Quickshell
import "flea" as Flea

// Prove both Markdown Loaders activate, then unload for the shell-provided plain-text fixture.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_MEMORY " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property bool done: false
    property bool plain: false
    property string fixtureRoot: Quickshell.env("FLEA_MARKDOWN_MEMORY_ROOT")
    readonly property string fixture: fixtureRoot + (plain ? "/note.txt" : "/note.md")
    readonly property bool ready: plain
        ? look.status === "ready" && look.surfaceItem() !== null
            && look.surfaceItem().text.trim() === "plain text"
            && !column.textLoading && column.linesItem.shownText.trim() === "plain text"
        : look.markdownItem !== null && column.markdown !== null
            && look.markdownItem.contentReady && column.markdown.contentReady
    onReadyChanged: if (ready) Qt.callLater(shell.advance)
    readonly property int watchdogMs: 30000

    FloatingWindow {
        id: window
        implicitWidth: 560
        implicitHeight: 800
        color: "#101315"

        Flea.Preview {
            id: look
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 400
            active: true
            kind: "text"
            path: shell.fixture
            size: 10
        }

        Flea.PreviewColumn {
            id: column
            anchors.top: look.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 380
            row: ({ n: shell.plain ? "note.txt" : "note.md", d: false, t: true, s: 10, i: "text-x-generic" })
            path: shell.fixture
            meta: ({})
            kindName: "text"
        }
    }

    function advance() {
        if (shell.done || !shell.ready) return
        if (!shell.plain) {
            shell.log("positive lookMarkdown=built columnMarkdown=built contentReady=true")
            shell.plain = true
            Qt.callLater(shell.advance)
            return
        }
        if (look.markdownItem !== null || column.markdown !== null) {
            shell.fail("plain-text step retained a Markdown Loader")
            return
        }
        shell.log("lookMarkdown=null columnMarkdown=null fixture=" + shell.fixture)
        shell.done = true
        shell.quit()
    }

    Component.onCompleted: {
        if (shell.fixtureRoot.length === 0) shell.fail("no fixture root arrived")
        else if (shell.ready) Qt.callLater(shell.advance)
    }

    Timer {
        interval: shell.watchdogMs
        repeat: false
        running: !shell.done
        onTriggered: shell.fail("watchdog waiting for " + (shell.plain ? "plain-text readers and Loader teardown: look=" + look.status + " text=" + JSON.stringify(look.textShown()) + " columnState=" + column.rowState + " columnLoading=" + column.textLoading + " text=" + JSON.stringify(column.linesItem.shownText) : "both Markdown Loaders and contentReady"))
    }

    function fail(why) {
        if (shell.done)
            return
        shell.done = true
        shell.log("FAIL " + why)
        shell.quit()
    }
}
