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
        shell.log("blocks=" + md.blockList.length + " delegates=" + md.delegateCount()
            + " offthread=" + md.parsedOffThread)
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
