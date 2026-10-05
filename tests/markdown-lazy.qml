//@ pragma ShellId flea-markdown-lazy-test

import QtQuick
import Quickshell
import "flea" as Flea

// Render about 560 KiB from 2500 sections of five source blocks through the real lazy preview.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_LAZY " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property string fixture: Quickshell.env("FLEA_MARKDOWN_FIXTURE")
    property bool done: false

    FloatingWindow {
        id: window
        implicitWidth: 560
        implicitHeight: 1120
        color: "#101315"

        Flea.PreviewMarkdown {
            id: md
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1060
            active: true
            path: shell.fixture
            size: 1
            view: "rendered"
        }
    }

    Connections {
        target: md
        function onContentReadyChanged() { if (md.contentReady) Qt.callLater(shell.report) }
    }

    function report() {
        if (shell.done || !md.contentReady) return
        md.bodyItem.forceLayout()
        if (md.delegateCount() === 0) {
            shell.fail("no delegates after forceLayout")
            return
        }
        shell.log("blocks=" + md.blockList.length + " delegates=" + md.delegateCount()
            + " offthread=" + md.parsedOffThread)
        md.view = "source"
        Qt.callLater(shell.reportSource)
    }

    // The same 560 KiB as Source: a screenful of chunks is laid out, and the end of the list shows the file's last line.
    function reportSource() {
        var list = md.sourceItem
        list.forceLayout()
        var first = md.sourceChars
        list.positionViewAtEnd()
        list.forceLayout()
        var tail = md.rawText.split("\n").filter(function (l) { return l.indexOf("var section") === 0 }).pop()
        var reached = false
        for (var i = 0; i < list.contentItem.children.length; i++) {
            var row = list.contentItem.children[i]
            if (row.objectName === "sourceChunk" && String(row.label.text).indexOf(tail) >= 0)
                reached = true
        }
        shell.log("source chars=" + first + " total=" + md.rawText.length + " endlaid=" + md.sourceChars + " lastline=" + reached)
        shell.done = true
        shell.quit()
    }

    Component.onCompleted: {
        if (shell.fixture.length === 0) shell.fail("no fixture arrived in FLEA_MARKDOWN_FIXTURE")
        else if (md.contentReady) Qt.callLater(shell.report)
    }

    readonly property int watchdogMs: 30000
    Timer {
        interval: shell.watchdogMs
        repeat: false
        running: !shell.done
        onTriggered: shell.fail("watchdog waiting for Markdown contentReady")
    }

    function fail(why) {
        if (shell.done)
            return
        shell.done = true
        shell.log("FAIL " + why)
        shell.quit()
    }
}
