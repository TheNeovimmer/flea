import QtQuick
import "../ui/js/Markdown.js" as Markdown

Window {
    id: root
    visible: true
    width: 800
    height: 660
    color: "#101315"
    property int checks: 0
    property int failures: 0
    property int readyImages: 0
    readonly property int decodeTimeoutMs: 5000
    readonly property int decodePollMs: 25
    property double decodeStarted: 0
    property var samples: []
    property string fixture: Qt.application.arguments[Qt.application.arguments.length - 1]
    FontMetrics { id: metrics; font.family: "monospace" }
    Text { id: heading; textFormat: Text.MarkdownText }
    TextEdit { id: decoded; textFormat: TextEdit.MarkdownText }
    Row {
        id: capture
        anchors.fill: parent
        spacing: 20
        Repeater {
            model: 2
            Column {
                required property int index
                width: 380
                spacing: 8
                Repeater {
                    model: root.samples.slice(index * 3, index * 3 + 3)
                    Column {
                        required property var modelData
                        Text { text: modelData.id + " body " + modelData.bodyPx; color: "#c0caf5" }
                        Image {
                            source: "data:image/svg+xml," + encodeURIComponent(modelData.svg)
                            width: sourceSize.width
                            height: sourceSize.height
                            onStatusChanged: if (status === Image.Ready) root.readyImages++
                        }
                    }
                }
            }
        }
    }
    function check(ok, label) {
        checks++
        if (!ok) { failures++; console.log("FAIL " + label) }
    }
    Component.onCompleted: {
        for (var fence of ["```python", "~~~python"]) {
            var block = Markdown.blocks("# " + fence, "", "#181825", "#c0caf5")[0]
            heading.text = block.text
            decoded.text = block.text
            check(heading.implicitWidth > 0, "F3 heading has native ink: " + fence)
            check(decoded.getText(0, decoded.length) === fence, "F3 heading decodes literally: " + fence)
        }
        var request = new XMLHttpRequest()
        request.open("GET", root.fixture, false)
        request.send()
        var cases = JSON.parse(request.responseText)
        samples = cases
        for (var sample of cases) {
            metrics.font.pixelSize = sample.fontPx
            var ink = metrics.boundingRect(sample.label).width
            sample.labelInkWidth = ink
            if (sample.id === "F2") {
                check(ink <= sample.nodeWidth, "F2 body " + sample.bodyPx + ": native ink fits node")
                check(ink <= sample.canvasWidth, "F2 body " + sample.bodyPx + ": native ink fits canvas")
            }
            var geometry = Object.assign({}, sample)
            delete geometry.svg
            console.log("MD3U_GEOMETRY " + JSON.stringify(geometry))
        }
        decodeStarted = Date.now()
        settle.start()
    }
    Timer {
        id: settle
        interval: root.decodePollMs
        repeat: true
        onTriggered: {
            if (root.readyImages !== root.samples.length && Date.now() - root.decodeStarted < root.decodeTimeoutMs)
                return
            stop()
            check(root.readyImages === root.samples.length, "all SVG images decoded")
            capture.grabToImage(function(result) {
                check(result.saveToFile(root.fixture.replace(/^file:\/\//, "").replace(/\.json$/, ".png")), "native geometry capture saved")
                root.finish()
            })
        }
    }
    function finish() {
        console.log("MARKDOWN_MD3U_NATIVE " + checks + " checks, " + failures + " failed")
        Qt.exit(failures ? 1 : 0)
    }
}
