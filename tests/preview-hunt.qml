import QtQuick
import Quickshell
import "flea" as Flea

// The actual Markdown delegates, with Qt's native Markdown parser as a control.
// The scroll phase opens real Quick Look documents through its public trigger.
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
    function parsed(text) {
        reader.text = text
        return reader.getText(0, reader.length).replace(/[\u2028\u2029]/g, "\n").trim()
    }
    function drawnText(item) {
        return descendants(item).filter(function(node) {
            return node.visible && node.textFormat !== undefined && typeof node.text === "string"
                && node.text.length > 0 && node.text !== "•"
        }).map(function(node) { return root.parsed(node.text) }).join("\n")
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
                    var nativeTasks = root.parsed(md.rawText)
                    root.check("native Qt consumes task markers", nativeTasks, "todo\ndone")
                    root.check("rendered task items consume checkbox syntax", root.drawnText(md.blockItem(0)), nativeTasks)
                } else if (scenario === "reference") {
                    var reference = root.parsed(md.rawText).split("\n")[0]
                    root.check("native Qt resolves reference across fence", reference, "Read guide.")
                    root.check("rendered reference link survives block split", root.drawnText(md.blockItem(0)), reference)
                } else if (scenario === "table") {
                    var cell = md.blockList[0].rows[0][0]
                    root.check("rendered table cell keeps emphasis markup", root.parsed(cell), root.parsed("**bold**"))
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
                root.check("new file B starts at its own position", Math.round(liveFlick.contentY), 0)
                liveFlick.contentY = 240
                root.check("file B scrolls independently", Math.round(liveFlick.contentY), 240)
                quick.open(root.fixture + "/a.md", "text-x-generic", 2000, "Markdown document", "")
                root.stage = 3
                root.stamp = Date.now()
                return
            }
            if (stage === 3 && quick.status === "ready" && Date.now() - root.stamp > 300) {
                root.check("revisiting A restores A scroll", Math.round(liveFlick.contentY), 120)
                root.finish()
            }
        }
    }
}
