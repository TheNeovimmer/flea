.import "../markdown-render.js" as Render
.import "../markdown-figures-render.js" as Figures
.import "sourcefixture.js" as Source

// Adversarial fixtures execute the render harness methods with broken live-tree states.
function run(check) {
    var preview = Source.source("ui/PreviewMarkdown.qml")
    check("md3z F2 one preview header", !/\/\/[^\n]*\n\/\/[^\n]*\nItem \{/.test(preview), true)
    check("md3z F2 image sentence beside resolution", /\/\/ Resolve images[^\n]*\n    function askParse/.test(preview), true)
    check("md3z F3 markerPaths sample", /\/\/ Sample input:[^\n]*points=[^\n]*\nfunction markerPaths/.test(Source.source("ui/js/FigureWorker.mjs")), true)
    var commentFiles = ["ui/MarkdownFigure.qml", "ui/MarkdownText.qml", "ui/MarkdownPane.qml",
        "ui/PreviewMarkdown.qml", "ui/js/MdBlocks.js"]
    for (var f = 0; f < commentFiles.length; f++) {
        var sourceLines = Source.source(commentFiles[f]).split("\n")
        for (var c = 0; c < sourceLines.length; c++) {
            if (!/^\s*\/\//.test(sourceLines[c]))
                continue
            check("md3u F4 comment length " + commentFiles[f] + ":" + (c + 1),
                sourceLines[c].trim().length <= 140, true)
            if (c > 0 && /^\s*\/\//.test(sourceLines[c - 1]))
                check("md3u F4 single constraint " + commentFiles[f] + ":" + (c + 1),
                    /Sample(?: input)?:/.test(sourceLines[c - 1] + sourceLines[c]), true)
        }
    }
    var blocksSource = Source.source("ui/js/MdBlocks.js")
    check("md3u F5 figureKind sample", /\/\/ Sample input:[^\n]*mermaid[^\n]*\nfunction figureKind/.test(blocksSource), true)
    check("md3u F8 display sample", /\/\/ Sample input:[^\n]*\$\$x[^\n]*\\n[^\n]*\n        var disp/.test(blocksSource), true)
    var figureRunner = Source.source("tests/markdown-figures-render.sh")
    check("md3t F5 one shell header", !/^#![^\n]*\n#[^\n]*\n#/.test(figureRunner), true)
    var figureModule = Source.source("tests/markdown-figures-render.js")
    check("md3t F6 labelError sample", /\/\/ Sample input:[^\n]*<text[^\n]*\nfunction labelError/.test(figureModule), true)
    check("md3t F6 paletteError sample", /\/\/ Sample input:[^\n]*fill=[^\n]*\nfunction paletteError/.test(figureModule), true)
    check("md3v F2 one module header", !/^\/\/[^\n]*\n\/\//.test(Source.source("tests/markdown-render.js")), true)
    var source = Source.source("tests/markdown-source-render.qml")
    var geometry = new Function("sourcePane", "reference", "Flea", "Text", "check", "sourceParts",
        Source.slice(source, "function geometry()", "    Timer {") + "\ngeometry()")
    function sourceCase(widths, wheel) {
        var flick = { children: [], height: 240, contentHeight: 300 }
        for (var w = 0; w < widths.length; w++)
            flick.children.push({ knobItem: {}, flickable: flick, width: widths[w], mapToItem: function () { return { x: 560 } } })
        if (wheel)
            flick.children.push({ flickable: flick, width: 560, mapToItem: function () { return { x: 560 } } })
        var text = { width: 520, implicitHeight: 268, text: "raw", textFormat: 0,
            mapToItem: function () { return { x: 20, y: 16 } } }
        var failures = []
        geometry({ width: 560, insetX: 20, insetY: 16, rawText: "raw" },
            { item: { blockItem: function () { return text } } },
            { Theme: { font: { body: 14 } } }, { PlainText: 0 },
            function (ok, label) { if (!ok) failures.push(label) },
            function () { return { flick: flick, text: text } })
        return failures
    }
    check("md3z F4 missing Source scrollbar rejected", sourceCase([]).length > 0, true)
    check("md3z F4 zero-width Source scrollbar rejected", sourceCase([0]).length > 0, true)
    check("md3z F4 duplicate Source scrollbars rejected", sourceCase([14, 14]).length > 0, true)
    check("md3z F4 one Source scrollbar accepted", sourceCase([14]).length, 0)
    check("md3z F4 wheel handler cannot replace missing bar", sourceCase([], true).length > 0, true)
    check("md3z F4 wheel handler not counted as scrollbar", sourceCase([14], true).length, 0)
    var renderRunner = Source.source("tests/markdown-render.sh")
    check("md3z F4 runner requires all 15 Source checks", renderRunner.indexOf("expected_source_checks=15") >= 0
        && renderRunner.indexOf("MARKDOWN_SOURCE $expected_source_checks checks, 0 failed") >= 0, true)

    var figureSource = Source.source("tests/markdown-figures-render.qml")
    check("md3t F5 one QML header", !/\/\/[^\n]*\n\/\/[^\n]*\nShellRoot/.test(figureSource), true)
    var drive = new Function("shell", "md", "Flea", "Checks", "poll", "grabRoot",
        Source.slice(figureSource, "function drive()", "function grabbed(") + "\ndrive()")
    function figureCase(mode, imgW, history, step) {
        var failure = ""
        var shell = { step: step, figMode: mode, farIndex: 9, requestHistory: history, t0: Date.now(),
            figuresSettled: function () { return true }, checkFar: function () { return true },
            log: function () {}, check: function () {}, fail: function (why) { failure = why } }
        var farSource = "flowchart TD\n    FAR --> AWAY"
        var md = { width: 560, blockList: [],
            figureInfo: function (i) { return i === 9 ? null : { boxW: 520, imgW: imgW, imgH: 20 } },
            blockItem: function () { return { visible: false } }, hexOf: function () { return "#101315" } }
        md.blockList[9] = { source: farSource }
        var checks = { surfaceError: Figures.surfaceError, farRequestError: Figures.farRequestError,
            figure: function () { return { svg: "" } },
            bodyFont: function () { return {} }, labelError: function () { return "" }, paletteError: function () { return "" } }
        shell.checkHistory = function () {
            var error = Figures.farRequestError(shell.requestHistory, farSource, history.length)
            if (error !== "") {
                shell.fail(error)
                return false
            }
            return true
        }
        drive(shell, md, { FigureService: { sends: history.length }, Theme: { color: {} } }, checks,
            { stop: function () {} }, { grabToImage: function () {} })
        return failure
    }
    var sentFar = [{ id: 1, source: "flowchart TD\n    FAR --> AWAY" }]
    for (var m = 0; m < 2; m++) {
        var mode = m === 0 ? "real" : "stub"
        check("md3t F2 evicted far request rejected in " + mode, figureCase(mode, 200, sentFar, 1) !== "", true)
        check("md3t F2 far request on return rejected in " + mode, figureCase(mode, 200, sentFar, 3) !== "", true)
        check("md3t F3 image wider than box rejected in " + mode, figureCase(mode, 700, [], 1) !== "", true)
        check("md3t F3 fitted image accepted in " + mode, figureCase(mode, 200, [], 1), "")
    }
    // Sample input: if (c[2] >= 200 && c[0] <= 110 && c[1] <= 170) precedes the default-blue failure.
    var blue = new Function("c", "accent", "ground", "Checks", "return "
        + figureSource.match(/if \(([^\n]*)\)\n\s+return shell\.fail\("a Qt default link blue/)[1])
    check("md3t F4 theme accent composite accepted", blue([101, 133, 202], [122, 162, 247], [16, 19, 21], Figures), false)
    check("md3t F4 Qt default blue rejected", blue([0, 0, 255], [122, 162, 247], [16, 19, 21], Figures), true)

    var captureWidth = 560
    var captureHeight = 1080
    var outside = { x: 20, y: 1080, w: 520, h: 17 }
    var error = ""
    try {
        Figures.inkBounds(new Uint8Array(captureWidth * captureHeight * 4), captureWidth, outside, [16, 19, 21], [30, 30, 30])
    } catch (e) {
        error = String(e)
    }
    check("md3t F7 out-of-buffer rect rejected", error.indexOf("1080") >= 0 && error.indexOf("560x1080") >= 0, true)
    var bodyPx = 14
    for (var r = 1; r <= 2; r++) {
        var box = Math.round(r * bodyPx)
        check("md3v F1 " + r + ".0 line box rejected", Render.lineBoxError([
            { name: "run", h: box, text: { box: box, lineHeight: box, font: { pixelSize: bodyPx } } }
        ]) !== "", true)
    }
    var goodBox = Math.round(Render.BOARD_LINE_BOX_RATIO * bodyPx)
    check("md3v F1 font-derived box accepted", Render.lineBoxError([
        { name: "run", h: goodBox, text: { box: goodBox, lineHeight: goodBox, font: { pixelSize: bodyPx } } }
    ]), "")
    var renderer = Source.source("tests/markdown-render.qml")
    check("md3z F6 board ratio is 1.7", Render.BOARD_LINE_BOX_RATIO, 1.7)
    check("md3z F6 ratio never read from the renderer", renderer.indexOf("Checks.lineBoxError(texts)") >= 0 && renderer.indexOf("boxRatio") < 0, true)
    check("md3v F3 rhythm read from Theme token", renderer.indexOf("Checks.rhythmError(rects, Flea.Theme.spacing.rowPaddingY)") >= 0, true)
    // Sample input: shell.check(Checks.rhythmError(rects, md.blockGap), "block rhythm").
    var rhythmCall = renderer.match(/shell\.check\(Checks\.rhythmError\([^\n]+/)[0]
    var rhythm = new Function("rects", "md", "Flea", "Checks", "shell", rhythmCall)
    var rhythmError = ""
    rhythm([{ y: 0, h: 24 }, { y: 34, h: 24 }], { blockGap: 10 },
        { Theme: { spacing: { rowPaddingY: 7 } } }, Render,
        { check: function (error) { rhythmError = error } })
    check("md3v F3 differing renderer gap rejected", rhythmError !== "", true)
}
