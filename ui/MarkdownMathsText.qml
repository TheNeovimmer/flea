import QtQuick
import "js/MarkdownMaths.js" as Maths

// A Markdown text whose inline formulas draw in the line: each asks the figure helper once, and its code span stands until the picture lands.
MarkdownText {
    id: root

    // The run's HTML text, and the TeX of its inline formulas in the order of the data-math spans inside it.
    property string source: ""
    property var maths: []
    // The theme and gates a figure takes, handed down by the block's host as the display figures get them.
    property bool askArmed: true
    property bool inView: true
    property string bgHex: "#101315"
    property string fgHex: "#c0caf5"
    property string accentHex: "#7aa2f7"
    property string mutedHex: ""
    property string surfaceHex: ""
    // The fence pads a failed formula's source takes, the preview's own.
    property int fencePadX: 0
    property int fencePadY: 0

    // A formula the parser and the text disagree on is left as its code span, and asks for nothing.
    readonly property bool matched: Maths.spans(root.source).length === root.maths.length
    // Each distinct formula asks once, however often the run repeats it.
    readonly property var formulas: {
        var seen = []
        for (var i = 0; root.matched && i < root.maths.length; i++) {
            if (seen.indexOf(root.maths[i]) < 0)
                seen.push(root.maths[i])
        }
        return seen
    }
    // The SVG of each drawn formula by its TeX, "" while it waits or after it failed.
    property var svgs: ({})
    property var settledSources: ({})
    // Formulas still waiting for their answer; the suite reads it to know the run is done.
    readonly property int unsettled: root.formulas.length - Object.keys(root.settledSources).length

    // Qt centres a middle-aligned picture above the baseline by a font-dependent amount; a hidden tall picture reports it as its baseline.
    readonly property real anchorHeight: calibration.baselineOffset - Maths.CALIBRATION_HEIGHT / 2
    readonly property real tallestPicture: 2 * root.box

    function landed(tex, svg, settled) {
        var next = Object.assign({}, root.svgs)
        next[tex] = svg
        root.svgs = next
        var done = Object.assign({}, root.settledSources)
        if (settled)
            done[tex] = true
        else
            delete done[tex]
        root.settledSources = done
    }

    text: root.matched ? Maths.compose(root.source, root.maths.map(function (tex) {
        return Maths.picture(root.svgs[tex] || "", root.anchorHeight, root.tallestPicture)
    })) : root.source

    Text {
        id: calibration
        visible: false
        font: root.font
        textFormat: Text.MarkdownText
        wrapMode: Text.NoWrap
        text: "H <img src=\"" + Maths.CLEAR + "\" width=\"1\" height=\"" + Maths.CALIBRATION_HEIGHT + "\" style=\"vertical-align: middle\" />"
    }

    Repeater {
        model: root.formulas
        delegate: MarkdownFigure {
            required property string modelData
            visible: false
            kind: "math"
            source: modelData
            display: false
            inline: true
            bare: true
            askArmed: root.askArmed
            inView: root.inView
            bgHex: root.bgHex
            fgHex: root.fgHex
            accentHex: root.accentHex
            mutedHex: root.mutedHex
            surfaceHex: root.surfaceHex
            fencePadX: root.fencePadX
            fencePadY: root.fencePadY
            fontFamily: root.font.family
            bodyPx: root.font.pixelSize
            onSvgChanged: root.landed(modelData, svg, svg !== "" || error !== "")
            onErrorChanged: root.landed(modelData, svg, svg !== "" || error !== "")
        }
    }

    // Its formulas are padded to sit on the fixed line's baseline, so a picture beside them keeps that line.
    growsForPictures: false
}
