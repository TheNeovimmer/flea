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
    property bool delayedCorpus: Quickshell.env("FLEA_MARKDOWN_DELAYED_CORPUS") === "1"
    property bool done: false
    property bool probesBuilt: false
    property bool draining: false
    property bool started: false
    readonly property int drainPollMs: 16
    readonly property int watchdogMs: 30000
    property var validationFailures: []
    property string counter: Quickshell.env("FLEA_MARKDOWN_COUNTER")

    // Wait for explicit Images in the preview, echo and resource probes to reach Ready or Error.
    function imagesSettled(item) {
        if (item.source !== undefined && item.asynchronous !== undefined
                && String(item.source) !== "" && item.status !== Image.Ready && item.status !== Image.Error)
            return false
        var children = item.children || []
        for (var i = 0; i < children.length; i++) {
            if (!imagesSettled(children[i]))
                return false
        }
        return true
    }

    // Sample: ![x](file:///pic.png) and <img src="file:///pic.png"> expose the Text image resources.
    function resourceUrls(item, urls) {
        if (item.textFormat === Text.MarkdownText) {
            var re = /!\[[^\]]*\]\(([^)]+)\)|<img\b[^>]*\bsrc=["']([^"']*)["']/g
            var hit = null
            while ((hit = re.exec(String(item.text))) !== null)
                urls.push(hit[1] || hit[2])
        }
        var children = item.children || []
        for (var i = 0; i < children.length; i++)
            resourceUrls(children[i], urls)
    }

    function startDrain() {
        if (started || !md.contentReady || md.blockList.length === 0)
            return
        if (!imagesSettled(root))
            return
        started = true
        var dir = Url.dirOf(fixture)
        var corpusText = JSON.stringify(md.blockList)
        if (corpusText.indexOf("R9_DROP_BODY") >= 0)
            validationFailures.push("malformed drop tag kept its body")
        if (corpusText.indexOf("R9_KEEP_BODY") < 0 || corpusText.indexOf("R9_TAIL") < 0)
            validationFailures.push("HTML whitespace control body or tag tail was lost")
        var paths = ["file://" + dir + "/../x.png", dir + "/notes/../../x.png",
            "file://" + dir + "/%2e%2e/x.png", dir + "/notes/%2e%2e/%2e%2e/x.png"]
        for (var i = 0; i < paths.length; i++) {
            if (Url.classifyImage(paths[i], dir).kind !== "dropped") {
                validationFailures.push("traversal accepted " + paths[i])
            }
        }
        if (Url.classifyImage("/etc/x.png", "relative").kind !== "dropped") {
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
        // Build resource probes after delegates, then wait for their native Image completion signals.
        Qt.callLater(function () {
            var urls = []
            resourceUrls(root, urls)
            resourceProbes.model = urls
            probesBuilt = true
            Qt.callLater(finishDrain)
        })
    }

    function finishDrain() {
        if (done || draining || !probesBuilt || !imagesSettled(root))
            return
        draining = true
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
            if (shell.delayedCorpus && delayedImage.status === Image.Loading)
                log("FAIL control overtook a Loading corpus Image")
            done = true
            log("drained, control GET landed")
            quit()
        }
        request.open("GET", counter + "/drain")
        request.send()
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

            Repeater {
                id: resourceProbes
                model: []
                delegate: Image {
                    required property string modelData
                    source: modelData
                    asynchronous: true
                }
            }

            Image {
                id: delayedImage
                source: shell.delayedCorpus ? shell.counter + "/delayed-corpus.png" : ""
                asynchronous: true
            }

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
                Repeater {
                    model: ["", "red"]
                    delegate: Text {
                        required property string modelData
                        required property int index
                        textFormat: Text.MarkdownText
                        text: Run.parseInline('$![x](' + shell.counter + '/math-chrome-' + index + '.png)$',
                            Url.dirOf(shell.fixture), {}, {}, modelData, '#c0caf5', [])
                    }
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
        interval: shell.drainPollMs
        repeat: true
        running: !shell.done
        onTriggered: {
            if (shell.started)
                shell.finishDrain()
            else
                shell.startDrain()
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
