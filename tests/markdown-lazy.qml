//@ pragma ShellId flea-markdown-lazy-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/markdown-lazy.sh's harness: the real ui/PreviewMarkdown.qml over a
// generated 1 MiB README, offscreen. The parse must arrive off the UI thread
// and the view must instantiate only visible blocks plus its bounded cache,
// never the whole document. Quits itself.
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

    Timer {
        id: settle
        interval: 4000
        repeat: false
        running: true
        onTriggered: {
            if (shell.fixture.length === 0)
                shell.fail("no fixture arrived in FLEA_MARKDOWN_FIXTURE")
            else if (!md.contentReady)
                shell.fail("the document never loaded")
            else {
                shell.log("blocks=" + md.blockList.length
                    + " delegates=" + md.delegateCount()
                    + " offthread=" + md.parsedOffThread)
                shell.done = true
                shell.quit()
            }
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
