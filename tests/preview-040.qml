import QtQuick
import Quickshell
import "flea" as Flea

// TallPreviews callout 7: each file keeps its preview scroll position for the session, scheduled for 0.3.10.
ShellRoot {
    id: root
    property string fixture: Quickshell.env("FLEA_PREVIEW_040_DIR")
    property int stage: 0
    property double stamp: Date.now()
    property int failures: 0
    property int checks: 0
    property var liveMarkdown: null
    property var liveFlick: null

    function check(label, actual, expected) {
        checks++
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) failures++
        console.log("PREVIEW_040 " + (ok ? "PASS " : "FAIL ") + label
            + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    function finish() {
        poll.stop()
        console.log("PREVIEW_040 DONE " + checks + " checks, " + failures + " failed")
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
    function flickOf(item) {
        var handlers = descendants(item).filter(function(node) { return node.objectName === "fleaScroll" })
        return handlers.length ? handlers[0].flickable : null
    }

    FloatingWindow {
        implicitWidth: 760
        implicitHeight: 500
        color: Flea.Theme.color.background
        Flea.Preview { id: quick }
    }

    Timer {
        id: poll
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            if (Date.now() - root.stamp > 8000) {
                root.check("probe completes", "timeout stage " + stage, "complete")
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
