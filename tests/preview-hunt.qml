import QtQuick
import Quickshell
import "flea" as Flea

// Probe real Markdown delegates and task boxes; open Quick Look documents through its public trigger.
ShellRoot {
    id: root
    property string scenario: Quickshell.env("FLEA_PREVIEW_HUNT_CASE")
    property string fixture: Quickshell.env("FLEA_PREVIEW_HUNT_DIR")
    property int stage: 0
    property double stamp: Date.now()
    property int failures: 0
    property int checks: 0
    property var liveMarkdown: null
    property var liveFlick: null
    property var nativePane: null
    property var nativeKeys: null
    readonly property bool overlayCase: scenario === "scroll" || scenario === "source-key"

    function check(label, actual, expected) {
        checks++
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) failures++
        console.log("PREVIEW_HUNT " + (ok ? "PASS " : "FAIL ") + label
            + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    function finish() {
        console.log("PREVIEW_HUNT DONE " + checks + " checks, " + failures + " failed")
        Qt.exit(failures ? 1 : 0)
    }
    function descendants(item) {
        var out = [item]
        for (var i = 0; i < out.length; i++) {
            var kids = out[i].children || []
            for (var j = 0; j < kids.length; j++) out.push(kids[j])
        }
        return out
    }
    function parsed(text, format) {
        reader.textFormat = format === undefined ? TextEdit.MarkdownText
            : format === Text.StyledText ? TextEdit.RichText : format
        reader.text = text
        return reader.getText(0, reader.length).replace(/[\u2028\u2029]/g, "\n").trim()
    }
    function drawnText(item) {
        return descendants(item).filter(function(node) {
            return node.visible && node.textFormat !== undefined && typeof node.text === "string"
                && node.text.length > 0 && node.text !== "•"
        }).map(function(node) {
            return node.textFormat === Text.PlainText ? node.text : root.parsed(node.text, node.textFormat)
        }).join("\n")
    }
    function drawnBold(node) {
        if (!node) return false
        // Reset the reader's insertion font so a previous bold selection cannot style plain text.
        reader.text = ""
        reader.deselect()
        reader.font = node.font
        reader.cursorSelection.font = node.font
        if (root.parsed(node.text, node.textFormat) !== "bold") return false
        for (var i = 0; i < reader.length; i++) {
            reader.select(i, i + 1)
            if (reader.cursorSelection.font.weight < Font.Bold) return false
        }
        return true
    }
    function flickOf(item) {
        var handlers = descendants(item).filter(function(node) { return node.objectName === "fleaScroll" })
        return handlers.length ? handlers[0].flickable : null
    }

    FloatingWindow {
        implicitWidth: 760
        implicitHeight: 500
        color: Flea.Theme.color.background
        Flea.PreviewMarkdown {
            id: md
            width: 600
            height: 400
            active: !root.overlayCase
            path: root.fixture + "/" + root.scenario + ".md"
            size: 1000
        }
        Flea.Preview { id: quick }
        TextEdit {
            id: reader
            visible: false
            textFormat: TextEdit.MarkdownText
        }
    }
    Flea.Backend { id: realBackend }
    Component {
        id: paneComponent
        Flea.Pane {
            width: 760
            height: 500
            backend: realBackend
            preview: quick
        }
    }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            if (Date.now() - root.stamp > 8000) {
                root.check("probe completes", "timeout stage " + stage, "complete")
                root.finish()
                return
            }
            if (scenario === "source-key") {
                if (stage === 0) {
                    nativePane = paneComponent.createObject(quick.parent)
                    quick.pane = nativePane
                    nativePane.open(root.fixture)
                    nativeKeys = Qt.createQmlObject("import QtTest; TestEvent {}", nativePane.listArea)
                    root.stage = 1
                    root.stamp = Date.now()
                    return
                }
                if (stage === 1 && !nativePane.listInFlight && nativePane.total > 0) {
                    quick.open(root.fixture + "/a.md", "text-x-generic", 2000, "Markdown document", "")
                    nativePane.listArea.forceActiveFocus()
                    root.stage = 2
                    root.stamp = Date.now()
                    return
                }
                if (stage === 2 && quick.status === "ready" && Date.now() - root.stamp > 300) {
                    root.check("Quick Look starts rendered", Flea.ViewState.markdownView, "rendered")
                    nativeKeys.keyClickChar("r", Qt.NoModifier, -1)
                    root.check("real r key switches Quick Look to Source", Flea.ViewState.markdownView, "source")
                    liveMarkdown = root.descendants(quick).filter(function(node) {
                        return node.blockList !== undefined && node.active === true
                    })[0]
                    root.check("Source is drawn by the live pane", liveMarkdown.view, "source")
                    root.stage = 3
                    root.stamp = Date.now()
                    return
                }
                if (stage === 3 && Date.now() - root.stamp > 600) root.finish()
                return
            }
            if (!root.overlayCase) {
                if (!md.contentReady || Date.now() - root.stamp < 400) return
                if (scenario === "tasks") {
                    var tasks = root.drawnText(md.blockItem(0))
                    root.check("rendered task items consume checkbox syntax", /\[[ xX]\]/.test(tasks), false)
                    var taskLines = tasks.split("\n")
                    var openTask = /^([^\s]+)\s+todo$/.exec(taskLines[0] || "")
                    var doneTask = /^([^\s]+)\s+done$/.exec(taskLines[1] || "")
                    root.check("each task text follows its box", taskLines.length === 2
                        && openTask !== null && doneTask !== null
                        && /^[\u2610\u2611]$/.test(openTask[1]) && /^[\u2610\u2611]$/.test(doneTask[1]), true)
                    root.check("open and done tasks draw distinct box marks", openTask !== null && doneTask !== null
                        && openTask[1] !== doneTask[1], true)
                } else if (scenario === "reference") {
                    var reference = root.parsed(md.rawText).split("\n")[0]
                    root.check("native Qt resolves reference across fence", reference, "Read guide.")
                    root.check("rendered reference link survives block split", root.drawnText(md.blockItem(0)), reference)
                } else if (scenario === "table") {
                    var bodyRows = root.descendants(md.blockItem(0)).filter(function(node) { return node.row === 0 })
                    var cells = bodyRows.length ? root.descendants(bodyRows[0]).filter(function(node) {
                        return node.visible && node.cellPad !== undefined && node.textFormat !== undefined
                    }) : []
                    var cell = cells.length ? cells[0] : null
                    root.check("rendered table cell draws text without literal markup", cell ? root.drawnText(cell) : null, "bold")
                    root.check("rendered table cell draws the bold run", root.drawnBold(cell), true)
                } else if (scenario === "control") {
                    root.check("plain Markdown paragraph renders", root.drawnText(md.blockItem(0)), "Hello preview.")
                }
                root.finish()
                return
            }
            if (stage === 0) {
                quick.open(root.fixture + "/a.md", "text-x-generic", 2000, "Markdown document", "")
                root.stage = 1
                root.stamp = Date.now()
                return
            }
            if (stage === 1 && quick.status === "ready" && Date.now() - root.stamp > 300) {
                liveMarkdown = root.descendants(quick).filter(function(node) {
                    return node.blockList !== undefined && node.active === true
                })[0]
                liveFlick = root.flickOf(liveMarkdown)
                root.check("Quick Look has a scrolling Markdown frame", liveFlick.contentHeight > liveFlick.height + 300, true)
                liveFlick.contentY = 120
                root.check("file A scrolls", Math.round(liveFlick.contentY), 120)
                quick.open(root.fixture + "/b.md", "text-x-generic", 2000, "Markdown document", "")
                root.stage = 2
                root.stamp = Date.now()
                return
            }
            if (stage === 2 && quick.status === "ready" && Date.now() - root.stamp > 300) {
                root.check("new file B starts at its own position", Math.round(liveFlick.contentY), -liveFlick.topMargin)
                var firstBlock = liveMarkdown.blockItem(0)
                var firstTop = firstBlock ? firstBlock.mapToItem(liveFlick, 0, 0).y : -1
                root.check("first block starts inside the visible frame at rest", firstBlock !== null
                    && firstTop >= 0 && firstTop < liveFlick.height, true)
                liveFlick.contentY = 240
                root.check("file B scrolls independently", Math.round(liveFlick.contentY), 240)
                root.finish()
            }
        }
    }
}
