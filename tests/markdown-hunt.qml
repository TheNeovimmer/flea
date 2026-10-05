import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "flea/js/MdLeaf.js" as Leaf

// Exercise live preview objects, native link clicks and a real file rewrite without changing product code.
ShellRoot {
    id: root
    property string scenario: Quickshell.env("FLEA_PREVIEW_HUNT_CASE")
    property string fixture: Quickshell.env("FLEA_PREVIEW_HUNT_DIR") + "/" + scenario + ".md"
    property int stage: 0
    property double stamp: Date.now()
    property int failures: 0
    property int checks: 0
    property var keys: null
    property var clicked: []
    property string initialInk: ""
    property string otherFixture: Quickshell.env("FLEA_PREVIEW_HUNT_DIR") + "/disk-stale-b.md"
    property real scrolledY: 0
    property int settleTicks: 0
    property var lastPlaces: null
    property int placesQuiet: 0
    property bool rewritten: false
    // About 2 x 50 text items fit the viewport and its cache, plus the chunks at both ends; a delegate per item would be 3000.
    readonly property int liveTextBound: 400
    // The lazy suite caps live block delegates at 150; one chunk needs the same bound.
    readonly property int chunkDelegateBound: 150
    // The probe's own bounds: its give-up, and the layout warm-up before a check.
    readonly property int probeGiveUpMs: 8000
    readonly property int warmupMs: 350
    // A place deep inside the 300 paragraph disk-scroll file, past the first screen.
    readonly property int scrollTargetY: 1200
    // Viewports of content that mean a file really scrolls, and that a long container exceeds.
    readonly property int scrollableScreens: 3
    readonly property int containerScreens: 10
    // The fixtures' own sizes, written by tests/preview-hunt.sh.
    readonly property int listItemsTotal: 1500
    readonly property int tableRowsTotal: 1200
    // Ticks of the probe timer a theme switch stays quiet for before its place is read; counted, never timed.
    readonly property int themeSettleTicks: 15
    // Ticks a long container's row places hold before they are read; counted, never timed.
    readonly property int settleQuietTicks: 15

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
    function textOf(block) {
        return descendants(block).filter(function (node) {
            return node.visible && node.textFormat !== undefined && typeof node.text === "string"
                && node.text.length > 0
        })[0]
    }
    function nativeLinkInk(node) {
        reader.textFormat = TextEdit.MarkdownText
        reader.text = node.text
        reader.select(0, 1)
        return String(reader.cursorSelection.color)
    }
    readonly property string editedText: "After disk edit.\n"
    function diskChecks() {
        root.check("watched control sees disk edit", watchedControl.text(), root.editedText)
        root.check("Quick Look follows document changed on disk", quick.textShown(), root.editedText)
        root.check("column follows document changed on disk", column.markdown.rawText, root.editedText)
    }
    function chunkEdge() { return scenario === "long-list" ? Leaf.LIST_CHUNK_ITEMS : Leaf.TABLE_CHUNK_ROWS }
    function rowText(n) { return textY((scenario === "long-list" ? "Item " : "Row ") + n, scenario === "long-list") }
    // The rows the container checks read, the first two and both sides of the first chunk boundary, as their places; null until all are alive.
    function rowPlaces() {
        var edge = root.chunkEdge()
        var places = [0, 1, edge - 1, edge].map(function (n) { return root.rowText(n) })
        return places.every(function (y) { return y !== null }) ? JSON.stringify(places) : null
    }
    // True once those places have held for settleQuietTicks ticks: the chunks are placed over several layout turns, and a read between them sees a chunk at its estimate.
    function rowsSettled() {
        var places = root.rowPlaces()
        if (places === null || places !== root.lastPlaces) {
            root.lastPlaces = places
            root.placesQuiet = 0
            return false
        }
        return ++root.placesQuiet >= root.settleQuietTicks
    }
    function containerChecks() {
        var isList = scenario === "long-list"
        var total = 0
        for (var b = 0; b < md.blockList.length; b++)
            total += isList ? md.blockList[b].items.length : md.blockList[b].rows.length
        var first = md.blockItem(0)
        var firstNodes = liveText(first)
        // The parser splits a long container into chunk blocks, so completeness is the sum over the chunks.
        root.check("long container parsed completely", total, isList ? root.listItemsTotal : root.tableRowsTotal)
        root.check("long container exceeds visible frame", md.flickContentHeight > md.height * root.containerScreens, true)
        root.check("viewport bounds live " + scenario + " text delegates", firstNodes.length <= root.chunkDelegateBound, true)
        var live = liveText(md.bodyItem.contentItem)
        // Beside the first chunk, every chunk the list keeps alive for the viewport and its cache counts.
        root.check("viewport bounds all live " + scenario + " text delegates", live.length <= liveTextBound, true)
        // Rows across a chunk boundary keep the pitch of rows inside a chunk, so the chunks read as one container.
        // The first row of the second chunk, from the parser's own chunk size.
        var edge = root.chunkEdge()
        var rowsAt = [0, 1, edge - 1, edge]
        for (var r = 0; r < rowsAt.length; r++)
            root.check(scenario + " row " + rowsAt[r] + " is alive", root.rowText(rowsAt[r]) !== null, true)
        var pitch = root.rowText(1) - root.rowText(0)
        root.check(scenario + " rows inside a chunk are a positive pitch apart", pitch > 0, true)
        root.check("chunk boundary keeps the row pitch", root.rowText(edge) - root.rowText(edge - 1), pitch)
        console.log("PREVIEW_HUNT CONTAINER " + scenario + " blocks=" + md.blockList.length
            + " textDelegates=" + live.length + " height=" + md.flickContentHeight + " viewport=" + md.height)
    }
    function liveText(item) {
        return descendants(item).filter(function (node) {
            return node.visible && node.textFormat !== undefined && typeof node.text === "string"
                && node.text.length > 0
        })
    }
    // The y of the text a row starts with, in the list's content coordinates; null while its chunk is not alive.
    function textY(prefix, spaced) {
        var found = liveText(md.bodyItem.contentItem).filter(function (node) {
            return spaced ? node.text.indexOf(prefix + " ") === 0 : node.text === prefix
        })
        return found.length ? Math.round(found[0].mapToItem(md.bodyItem.contentItem, 0, 0).y) : null
    }
    function launchLines() {
        return openLog.text().trim().split("\n").filter(function (line) { return line.length > 0 })
    }

    Component.onCompleted: {
        if (scenario === "theme")
            Flea.Theme.applyColors('background = "#101315"\nforeground = "#eeeeee"')
    }
    FloatingWindow {
        id: window
        implicitWidth: 760
        implicitHeight: 700
        color: Flea.Theme.color.background
        Flea.PreviewMarkdown {
            id: md
            width: 600
            height: 580
            active: root.scenario !== "disk"
            path: root.fixture
            size: 2000
        }
        Flea.Preview {
            id: quick
            active: root.scenario === "disk"
            kind: "text"
            path: root.fixture
            size: 100
        }
        Flea.PreviewColumn {
            id: column
            width: 300
            height: 600
            visible: root.scenario === "disk"
            row: ({ n: "disk.md", d: false, t: false, s: 100, i: "text-x-generic" })
            meta: ({})
            path: root.fixture
            kindName: "Markdown document"
        }
        TextEdit { id: reader; visible: false }
    }
    // Read only on an explicit reload: a watcher-started read racing a click would count one launch late.
    FileView {
        id: openLog
        path: Quickshell.env("FLEA_MARKDOWN_OPEN_LOG")
        printErrors: false
    }
    FileView {
        id: watchedControl
        path: root.scenario === "disk" ? root.fixture : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    // An editor's atomic save: write a sibling, then rename it over the shown file.
    readonly property string renameScript: "import os, sys; from pathlib import Path; t = sys.argv[1] + '.tmp'; Path(t).write_text('After disk edit.\\n'); os.replace(t, sys.argv[1])"
    readonly property string plainScript: "from pathlib import Path; import sys; Path(sys.argv[1]).write_text('After disk edit.\\n')"
    readonly property string scrollScript: "from pathlib import Path; import sys; p = Path(sys.argv[1]); p.write_text(p.read_text().replace('scroll paragraph 0.', 'edited paragraph 0.'))"
    // The stale-file phase rewrites the file it just left.
    FileView {
        id: oldWatch
        path: root.scenario === "disk-stale" ? root.fixture : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    Process {
        id: rewrite
        command: ["python3", "-c", root.scenario === "disk-rename" ? root.renameScript
            : root.scenario === "disk-scroll" ? root.scrollScript : root.plainScript, root.fixture]
        onExited: function (exitCode, exitStatus) {
            root.check("fixture rewrite completed", exitCode, 0)
            root.rewritten = true
            root.stamp = Date.now()
        }
    }
    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            if (Date.now() - root.stamp > root.probeGiveUpMs) {
                // A phase that waits for its condition names what it saw when the wait ran out.
                if (scenario === "disk" && stage === 1) root.diskChecks()
                if ((scenario === "long-list" || scenario === "long-table") && md.contentReady) root.containerChecks()
                root.check("probe completes", "timeout stage " + stage, "complete")
                root.finish()
                return
            }
            if (scenario === "disk") {
                if (stage === 0 && quick.markdownItem && quick.markdownItem.contentReady
                        && column.markdown && column.markdown.contentReady) {
                    root.check("Quick Look initially reads file", quick.textShown(), "Before disk edit.\n")
                    root.check("column initially reads file", column.markdown.rawText, "Before disk edit.\n")
                    rewrite.running = true
                    root.stage = 1
                    return
                }
                // The edit is the event under test: wait until all three readers show it, the give-up reports a miss.
                if (stage === 1 && rewritten && watchedControl.text() === root.editedText && quick.textShown() === root.editedText
                        && column.markdown.rawText === root.editedText) {
                    root.diskChecks()
                    root.finish()
                }
                return
            }
            if (scenario === "disk-rename") {
                if (stage === 0 && md.contentReady) {
                    root.check("document initially reads file", md.rawText, "Before disk edit.\n")
                    rewrite.running = true
                    root.stage = 1
                    return
                }
                // The product reload is the event under test, so wait for it; the global timeout reports a miss.
                if (stage === 1 && rewritten && md.rawText === "After disk edit.\n") {
                    root.check("document follows a file replaced by rename", md.rawText, "After disk edit.\n")
                    root.finish()
                }
                return
            }
            if (scenario === "disk-scroll") {
                if (stage === 0 && md.contentReady && md.flickContentHeight > md.height * root.scrollableScreens) {
                    md.bodyItem.contentY = root.scrollTargetY
                    root.scrolledY = md.bodyItem.contentY
                    root.check("scrolled into the document", root.scrolledY, root.scrollTargetY)
                    rewrite.running = true
                    root.stage = 1
                    return
                }
                if (stage === 1 && rewritten && md.rawText.indexOf("edited paragraph 0.") === 0) {
                    root.stage = 2
                    return
                }
                // The reparse lands and the list lays out over a few turns; count them rather than time them.
                if (stage >= 2 && stage < 5) {
                    root.stage++
                    return
                }
                if (stage === 5 && md.contentReady) {
                    root.check("disk edit keeps the scroll position", md.bodyItem.contentY, root.scrolledY)
                    root.check("edited text is drawn", md.rawText.indexOf("edited paragraph 0.") === 0, true)
                    root.finish()
                }
                return
            }
            if (scenario === "disk-stale") {
                if (stage === 0 && md.contentReady) {
                    md.path = root.otherFixture
                    root.stage = 1
                    return
                }
                if (stage === 1 && md.contentReady && md.rawText === "Other file.\n") {
                    rewrite.running = true
                    root.stage = 2
                    return
                }
                // The watched control on the old file proves the edit happened and was announced.
                if (stage === 2 && rewritten && oldWatch.text() === "After disk edit.\n") {
                    root.stage = 3
                    return
                }
                if (stage >= 3 && stage < 6) {
                    root.stage++
                    return
                }
                if (stage === 6) {
                    root.check("control saw the old file change", oldWatch.text(), "After disk edit.\n")
                    root.check("shown file is not reloaded from the old path", md.rawText, "Other file.\n")
                    root.finish()
                }
                return
            }
            if (!md.contentReady || Date.now() - root.stamp < root.warmupMs) return
            if (scenario === "local-image") {
                var block = md.blockItem(0)
                var images = descendants(block).filter(function (node) {
                    return node.visible && node.source !== undefined && node.asynchronous !== undefined
                        && String(node.source) !== ""
                })
                if (!images.length || images[0].status !== Image.Ready) return
                var image = images[0]
                root.check("same-folder image loads locally", String(image.source).indexOf("file:") === 0, true)
                root.check("local image decoded original aspect", [image.sourceSize.width, image.sourceSize.height], [1200, 600])
                root.check("local image block fits scaled picture without blank bands", Math.round(block.height), Math.round(image.width / 2))
                root.finish()
                return
            }
            if (scenario === "long-list" || scenario === "long-table") {
                // The chunks build and are placed over turns after the parse lands; wait until the rows the checks read are alive and still, the give-up reports a miss.
                if (!root.rowsSettled()) return
                root.containerChecks()
                root.finish()
                return
            }
            if (scenario === "theme") {
                if (stage === 0) {
                    root.initialInk = md.inkHex
                    root.check("native link initially uses theme ink", nativeLinkInk(textOf(md.blockItem(0))), initialInk)
                    root.check("the theme file scrolls", md.flickContentHeight > md.height * root.scrollableScreens, true)
                    md.bodyItem.contentY = root.scrollTargetY
                    root.scrolledY = md.bodyItem.contentY
                    root.check("scrolled into the document", root.scrolledY, root.scrollTargetY)
                    Flea.Theme.applyColors('background = "#ffffff"\nforeground = "#202020"')
                    root.stage = 1
                    root.stamp = Date.now()
                    return
                }
                // The reparse lands and the list lays out over a few turns; count them rather than time them.
                if (++root.settleTicks <= root.themeSettleTicks) return
                root.check("theme flip changed live palette", md.inkHex !== initialInk, true)
                root.check("shown link follows new theme ink", nativeLinkInk(textOf(md.blockItem(0))), md.inkHex)
                root.check("a theme switch keeps the scroll position", md.bodyItem.contentY, root.scrolledY)
                root.finish()
                return
            }
            if (scenario === "links") {
                if (stage === 0) {
                    root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", window.contentItem)
                    root.check("handler control starts", Qt.openUrlExternally("https://example.invalid/control"), true)
                    root.stage = 1
                    root.stamp = Date.now()
                    return
                }
                if (stage === 1) {
                    // No read may stay in flight into the clicks, or the first click's launch is counted late.
                    openLog.reload()
                    openLog.waitForJob()
                    if (launchLines().length < 1) return
                    root.check("positive control reached native URL dispatch", launchLines(), ["called"])
                    // Paragraphs in one run share a Text; click each native anchor by its URL hit region.
                    var node = textOf(md.blockItem(0))
                    var urls = ["http://example.invalid/http", "https://example.invalid/https", "mailto:test@example.invalid", "./other.md", "#heading"]
                    var points = ({})
                    for (var y = 0; y < Math.ceil(node.height); y++)
                        for (var x = 0; x < Math.ceil(node.width); x++) {
                            var url = node.linkAt(x, y)
                            if (url !== "" && points[url] === undefined) points[url] = { x: x, y: y }
                        }
                    node.linkActivated.connect(function (url) { root.clicked.push(String(url)) })
                    for (var i = 0; i < urls.length; i++) {
                        var point = points[urls[i]]
                        root.check("native link hit region exists " + urls[i], point !== undefined, true)
                        var before = launchLines().length
                        if (point !== undefined)
                            keys.mouseClick(node, point.x, point.y, Qt.LeftButton, Qt.NoModifier, -1)
                        openLog.reload()
                        openLog.waitForJob()
                        root.check("click dispatch increment " + urls[i], launchLines().length - before, i < 3 ? 1 : 0)
                    }
                    root.check("real clicks emit five native link signals", clicked, urls)
                    root.stage = 2
                    root.stamp = Date.now()
                    return
                }
                openLog.reload()
                if (!openLog.loaded) return
                var launched = launchLines()
                root.check("three external links dispatch and two internal links stay inside", launched.length, 4)
                root.finish()
            }
        }
    }
}
