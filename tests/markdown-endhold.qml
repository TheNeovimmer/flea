import QtQuick

// The shipped end-follow wired to a real lazy ListView: a reader scrolling through blocks that are not built yet is never run to the end.
QtObject {
    id: gate
    property Item sandbox: Item {}
    property int checks: 0
    property int failures: 0
    // A short run of one-line blocks, then a few tall ones the list has not built when the document opens, so its first estimate falls short.
    readonly property int shortBlocks: 26
    readonly property int shortPx: 40
    readonly property int tallBlocks: 3
    readonly property int tallPx: 700
    readonly property int viewPx: 400
    readonly property int insetPx: 16
    readonly property int gapPx: 6
    readonly property int viewWidthPx: 400
    // One wheel step, the way a notch moves the view, and how many a reader makes.
    readonly property int notchPx: 200
    readonly property int notches: 8
    // The most steps a reader takes to reach the end of the document.
    readonly property int reachLimit: 60
    // A layout pass builds what the last one moved into range, so a frame is as many passes as it takes to hold still.
    readonly property int layoutPassLimit: 12
    // A late picture grows the last block by this much.
    readonly property int pictureGrowPx: 80
    // How far from the drawn end still counts as at it once the last block has grown.
    readonly property real followTolerancePx: 1

    function readSource(path) {
        var request = new XMLHttpRequest()
        request.open("GET", Qt.resolvedUrl(path), false)
        request.send()
        return request.responseText
    }

    // Sample input: function holdEnd() { var was = root.seenHeight ... } answering the text between its braces, null when the source has none.
    function body(source, marker) {
        var markerAt = source.indexOf(marker)
        if (markerAt < 0)
            return null
        var start = source.indexOf("{", markerAt)
        var depth = 1
        var end = start + 1
        for (; depth && end < source.length; end++) {
            if (source[end] === "{")
                depth++
            if (source[end] === "}")
                depth--
        }
        return source.slice(start + 1, end - 1)
    }

    function check(ok, name) {
        checks++
        console.log((ok ? "ok " : "FAIL ") + name)
        if (!ok)
            failures++
    }

    // Sample input: onContentHeightChanged: root.holdEnd(), answering "root.holdEnd()".
    function handler(source, name) {
        var found = source.match(new RegExp(name + ":\\s*([^\\n]*)"))
        return found ? found[1] : ""
    }

    // Sample input: readonly property int blockCachePixels: 600, answering 600, NaN when the source has none.
    function shippedCache(source) {
        var found = source.match(/readonly property int blockCachePixels: (\d+)/)
        return found ? parseInt(found[1]) : NaN
    }

    // The shipped functions on a stand-in root, over a real ListView built from the shipped cache and list geometry.
    function build(source, cache, heights) {
        var list = Qt.createQmlObject('import QtQuick\nListView { width: ' + viewWidthPx + '; height: ' + viewPx + '; clip: true\n'
            + 'spacing: ' + gapPx + '; topMargin: ' + insetPx + '; bottomMargin: ' + insetPx + '; cacheBuffer: ' + cache + '\n'
            + 'property int tailPx: 0\n'
            + 'delegate: Item { property int blockIndex: index; width: ListView.view.width\n'
            + 'height: index === ListView.view.count - 1 ? ListView.view.tailPx + modelData : modelData } }', gate.sandbox)
        var root = { seenHeight: 0, endBuilt: false, snappingToEnd: false, samePlacePx: 1, blockList: heights }
        root.releaseHeldPlace = function () {}
        root.blockItem = new Function("body", "i", body(source, "function blockItem(i)")).bind(null, list)
        var note = body(source, "function noteEnd()")
        root.noteEnd = note === null ? function () {} : new Function("root", note).bind(null, root)
        var hold = new Function("root", "body", body(source, "function holdEnd()"))
        root.holdEnd = function () { hold(root, list) }
        list.contentHeightChanged.connect(new Function("root", handler(source, "onContentHeightChanged")).bind(null, root))
        list.model = heights
        gate.settle(list)
        return { list: list, root: root }
    }

    function settle(list) {
        for (var pass = 0; pass < layoutPassLimit; pass++) {
            var y = list.contentY
            var h = list.contentHeight
            list.forceLayout()
            if (list.contentY === y && list.contentHeight === h)
                return
        }
    }

    function endOf(list) {
        return list.originY + list.contentHeight - list.height + list.bottomMargin
    }

    // A wheel step is bounded by the end the list draws, which is an estimate while blocks are unbuilt.
    function wheel(list) {
        list.contentY = Math.min(list.contentY + notchPx, endOf(list))
        settle(list)
    }

    function document() {
        var heights = []
        for (var i = 0; i < shortBlocks; i++)
            heights.push(shortPx)
        for (var j = 0; j < tallBlocks; j++)
            heights.push(tallPx)
        return heights
    }

    function walkChecks(source, cache) {
        var shown = build(source, cache, document())
        var list = shown.list
        // The hazard must arise: the last block starts unbuilt and the height grows as the walk builds toward it.
        var unbuiltAtStart = shown.root.blockItem(list.count - 1) === null
        var heightAtStart = list.contentHeight
        var moved = true
        var written = list.contentY
        for (var n = 0; n < notches && moved; n++) {
            written = Math.min(list.contentY + notchPx, endOf(list))
            list.contentY = written
            settle(list)
            moved = list.contentY === written
        }
        check(unbuiltAtStart && list.contentHeight > heightAtStart,
            "the walk meets the hazard: the last block unbuilt at the start and the height grown by the end (unbuilt " + unbuiltAtStart + ", "
            + heightAtStart + " to " + list.contentHeight + ")")
        check(moved, "a reader scrolling through unbuilt blocks moves only by the wheel steps (at " + list.contentY + " after writing " + written + ")")
        check(list.contentY < endOf(list), "the reader scrolling through unbuilt blocks is not run to the document's end (at " + list.contentY + " of " + endOf(list) + ")")
        list.destroy()
    }

    // The control: a reader who reached the drawn end of a built last block keeps it in view when that block grows.
    function followChecks(source, cache) {
        var shown = build(source, cache, document())
        var list = shown.list
        var reached = false
        for (var n = 0; n < reachLimit && !reached; n++) {
            gate.wheel(list)
            reached = shown.root.blockItem(list.count - 1) !== null && list.atYEnd
        }
        check(reached, "the control reader reaches the end with the last block built")
        var before = endOf(list)
        list.tailPx = pictureGrowPx
        settle(list)
        check(list.atYEnd && endOf(list) === before + pictureGrowPx && Math.abs(list.contentY - endOf(list)) < followTolerancePx,
            "a reader at the drawn end follows the last block when a picture grows it (at " + list.contentY + " of " + endOf(list) + ")")
        list.destroy()
    }

    function run() {
        var source = readSource("../ui/PreviewMarkdown.qml")
        var cache = shippedCache(source)
        check(cache > 0, "PreviewMarkdown.qml declares blockCachePixels")
        if (!(cache > 0)) {
            console.log("MARKDOWN_ENDHOLD " + checks + " checks, " + failures + " failed")
            Qt.exit(1)
            return
        }
        walkChecks(source, cache)
        followChecks(source, cache)
        console.log("MARKDOWN_ENDHOLD " + checks + " checks, " + failures + " failed")
        Qt.exit(failures ? 1 : 0)
    }

    Component.onCompleted: Qt.callLater(run)
}
