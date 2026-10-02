//@ pragma ShellId flea-markdown-security-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/MdRun.js" as Run
import "flea/js/MdUrl.js" as Url
import "flea/js/MdResolve.js" as Resolve
import "flea/js/MdHtml.js" as Html

// Render the preview and every emitted block offscreen; the shell checks the counter after the control GET handshake.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_SECURITY " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property string fixture: Quickshell.env("FLEA_MARKDOWN_FIXTURE")
    property bool done: false
    property bool started: false
    readonly property int watchdogMs: 30000
    property var validationFailures: []
    property string counter: Quickshell.env("FLEA_MARKDOWN_COUNTER")

    function startDrain() {
        if (started || !md.contentReady || md.blockList.length === 0)
            return
        started = true
        var dir = Url.dirOf(fixture)
        var paths = ["file://" + dir + "/../x.png", dir + "/notes/../../x.png",
            "file://" + dir + "/%2e%2e/x.png", dir + "/notes/%2e%2e/%2e%2e/x.png"]
        for (var i = 0; i < paths.length; i++) {
            if (Url.classifyImage(paths[i], dir).kind !== "dropped") {
                validationFailures.push("traversal accepted " + paths[i])
            }
        }
        if (Url.classifyImage("/etc/x.png", "").kind !== "dropped") {
            validationFailures.push("unknown document folder accepted absolute path")
        }
        var hostTags = ['<img src="http://a%3Cb%3Ex/x">',
            '<img src="http://%3Cimg%20src=http%26%2347%3B%26%2347%3B127.0.0.1/x">']
        for (var h = 0; h < hostTags.length; h++) {
            if (Html.sanitizeTag(hostTags[h], dir, []).emit.indexOf("<") >= 0)
                validationFailures.push("host placeholder emitted markup " + h)
        }
        var links = [Resolve.resolvePair("x", "javascript:alert(1)", false, dir, "#c0caf5", []),
            Resolve.resolvePair("x", "https://x", false, dir, "", [])]
        for (var l = 0; l < links.length; l++) {
            if (links[l].indexOf("[") >= 0 || links[l].indexOf("<a ") >= 0)
                validationFailures.push("rejected target emitted anchor syntax " + l)
        }
        log("blocks=" + md.blockList.length)
        // Start the control after the corpus delegates have been built in this event turn.
        Qt.callLater(function () {
            control.text = "![control](" + counter + "/control.png)"
            var request = new XMLHttpRequest()
            request.onreadystatechange = function () {
                if (request.readyState !== XMLHttpRequest.DONE)
                    return
                if (request.status !== 200) {
                    fail("control handshake failed " + request.status)
                    return
                }
                for (var f = 0; f < validationFailures.length; f++)
                    log("FAIL " + validationFailures[f])
                done = true
                log("drained, control GET landed")
                quit()
            }
            request.open("GET", counter + "/drain")
            request.send()
        })
    }

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
                onContentReadyChanged: Qt.callLater(shell.startDrain)
                onBlockListChanged: Qt.callLater(shell.startDrain)
            }

            // Echo every block through the product text format; fences stay PlainText, and prose uses MarkdownText.
            Column {
                id: echo
                Text {
                    id: control
                    textFormat: Text.MarkdownText
                }
                Text {
                    textFormat: Text.MarkdownText
                    text: Run.parseInline('!<bogus>[x](' + shell.counter + '/empty-tag.png)',
                        Url.dirOf(shell.fixture), {}, {}, '#181825', '', [])
                }
                Text {
                    textFormat: Text.MarkdownText
                    text: Run.parseInline('!<!--gap-->[x](' + shell.counter + '/empty-comment.png)',
                        Url.dirOf(shell.fixture), {}, {}, '#181825', '', [])
                }
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
        interval: shell.watchdogMs
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
