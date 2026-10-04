//@ pragma ShellId flea-mdspec-shots

import QtQuick
import Quickshell
import "flea" as Flea

// One PNG of the real ui/PreviewMarkdown.qml per spec example, grabbed offscreen at the board's body size; tests/mdspec-shots.sh sets it up.
ShellRoot {
    id: shell

    // The body size GM runs, one of TextSize's stops.
    readonly property int sheetBody: 14
    readonly property int sheetWidth: 480
    readonly property int sheetMaxHeight: 900
    // Polls that must see an unchanged content height before the grab, so a late layout pass cannot be missed.
    readonly property int stableReads: 3
    readonly property int pollMs: 60
    readonly property int failAfterReads: 400
    // A frame never shrinks below this many pixels, and the document's inset counts on both sides of it.
    readonly property int minFrameHeight: 1
    readonly property int insetSides: 2
    readonly property color windowGround: "#101315"
    property string outDir: Quickshell.env("FLEA_SHEET_OUT")
    property string mdDir: Quickshell.env("FLEA_SHEET_MD")
    property var manifest: []
    property int at: -1
    property int seqBefore: 0
    property int stable: 0
    property real lastHeight: -1
    property int reads: 0
    property bool grabbing: false

    // The ListView's contentHeight is an estimate until every delegate exists, so the document ends where its last delegate does.
    function contentEnd() {
        var last = md.blockList.length > 0 ? md.blockItem(md.blockList.length - 1) : null
        return last === null ? 0 : last.y + last.height + md.insetY * shell.insetSides
    }

    function log(line) { console.log("MDSHEET " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    function load(path) {
        var request = new XMLHttpRequest()
        request.open("GET", "file://" + path, false)
        request.send()
        return JSON.parse(request.responseText)
    }

    function next() {
        shell.at++
        if (shell.at >= shell.manifest.length) {
            shell.log("DONE " + shell.manifest.length)
            shell.quit()
            return
        }
        shell.seqBefore = md.parseSeq
        shell.stable = 0
        shell.lastHeight = -1
        shell.reads = 0
        shell.grabbing = false
        md.path = shell.mdDir + "/" + shell.manifest[shell.at].n + ".md"
    }

    Component.onCompleted: {
        shell.manifest = shell.load(shell.mdDir + "/manifest.json")
        Flea.ViewState.state = { display: { textSize: { mode: shell.sheetBody } } }
        shell.next()
    }

    FloatingWindow {
        implicitWidth: shell.sheetWidth
        implicitHeight: shell.sheetMaxHeight
        color: shell.windowGround

        Rectangle {
            id: grabRoot
            width: shell.sheetWidth
            height: Math.max(shell.minFrameHeight, Math.min(shell.sheetMaxHeight, Math.ceil(shell.contentEnd())))
            color: Flea.Theme.color.background
            clip: true

            Flea.PreviewMarkdown {
                id: md
                width: parent.width
                height: shell.sheetMaxHeight
                active: true
                size: 1
                view: "rendered"
            }
        }
    }

    function grabbed(result) {
        var name = shell.manifest[shell.at].n
        if (!result.saveToFile(shell.outDir + "/" + name + ".png"))
            shell.log("FAIL save " + name)
        shell.next()
    }

    Timer {
        interval: shell.pollMs
        repeat: true
        running: true
        onTriggered: {
            if (shell.at < 0 || shell.at >= shell.manifest.length || shell.grabbing)
                return
            shell.reads++
            var ready = md.contentReady && md.appliedSeq > shell.seqBefore
            // A document that parses to nothing keeps its seq, so an unchanged empty file counts as ready.
            if (!ready && md.contentReady && md.blockList.length === 0 && shell.reads > shell.stableReads)
                ready = true
            var height = Math.ceil(shell.contentEnd())
            shell.stable = ready && height === shell.lastHeight ? shell.stable + 1 : 0
            shell.lastHeight = height
            if (shell.stable >= shell.stableReads) {
                shell.grabbing = true
                grabRoot.grabToImage(shell.grabbed)
            } else if (shell.reads > shell.failAfterReads) {
                shell.log("FAIL timeout " + shell.manifest[shell.at].n)
                shell.next()
            }
        }
    }
}
