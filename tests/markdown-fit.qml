import QtQuick
import Quickshell
import "flea" as Flea

// How the rendered document fits its host: a narrow picture sits on the text's left edge, and the preview column sets the document one step under Quick Look.
ShellRoot {
    id: root
    property string scenario: Quickshell.env("FLEA_PREVIEW_HUNT_CASE")
    property string fixture: Quickshell.env("FLEA_PREVIEW_HUNT_DIR") + "/" + scenario + ".md"
    property double stamp: Date.now()
    property int failures: 0
    property int checks: 0
    // The probe's own give-up and the layout warm-up before a check.
    readonly property int probeGiveUpMs: 8000
    readonly property int warmupMs: 350
    // The picture beside the document that tests/preview-hunt.sh writes.
    readonly property int benchWidth: 160
    readonly property int benchHeight: 80
    // RenderedPreviews' headings are 20 and 15 over its 14 body.
    readonly property real h1Ratio: 20 / 14
    readonly property real h2Ratio: 15 / 14

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
    function liveText(item) {
        return descendants(item).filter(function (node) {
            return node.visible && node.textFormat !== undefined && typeof node.text === "string"
                && node.text.length > 0
        })
    }

    FloatingWindow {
        implicitWidth: 760
        implicitHeight: 700
        color: Flea.Theme.color.background
        Flea.PreviewMarkdown {
            id: md
            width: 600
            height: 580
            active: true
            path: root.fixture
            size: 2000
        }
        Flea.PreviewColumn {
            id: column
            width: 300
            height: 600
            visible: root.scenario === "column-scale"
            row: ({ n: "column-scale.md", d: false, t: false, s: 100, i: "text-x-generic" })
            meta: ({})
            path: root.fixture
            kindName: "Markdown document"
        }
    }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            if (Date.now() - root.stamp > root.probeGiveUpMs) {
                root.check("probe completes", "timeout", "complete")
                root.finish()
                return
            }
            if (!md.contentReady || Date.now() - root.stamp < root.warmupMs) return
            if (root.scenario === "local-image-narrow") {
                var para = liveText(md.blockItem(0))[0]
                var block = md.blockItem(1)
                var images = descendants(block).filter(function (node) {
                    return node.visible && node.source !== undefined && node.asynchronous !== undefined
                        && String(node.source) !== ""
                })
                if (!images.length || images[0].status !== Image.Ready) return
                var image = images[0]
                root.check("narrow image decoded at its own size", [image.sourceSize.width, image.sourceSize.height], [root.benchWidth, root.benchHeight])
                root.check("narrow image is narrower than the content", image.paintedWidth < block.width, true)
                // Image paints its picture inside its box: the painted left is the box's left plus the alignment's share of the slack.
                var slack = image.width - image.paintedWidth
                var share = image.horizontalAlignment === Image.AlignLeft ? 0
                    : image.horizontalAlignment === Image.AlignRight ? 1 : 0.5
                var paintedLeft = image.mapToItem(md.bodyItem.contentItem, 0, 0).x + slack * share
                var textLeft = para.mapToItem(md.bodyItem.contentItem, 0, 0).x
                root.check("a narrow image is drawn flush with the text's left edge", Math.round(paintedLeft), Math.round(textLeft))
                root.finish()
                return
            }
            var doc = column.markdown
            if (!doc || !doc.contentReady) return
            var want = Flea.Theme.font.bodySmall
            root.check("the column's text token is smaller than Quick Look's", want < Flea.Theme.font.body, true)
            var sizes = []
            for (var b = 0; b < doc.blockList.length; b++) {
                var live = doc.blockItem(b)
                var node = live ? liveText(live)[0] : null
                if (node) sizes.push([doc.blockList[b].type + (doc.blockList[b].level || ""), node.font.pixelSize])
            }
            // The headings keep the board's 20 and 15 over Quick Look's body, whatever the column sets its text at.
            var expected = [["heading1", Math.round(Flea.Theme.font.body * root.h1Ratio)], ["heading2", Math.round(Flea.Theme.font.body * root.h2Ratio)],
                ["run", want], ["list", want], ["table", want], ["fence", want]]
            root.check("the column document sets its text at its own scale and its headings at the board's", sizes, expected)
            root.check("Quick Look's document keeps the body token under its heading", liveText(md.blockItem(0))[0].font.pixelSize,
                Math.round(Flea.Theme.font.body * root.h1Ratio))
            root.finish()
        }
    }
}
