//@ pragma ShellId flea-markdown-html-test

import QtQuick
import Quickshell
import "flea" as Flea
import "markdown-html.js" as Checks
import "markdown-html-pictures.js" as Pictures

// tests/markdown-html.sh's harness: each fixture document through the real ui/PreviewMarkdown.qml, grabbed offscreen and judged on what it draws.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_HTML " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    readonly property string dir: Quickshell.env("FLEA_MDHTML_DIR")
    readonly property var names: Quickshell.env("FLEA_MDHTML_DOCS").split(",")
    readonly property string shotBase: Quickshell.env("XDG_RUNTIME_DIR") + "/markdown-html-" + Quickshell.processId
    readonly property int paneW: 560
    readonly property int paneH: 1060
    readonly property color ground: "#101315"
    // The pane draws a run on a line box this many times its text size (MarkdownText.boxRatio).
    readonly property real lineBoxRatio: 1.7
    // Each document gets this long to settle before it is declared stuck, and a poll runs once a frame.
    readonly property int docWatchdogMs: 90000
    readonly property int pollMs: 16
    property int step: -1
    property bool done: false
    property bool armed: false
    property var allFacts: ({})
    property var geo: null
    property string lastHeight: ""
    property int loadsBefore: 0
    // Informational only: what the settle cost, so a slow pathological document shows its time in the log.
    property double startedAt: 0
    property double readyAt: 0

    function rgb(c) { return [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)] }
    function hexRgb(s) { return [parseInt(s.slice(1, 3), 16), parseInt(s.slice(3, 5), 16), parseInt(s.slice(5, 7), 16)] }

    FloatingWindow {
        id: window
        implicitWidth: shell.paneW
        implicitHeight: shell.paneH + 60
        color: shell.ground

        Item {
            id: grabRoot
            width: shell.paneW
            height: shell.paneH

            Rectangle { anchors.fill: parent; color: shell.ground }

            Flea.PreviewMarkdown {
                id: md
                anchors.fill: parent
                active: true
                size: 1
                view: "rendered"
            }

            Image { id: shot; width: 1; height: 1; opacity: 0 }

            Canvas {
                id: probe
                width: shell.paneW
                height: shell.paneH
                opacity: 0
                onPaint: if (shell.armed && !shell.done) shell.analyze(getContext("2d"))
            }

            // The importer the pane's text uses, read back as plain text: a literal "![" here is an image Markdown never drew.
            TextEdit {
                id: plainProbe
                visible: false
                textFormat: TextEdit.MarkdownText
            }

            TextMetrics {
                id: hMetrics
                text: "H"
                font.family: Flea.Theme.font.family
                font.pixelSize: Flea.Theme.font.body
            }
        }
    }

    function rectOf(i) {
        var item = md.blockItem(i)
        if (!item)
            return { x: 0, y: 0, w: 0, h: 0 }
        var p = item.mapToItem(grabRoot, 0, 0)
        return { x: p.x, y: p.y, w: item.width, h: item.height }
    }

    // The pictures of one delegate, the badge row's own included: a row is an item holding an images list, and its children are the pictures.
    function pictures(item) {
        var found = []
        for (var k = 0; k < item.children.length; k++) {
            var kid = item.children[k]
            if (kid.visible && kid.status !== undefined && kid.paintedWidth !== undefined)
                found.push(kid)
            else if (kid.visible && kid.images !== undefined)
                found = found.concat(pictures(kid))
        }
        return found
    }

    function imagesReady() {
        for (var i = 0; i < md.blockList.length; i++) {
            var item = md.blockItem(i)
            if (!item)
                continue
            var pics = pictures(item)
            for (var k = 0; k < pics.length; k++) {
                if (pics[k].status !== Image.Ready)
                    return false
            }
        }
        return true
    }

    // One row picture's link and whether a tap and a hover handler answer for it.
    function linkOf(pic) {
        var tap = false, hover = false
        for (var d = 0; d < pic.data.length; d++) {
            if (pic.data[d].gesturePolicy !== undefined)
                tap = tap || pic.data[d].enabled
            if (pic.data[d].cursorShape !== undefined)
                hover = hover || pic.data[d].enabled
        }
        return { link: pic.spec.link === undefined ? "" : pic.spec.link, tap: tap, hover: hover }
    }

    function next() {
        step++
        shell.armed = false
        if (step >= names.length) {
            finish()
            return
        }
        lastHeight = ""
        startedAt = Date.now()
        readyAt = 0
        loadsBefore = md.loadRuns
        md.path = dir + "/" + names[step]
        poll.restart()
        watchdog.restart()
    }

    // Settled: this file's load landed and parsed, its pictures decoded and its content height held across two polls.
    Timer {
        id: poll
        interval: shell.pollMs
        repeat: true
        onTriggered: {
            if (!md.contentReady || md.loadRuns <= shell.loadsBefore || !shell.imagesReady())
                return
            if (shell.readyAt === 0)
                shell.readyAt = Date.now()
            md.bodyItem.forceLayout()
            var height = String(md.flickContentHeight)
            if (height !== shell.lastHeight) {
                shell.lastHeight = height
                return
            }
            poll.stop()
            shell.log("time " + shell.names[shell.step] + " parsed after " + (shell.readyAt - shell.startedAt) + " ms, laid out after "
                + (Date.now() - shell.startedAt) + " ms, parseRuns=" + md.parseRuns + " offThread=" + md.parsedOffThread)
            shell.capture()
        }
    }

    Timer {
        id: watchdog
        interval: shell.docWatchdogMs
        onTriggered: shell.fail(shell.names[shell.step] + " never settled: status=" + md.status + " ready=" + md.contentReady)
    }

    function capture() {
        var blocks = []
        var texts = []
        // Every block's text is kept for the content checks; geometry and ink are read only for the first CAPTURED_BLOCKS.
        for (var t = 0; t < md.blockList.length; t++)
            texts.push(String(md.blockList[t].text))
        for (var i = 0; i < md.blockList.length && i < Checks.CAPTURED_BLOCKS; i++) {
            var b = md.blockList[i]
            var r = rectOf(i)
            plainProbe.text = b.type === "run" ? String(b.text) : ""
            var row = b.type === "images" ? shell.pictures(md.blockItem(i)).map(shell.linkOf) : []
            blocks.push({ type: b.type, text: b.text, width: b.width, align: b.align, x: r.x, y: r.y, w: r.w, h: r.h,
                plain: plainProbe.getText(0, plainProbe.length), row: row })
        }
        var notice = md.noticeItem === undefined ? null : md.noticeItem
        // The notice is list content, so its place in the pane is mapped, not read from its own coordinates.
        var noticeAt = notice !== null ? notice.mapToItem(md, 0, 0) : null
        var noticeRect = notice !== null && notice.visible ? { x: noticeAt.x, y: noticeAt.y, w: notice.width, h: notice.height } : null
        geo = { name: names[step], w: shell.paneW, h: shell.paneH, ground: rgb(shell.ground), chrome: hexRgb(String(md.chromeHex)),
            blocks: blocks, texts: texts, blockGap: md.blockGap, lineBox: Math.round(Flea.Theme.font.body * shell.lineBoxRatio), hAdvance: Math.floor(hMetrics.advanceWidth),
            tooDeep: md.tooDeep, notice: noticeRect, noticeText: notice === null ? "" : notice.text }
        grabRoot.grabToImage(function (result) {
            var path = shell.shotBase + "-" + shell.step + ".png"
            if (!result.saveToFile(path)) {
                shell.fail("the grab could not be saved")
                return
            }
            shot.source = "file://" + path
        })
    }

    Connections {
        target: shot
        function onStatusChanged() {
            if (shot.status === Image.Ready) {
                shell.armed = true
                probe.requestPaint()
            } else if (shot.status === Image.Error) {
                shell.fail("the saved grab would not reload")
            }
        }
    }

    function analyze(ctx) {
        ctx.clearRect(0, 0, shell.paneW, shell.paneH)
        ctx.drawImage(shot, 0, 0)
        var px = ctx.getImageData(0, 0, shell.paneW, shell.paneH).data
        allFacts[geo.name] = Checks.facts(px, geo)
        shell.armed = false
        shot.source = ""
        Qt.callLater(shell.next)
    }

    function finish() {
        shell.done = true
        var chromeEqualsGround = String(md.chromeHex).toLowerCase() === "#101315"
        var results = Checks.verdict(allFacts).concat(Pictures.verdict(allFacts))
        if (chromeEqualsGround)
            results.push(["the theme chrome differs from the harness ground", false])
        var failures = 0
        for (var i = 0; i < results.length; i++) {
            if (!results[i][1])
                failures++
            shell.log((results[i][1] ? "ok " : "FAIL ") + results[i][0])
        }
        shell.log(results.length + " checks, " + failures + " failed")
        shell.quit()
    }

    function fail(why) {
        if (shell.done)
            return
        shell.done = true
        shell.log("FAIL " + why)
        shell.log("0 checks, 1 failed")
        shell.quit()
    }

    Component.onCompleted: {
        if (shell.dir.length === 0 || names.length === 0)
            fail("no fixture directory arrived in FLEA_MDHTML_DIR")
        else
            Qt.callLater(shell.next)
    }
}
