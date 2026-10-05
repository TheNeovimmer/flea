import QtQuick

// Execute shipped callbacks and bindings without a native FileView or worker dependency.
QtObject {
    id: gate
    property Item sandbox: Item {}
    property int checks: 0
    property int failures: 0
    readonly property int remoteRowBytes: 600 * 1024
    readonly property int remoteLimitBytes: 256 * 1024
    readonly property int defaultReaderLimitBytes: 1024 * 1024
    readonly property int geometryWidth: 400
    readonly property int geometryGap: 8
    readonly property int geometryFontPixels: 16
    // The hold checks: a list of holdContentPx in a view of holdViewPx, a hold waiting at holdAtPx for a place at holdSavedPx, a reader who moves to holdReaderPx.
    readonly property int holdContentPx: 5000
    readonly property int holdViewPx: 500
    readonly property int holdAtPx: 100
    readonly property int holdSavedPx: 300
    readonly property int holdReaderPx: 40

    function readSource(path) {
        var request = new XMLHttpRequest()
        request.open("GET", Qt.resolvedUrl(path), false)
        request.send()
        return request.responseText
    }

    // Sample input: onMessage: function (messageObject) { if (...) return; ... }
    function body(source, marker) {
        var markerAt = source.indexOf(marker)
        if (markerAt < 0)
            throw new Error("missing callback " + marker)
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

    function stateChecks(source) {
        var file = { loaded: true }
        var root = { active: true, tooLarge: false, readFailed: false, parseError: "",
            parseSeq: 7, appliedSeq: 6, parsing: true, blockList: [], path: "/doc/A.md" }
        // Sample input: readonly property bool loading: root.active && ... followed by status.
        var loading = source.match(/readonly property bool loading:([\s\S]*?)readonly property string status:/)[1]
        Object.defineProperty(root, "blocksReady", { get: function () {
            return root.parseSeq === root.appliedSeq && !root.parsing
        } })
        Object.defineProperty(root, "loading", { get: function () {
            return new Function("root", "file", "return " + loading)(root, file)
        } })
        Object.defineProperty(root, "status", { get: function () {
            return new Function("root", "file", body(source, "readonly property string status:"))(root, file)
        } })
        var landed = new Function("root", "messageObject", body(source, "function landed(messageObject)"))
        root.landed = function (messageObject) { landed(root, messageObject) }
        var reply = new Function("root", "messageObject", body(source, "onMessage: function"))
        reply(root, { seq: root.parseSeq, error: "probe worker fault" })
        check(root.appliedSeq === root.parseSeq && !root.loading
            && root.status === "This file could not be read.", "F40 worker error settles loading and status")

        file.loaded = false
        check(!root.loading, "F40 parse error stays settled with unloaded reader")
        var markdown = { blocks: function () { return [] }, dirOf: function () { return "/doc" } }
        var timer = { restart: function () {}, stop: function () {} }
        var parserLoader = { active: false, item: { sendMessage: function () {} } }
        var ask = new Function("root", "file", "Markdown", "parseFallback", "parserLoader",
            body(source, "function askParse()"))
        // The shipped dropParse, parseNow and restoreScroll bodies, bound to the stub root over an empty stub list.
        var drop = new Function("root", body(source, "function dropParse()"))
        var landing = new Function("root", "Markdown", "text", "dir", "chrome", "ink", body(source, "function parseNow("))
        var restore = new Function("root", "body", body(source, "function restoreScroll()"))
        var remember = new Function("root", "body", body(source, "function rememberScroll()"))
        var list = { originY: 0, topMargin: 0, bottomMargin: 0, contentHeight: 0, height: 0, contentY: 0 }
        root.dropParse = function () { drop(root) }
        root.parseNow = function (text, dir, chrome, ink) { landing(root, markdown, text, dir, chrome, ink) }
        root.restoreScroll = function () { restore(root, list) }
        root.rememberScroll = function () { remember(root, list) }
        root.askParse = function () {}
        // File pointing belongs to quicklook-firstframe; the path handler only needs it callable here.
        root.pointFile = function () {}
        root.path = "/doc/B.md"
        new Function("root", "reloadCoalesce", body(source, "    onPathChanged: {"))(root, { stop: function () {} })
        check(root.parseError === "" && root.status === "loading", "F41 unloaded path clears previous error")
        root.askParse = function () { ask(root, file, markdown, timer, parserLoader) }
        root.parseError = "probe previous fault"
        root.askParse()
        check(root.parseError === "", "F41 askParse clears error before unloaded return")

        file.loaded = true
        root.parsing = true
        markdown.blocks = function () { throw new Error("probe parse fault") }
        var fallbackSource = source.slice(source.indexOf("id: parseFallback"))
        var fallback = new Function("root", "Markdown", body(fallbackSource, "onTriggered:"))
        root.askedText = "doc"
        root.askedDir = "/doc"
        var escaped = false
        try {
            fallback(root, markdown)
        } catch (error) {
            escaped = true
        }
        check(!escaped && root.parseError === "probe parse fault" && root.appliedSeq === root.parseSeq
            && !root.loading && root.status === "This file could not be read.", "F42 throwing fallback settles error")

        // A path change or a failed load drops keepScroll and leaves heldY, so the next place taken must clear it.
        var held = { keepScroll: false, heldY: 40, savedY: 0 }
        remember(held, { contentY: 300 })
        check(held.keepScroll && held.savedY === 300 && isNaN(held.heldY), "F43 a new place starts with no hold waiting")
    }

    // A stub root and list running the shipped place functions; assigning blockList resets the list to its top, as the real model does.
    function holdStub(source) {
        var list = { originY: 0, topMargin: 0, bottomMargin: 0, contentHeight: holdContentPx, height: holdViewPx, contentY: 0 }
        var root = { keepScroll: false, heldY: NaN, savedY: 0, settingBlocks: false, samePlacePx: 1, parseSeq: 3,
            appliedSeq: 2, parsing: true, parseError: "", parsedOffThread: false, askedAny: true, blocksSet: 0 }
        var blocks = []
        Object.defineProperty(root, "blockList", { get: function () { return blocks },
            set: function (value) { blocks = value; root.blocksSet++; list.contentY = 0 } })
        var release = new Function("root", "body", body(source, "function releaseHeldPlace()"))
        var remember = new Function("root", "body", body(source, "function rememberScroll()"))
        var restore = new Function("root", "body", body(source, "function restoreScroll()"))
        root.releaseHeldPlace = function () { release(root, list) }
        root.rememberScroll = function () { remember(root, list) }
        root.restoreScroll = function () { restore(root, list) }
        return { root: root, list: list }
    }

    // A hold waits at holdAtPx for a place at holdSavedPx; the reader then moves to holdReaderPx and the hold is released.
    function holdChecks(source) {
        var parse = new Function("root", "Markdown", "text", "dir", "chrome", "ink", body(source, "function parseNow("))
        var markdown = { blocks: function () { return ["parsed"] } }
        var sync = holdStub(source)
        sync.root.keepScroll = true
        sync.root.savedY = holdSavedPx
        sync.root.heldY = holdAtPx
        sync.list.contentY = holdReaderPx
        sync.root.releaseHeldPlace()
        parse(sync.root, markdown, "text", "/doc", "chrome", "ink")
        check(sync.list.contentY === holdReaderPx && !sync.root.keepScroll && isNaN(sync.root.heldY),
            "F48 a hold released in flight lands at the reader's place (got " + sync.list.contentY + ")")

        var worker = holdStub(source)
        var landed = new Function("root", "messageObject", body(source, "function landed(messageObject)"))
        worker.root.keepScroll = true
        worker.root.savedY = holdSavedPx
        worker.root.heldY = holdAtPx
        worker.list.contentY = holdReaderPx
        worker.root.releaseHeldPlace()
        landed(worker.root, { seq: worker.root.parseSeq, error: "", blocks: ["parsed"] })
        check(worker.list.contentY === holdReaderPx && !worker.root.keepScroll && isNaN(worker.root.heldY)
            && worker.root.blocksSet === 1, "F49 a worker landing after a released hold lands at the reader's place (got "
            + worker.list.contentY + ")")

        // A parse that throws replaces no model, so it must take no place: nothing would land to release it.
        var failing = holdStub(source)
        failing.list.contentY = holdReaderPx
        parse(failing.root, { blocks: function () { throw new Error("probe parse fault") } }, "text", "/doc", "chrome", "ink")
        check(!failing.root.keepScroll && failing.root.blocksSet === 0 && !failing.root.settingBlocks
            && failing.root.parseError === "probe parse fault", "F50 a parse that throws takes no place and replaces no model")
    }

    // The reader's place at the end of the list: a block above the end growing must not leave them short of it.
    readonly property int endContentPx: 3000
    readonly property int endViewPx: 500
    readonly property int endInsetPx: 16
    readonly property int endGrowPx: 80
    readonly property real endRoundingPx: 0.5
    function endStub(source) {
        var list = { originY: 0, topMargin: endInsetPx, bottomMargin: endInsetPx, contentHeight: endContentPx, height: endViewPx, contentY: 0 }
        var root = { seenHeight: 0, endBuilt: false, lastBuilt: true, snappingToEnd: false, samePlacePx: 1, blockList: ["first", "last"] }
        root.blockItem = function () { return root.lastBuilt ? {} : null }
        var note = new Function("root", body(source, "function noteEnd()"))
        root.noteEnd = function () { note(root) }
        var hold = new Function("root", "body", body(source, "function holdEnd()"))
        root.holdEnd = function () { hold(root, list) }
        // The list's own height change: the new height is seen by the shipped handler, as onContentHeightChanged does.
        root.grow = function (by) { list.contentHeight += by; root.holdEnd() }
        root.holdEnd()
        return { root: root, list: list }
    }

    function endChecks(source) {
        var end = endContentPx - endViewPx + endInsetPx
        var held = endStub(source)
        held.list.contentY = end
        held.root.grow(endGrowPx)
        check(held.list.contentY === end + endGrowPx, "N1 a view that sat at its end follows a block that grows (got " + held.list.contentY + ")")
        held.root.grow(endGrowPx)
        check(held.list.contentY === end + 2 * endGrowPx && !held.root.snappingToEnd, "N1 it keeps following the next block that grows")

        var near = endStub(source)
        near.list.contentY = end - endRoundingPx
        near.root.grow(endGrowPx)
        check(near.list.contentY === end + endGrowPx, "N1 a view within a pixel of its end counts as at it (got " + near.list.contentY + ")")

        var away = endStub(source)
        away.list.contentY = end - endGrowPx
        away.root.grow(endGrowPx)
        check(away.list.contentY === end - endGrowPx, "N1 a reader who left the end is not pulled back (got " + away.list.contentY + ")")

        var top = endStub(source)
        top.list.contentY = -endInsetPx
        top.root.grow(endGrowPx)
        check(top.list.contentY === -endInsetPx, "N1 a view at the top stays there when a block grows (got " + top.list.contentY + ")")

        var fits = endStub(source)
        fits.list.contentHeight = endViewPx - endGrowPx
        fits.root.holdEnd()
        fits.list.contentY = -endInsetPx
        fits.root.grow(2 * endGrowPx)
        check(fits.list.contentY === -endInsetPx, "N1 a document that fitted the view is not scrolled when it grows past it (got " + fits.list.contentY + ")")

        var shrunk = endStub(source)
        shrunk.list.contentY = end
        shrunk.root.grow(-endGrowPx)
        check(shrunk.list.contentY === end, "N1 a list that shrinks moves nothing")

        var unbuilt = endStub(source)
        unbuilt.root.lastBuilt = false
        unbuilt.root.holdEnd()
        unbuilt.list.contentY = end
        unbuilt.root.grow(endGrowPx)
        check(unbuilt.list.contentY === end, "N1 a reader at an estimated end, the last block unbuilt, is not run to the new end (got " + unbuilt.list.contentY + ")")

        var building = endStub(source)
        building.root.lastBuilt = false
        building.root.holdEnd()
        building.list.contentY = end
        building.root.lastBuilt = true
        building.root.grow(endGrowPx)
        check(building.list.contentY === end, "N1 the growth that builds the last block does not carry the reader to it (got " + building.list.contentY + ")")
        building.list.contentY = end + endGrowPx
        building.root.grow(endGrowPx)
        check(building.list.contentY === end + 2 * endGrowPx, "N1 once the reader is at the drawn end, the next growth is followed (got " + building.list.contentY + ")")
    }

    // A refill that grows the list on every contentY write must not recurse: the snap writes once and the settling height is only seen.
    function reentryChecks(source) {
        var held = endStub(source)
        var writes = 0
        var stored = endContentPx - endViewPx + endInsetPx
        Object.defineProperty(held.list, "contentY", {
            get: function () { return stored },
            set: function (value) {
                stored = value
                writes++
                held.list.contentHeight += endGrowPx
                held.root.holdEnd()
            }
        })
        // The stub's own first holdEnd primed these, so the growth below reaches the snap and no earlier exit.
        var primed = held.root.endBuilt && held.root.seenHeight === endContentPx
        var error = ""
        try {
            held.root.grow(endGrowPx)
        } catch (thrown) {
            error = String(thrown)
        }
        check(primed && error === "" && writes === 1 && !held.root.snappingToEnd, "N1 a height that settles under the snap does not re-enter it (primed " + primed + ", endBuilt " + held.root.endBuilt + ", seenHeight " + held.root.seenHeight + " of " + endContentPx + ", writes " + writes + ", snappingToEnd " + held.root.snappingToEnd + " " + error + ")")
    }

    function lazyChecks() {
        var source = readSource("markdown-lazy.qml")
        var shell = { done: false, failed: false, log: function () {}, quit: function () {},
            fail: function () { this.failed = true } }
        var md = { contentReady: true, blockList: ["drawn"], parsedOffThread: true,
            bodyItem: { forceLayout: function () {} }, delegateCount: function () { return 0 } }
        new Function("shell", "md", body(source, "function report()"))(shell, md)
        check(shell.failed, "F39 zero delegates fail after forceLayout")
    }

    // Sample input: readonly property bool tooLarge: root.size > root.maxBytes, answering " item.size > item.maxBytes".
    function expression(source, pattern) {
        var found = source.match(pattern)
        if (!found)
            throw new Error("missing shipped expression " + pattern)
        return found[1].replace(/\broot\./g, "item.")
    }

    // The reader gate: PreviewColumn's onLoaded wiring driving the shipped tooLarge and FileView path expressions.
    function readerGate(markdownSource, columnSource) {
        var callback = body(columnSource.slice(columnSource.indexOf("id: markdownLoader")), "onLoaded:")
        var tooLarge = expression(markdownSource, /readonly property bool tooLarge:([^\n]*)/)
        // Sample input: function pointFile() { then var want = (root.active && !root.tooLarge) ? root.path : "" on its own line.
        var readerPath = expression(body(markdownSource, "function pointFile()"), /\n\s*var want =([^\n]*)/)
        var probe = Qt.createQmlObject('import QtQuick\nQtObject {\n'
            + 'id: item\nproperty var root: ({ path: "/remote/A.md", row: { s: ' + remoteRowBytes + ' }, visible: true, '
            + 'manualHold: false, rowState: "text", isMarkdownRow: true, textLimit: ' + remoteLimitBytes + ', truncateText: true })\n'
            + 'property var facts: ({ TEXT: "text" })\n'
            + 'property bool active: false\nproperty string path: ""\nproperty int size: 0\n'
            + 'property int maxBytes: ' + defaultReaderLimitBytes + '\nproperty bool truncate: false\nproperty bool compact: false\n'
            + 'property var seen: []\nreadonly property bool tooLarge:' + tooLarge + '\n'
            + 'readonly property string readerPath:' + readerPath + '\n'
            + 'onReaderPathChanged: seen.push(readerPath)\n'
            + 'function apply() {' + callback.replace(/Facts\./g, "facts.")
            + '} }', gate.sandbox)
        // Evaluate the observer before installing bindings so intermediate reader paths are recorded.
        var initialPath = probe.readerPath
        probe.apply()
        // The row is over the limit from the start, so any path the reader saw on the way is an exposure.
        var safe = probe.seen.every(function (path) { return path === "" })
        var sized = probe.size === remoteRowBytes
        var guarded = initialPath === "" && safe && probe.active && sized
            && probe.maxBytes === remoteLimitBytes && probe.readerPath === ""
        probe.size = remoteLimitBytes
        var allowed = probe.readerPath === probe.root.path && probe.seen.length > 0
        probe.destroy()
        return { guarded: guarded, allowed: allowed, sized: sized, exposed: !safe }
    }

    function bindingChecks(source) {
        var column = readSource("../ui/PreviewColumn.qml")
        var shipped = readerGate(source, column)
        check(shipped.guarded, "F47 oversized remote row never exposes FileView path")
        // GM 2026-10-03: the column never draws Source, so its wiring names no view and reads no stored choice.
        var wiring = body(column.slice(column.indexOf("id: markdownLoader")), "onLoaded:")
        check(wiring.indexOf("item.view") < 0 && wiring.indexOf("markdownView") < 0 && wiring.indexOf("ViewState") < 0,
            "F51 the column Markdown wiring sets no view and reads no stored choice")
        check(shipped.allowed, "F47 allowed row exposes reader path")
        var unguardedPath = source.replace("(root.active && !root.tooLarge) ? root.path", "root.active ? root.path")
        check(unguardedPath !== source && !readerGate(unguardedPath, column).guarded,
            "F47 control: a reader path without the tooLarge guard is caught")
        var blindLimit = source.replace("readonly property bool tooLarge: root.size > root.maxBytes",
            "readonly property bool tooLarge: false")
        check(blindLimit !== source && !readerGate(blindLimit, column).guarded,
            "F47 control: a tooLarge without its comparison is caught")
        var sizeLine = "item.size = Qt.binding(function () { return root.row ? root.row.s : 0 })"
        var lastLine = "item.truncate = Qt.binding(function () { return root.truncateText })"
        var lateSize = column.replace(sizeLine, "").replace(lastLine, lastLine + "\n" + sizeLine)
        var late = readerGate(source, lateSize)
        // The moved binding still ran, so the row reached its size and only the path seen on the way fails the gate.
        check(lateSize.indexOf(sizeLine) > lateSize.indexOf(lastLine) && late.sized && late.exposed && !late.guarded,
            "F47 control: a size bound after active is caught")
    }

    function commentChecks(source) {
        var quick = readSource("../ui/Preview.qml")
        var column = readSource("../ui/PreviewColumn.qml")
        check(!/\/\/ The worker owns[^\n]*\n\s*\/\//.test(source)
            && !/\/\/ The Markdown bar[^\n]*\n\s*\/\//.test(quick)
            && !/\/\/ The lazy Markdown pane[^\n]*\n\s*\/\//.test(column)
            && quick.indexOf("cost nothing") < 0, "F45 comments state one-line constraints and null assertion")
    }

    function geometryChecks(source) {
        var marker = "                Column {\n                    id: listGrid"
        var column = "Column {" + body(source, marker) + "}"
        // The pane's Markdown module is not imported by the probe, so its link gate reads as a closed one.
        column = column.replace(/Theme\./g, "theme.").replace(/Markdown\.isExternalLink/g, "(function () { return false })")
            .replace(/blockDelegate\.width/g, "parent.width")
        // The runner supplies the shipped text component beside a local Theme for pure qml6.
        var textModule = Qt.resolvedUrl(Qt.application.arguments[Qt.application.arguments.length - 1])
        var probe = Qt.createQmlObject('import QtQuick\nimport "' + textModule + '" as Flea\nItem {\nwidth: ' + geometryWidth + '\n'
            + 'property var block: ({ type: "list", ordered: true, start: 9, items: ["nine", "ten"] })\n'
            + 'QtObject {\nid: theme\nproperty var spacing: ({ gap: ' + geometryGap + ' })\n'
            + 'property var color: ({ foreground: "#ffffff" })\n'
            + 'property var font: ({ family: "sans-serif", body: ' + geometryFontPixels + ' })\n}\n'
            + column + '}', gate.sandbox)
        Qt.callLater(function () {
            var list = probe.children[0]
            var rows = Array.prototype.filter.call(list.children, function (child) {
                return child.children.length === 2
            })
            check(rows.length === 2 && rows[0].children[1].x > 0
                && rows[0].children[1].x === rows[1].children[1].x, "F44 ordered items 9 and 10 share text x")
            probe.destroy()
            console.log("MARKDOWN_PREVIEW_STATE " + checks + " checks, " + failures + " failed")
            Qt.exit(failures ? 1 : 0)
        })
    }

    Component.onCompleted: Qt.callLater(run)

    function run() {
        var source = readSource("../ui/PreviewMarkdown.qml")
        stateChecks(source)
        holdChecks(source)
        endChecks(source)
        reentryChecks(source)
        lazyChecks()
        bindingChecks(source)
        commentChecks(source)
        geometryChecks(source)
    }
}
