//@ pragma ShellId flea-markdown-security-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/MdRun.js" as Run
import "flea/js/MdUrl.js" as Url
import "flea/js/MdResolve.js" as Resolve
import "flea/js/MdHtml.js" as Html
import "flea/js/MdBlocks.js" as Blocks
import "flea/js/MdLink.js" as Link
import "mdfence.js" as Fence

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
    // Drain polls the Source view may take to load the corpus; past them the run fails under its own name.
    readonly property int sourceLoadPolls: 600
    property int sourcePolls: 0
    readonly property int watchdogMs: 30000
    readonly property int referenceFormCount: 7
    readonly property int referenceContextCount: 9
    readonly property int expectedReferences: referenceFormCount * referenceContextCount
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

    // Sample: ![x](file:///pic.png) and <img src="file:///pic.png"> expose Text image resources, unless inside a fence (code).
    function resourceUrls(item, urls) {
        if (item.textFormat === Text.MarkdownText) {
            var re = /!\[[^\]]*\]\(([^)]+)\)|<img\b[^>]*\bsrc=["']([^"']*)["']/g
            var hit = null
            var drawnText = Fence.withoutFences(item.text)
            while ((hit = re.exec(drawnText)) !== null)
                urls.push(hit[1] || hit[2])
        }
        var children = item.children || []
        for (var i = 0; i < children.length; i++)
            resourceUrls(children[i], urls)
    }

    // Sample: <!-- fullref in alone --> followed by ![pic][ridf14c0] must resolve its own f14c0/x.png definition.
    function referenceResolution(source, dir, counter) {
        var defs = Blocks.collectReferences(source).defs
        var cases = /<!-- (fullref|collapsed|shortcut|multiline|spacelabel|quotedef|listdef) in [a-z0-9]+ -->\n([\s\S]*?)(?=<!--|$)/g
        var hit = null
        var total = 0
        var resolved = 0
        while ((hit = cases.exec(source)) !== null) {
            total++
            var use = /!\[([^\]]+)\](?:\[([^\]]*)\])?/.exec(hit[2])
            if (use === null)
                continue
            var label = use[2] || use[1]
            var key = Link.normalizeLabel(label)
            var path = /(f[0-9]+c[0-9]+)$/.exec(key)
            var expected = path === null ? "" : counter + "/" + path[1] + "/x.png"
            if (expected === "" || defs[key] !== expected)
                continue
            // Probe each raw use with the collected definition; the full corpus retains its code and table controls.
            var parsed = Blocks.blocks(use[0] + "\n\n[" + label + "]: " + defs[key], dir, "#181825", "#c0caf5")
            if (parsed.length === 1 && parsed[0].type === "remote" && parsed[0].host === Url.hostOf(expected))
                resolved++
        }
        return { total: total, resolved: resolved }
    }

    function startDrain() {
        if (started || !md.contentReady || md.blockList.length === 0)
            return
        if (!imagesSettled(root))
            return
        started = true
        var dir = Url.dirOf(fixture)
        var references = referenceResolution(md.rawText, dir, counter)
        log("references=" + references.resolved + "/" + references.total)
        if (references.total !== expectedReferences || references.resolved !== expectedReferences) {
            fail("reference forms did not all resolve, expected " + expectedReferences)
            return
        }
        log("reference forms resolved")
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
        // A destination spelled through references reads as a refused scheme after one decode or several, so none becomes a link, even around an image.
        var spelled = ["&amp;#106;avascript:alert(1)", "javascript&amp;colon;alert(1)", "&amp;#x6a;avascript&amp;colon;alert(1)", "java&amp;Tab;script:alert(1)",
            "javascript&amp;amp;colon;alert(1)", "data&amp;colon;text/html,x"]
        for (var sp = 0; sp < spelled.length; sp++) {
            var spelledText = JSON.stringify(Blocks.blocks("[![a](p.png)](" + spelled[sp] + ")\n[b](" + spelled[sp] + ")\n", dir, "#181825", "#c0caf5"))
            if (spelledText.indexOf("](") >= 0 || spelledText.indexOf("<a ") >= 0)
                validationFailures.push("refused scheme spelled through references became a link " + sp)
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

    // Sample: the Source view's Flickable holds one visible Text whose text is the whole file.
    function sourceTextItem(item) {
        if (item.textFormat !== undefined && item.visible && String(item.text) === sourceView.rawText)
            return item
        var children = item.children || []
        for (var i = 0; i < children.length; i++) {
            var found = sourceTextItem(children[i])
            if (found)
                return found
        }
        return null
    }

    function finishDrain() {
        if (done || draining || !probesBuilt || !imagesSettled(root))
            return
        if (sourceView.rawText.length === 0) {
            if (++sourcePolls > sourceLoadPolls)
                fail("Source view never loaded the corpus")
            return
        }
        draining = true
        // The zero requests count only over text the Source view shows, and plain text is what keeps it from asking.
        var drawn = sourceTextItem(sourceView)
        if (sourceView.view !== "source" || !drawn)
            validationFailures.push("Source view shows no Text holding the corpus")
        else if (drawn.textFormat !== Text.PlainText)
            validationFailures.push("Source view Text is not plain text")
        else if (String(drawn.text).indexOf("![front](") < 0 || String(drawn.text).indexOf("![math](") < 0)
            validationFailures.push("Source view Text lacks the front matter and display math placements")
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

            // Source view draws the raw file, front matter and display math included, as plain text.
            Flea.PreviewMarkdown {
                id: sourceView
                anchors.top: parent.top
                anchors.left: parent.left
                width: 200
                height: 200
                active: true
                path: shell.fixture
                size: 1
                view: "source"
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
