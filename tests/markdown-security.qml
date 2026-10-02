//@ pragma ShellId flea-markdown-security-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/markdown-security.sh's harness: the real ui/PreviewMarkdown.qml over a
// generated hostile document, plus the reviewer's own method (every block's text
// fed straight into Text.MarkdownText), offscreen. Any image or stylesheet URL
// the preview resolves hits the suite's 127.0.0.1 counter; the verdict is that
// counter's file, read by the shell after this process quits. Quits itself.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_SECURITY " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property string fixture: Quickshell.env("FLEA_MARKDOWN_FIXTURE")
    property bool done: false

    FloatingWindow {
        id: window
        implicitWidth: 560
        implicitHeight: 1120
        color: "#101315"

        Item {
            id: root
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1080

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

            // The reviewer's method: every emitted block text rendered the way the
            // product renders it, so a URL blocks() missed still shows up as a
            // server hit. Fences draw verbatim in production, so they echo as
            // PlainText here too; runs, quotes, lists and tables echo as Markdown.
            Column {
                id: echo
                anchors.top: md.bottom
                width: 540
                Repeater {
                    model: md.blockList
                    delegate: Text {
                        width: 540
                        wrapMode: Text.Wrap
                        textFormat: modelData.type === "fence" ? Text.PlainText : Text.MarkdownText
                        text: {
                            if (modelData.type === "list")
                                return (modelData.items || []).join("\n")
                            if (modelData.type === "table") {
                                var cells = (modelData.head || []).concat.apply(
                                    modelData.head || [], modelData.rows || [])
                                return cells.join("\n")
                            }
                            return modelData.text || ""
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: settle
        interval: 3000
        repeat: false
        running: true
        onTriggered: {
            if (shell.fixture.length === 0)
                shell.fail("no fixture arrived in FLEA_MARKDOWN_FIXTURE")
            else if (!md.contentReady)
                shell.fail("the document never loaded")
            else {
                shell.log("blocks=" + md.blockList.length
                    + " run0=" + JSON.stringify(String(md.blockList[0].text || "").slice(0, 80)))
                drain.start()
            }
        }
    }

    // Localhost loads finish in milliseconds; the drain leaves a full second so a
    // missed URL has landed on the counter before this process quits.
    Timer {
        id: drain
        interval: 1500
        repeat: false
        onTriggered: {
            if (!shell.done) {
                shell.done = true
                shell.log("drained, quitting for the hit count")
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
