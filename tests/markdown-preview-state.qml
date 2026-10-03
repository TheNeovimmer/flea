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
        var reply = new Function("root", "messageObject", body(source, "onMessage: function"))
        reply(root, { seq: root.parseSeq, error: "probe worker fault" })
        check(root.appliedSeq === root.parseSeq && !root.loading
            && root.status === "This file could not be read.", "F40 worker error settles loading and status")

        file.loaded = false
        check(!root.loading, "F40 parse error stays settled with unloaded reader")
        var markdown = { blocks: function () { return [] }, dirOf: function () { return "/doc" } }
        var timer = { restart: function () {} }
        var parser = { sendMessage: function () {} }
        var ask = new Function("root", "file", "Markdown", "parseFallback", "parser",
            body(source, "function askParse()"))
        root.askParse = function () {}
        root.path = "/doc/B.md"
        new Function("root", body(source, "    onPathChanged: {"))(root)
        check(root.parseError === "" && root.status === "loading", "F41 unloaded path clears previous error")
        root.askParse = function () { ask(root, file, markdown, timer, parser) }
        root.parseError = "probe previous fault"
        root.askParse()
        check(root.parseError === "", "F41 askParse clears error before unloaded return")

        file.loaded = true
        root.parsing = true
        markdown.blocks = function () { throw new Error("probe parse fault") }
        var fallbackSource = source.slice(source.indexOf("id: parseFallback"))
        var fallback = new Function("root", "Markdown", body(fallbackSource, "onTriggered:"))
        var escaped = false
        try {
            fallback(root, markdown)
        } catch (error) {
            escaped = true
        }
        check(!escaped && root.parseError === "probe parse fault" && root.appliedSeq === root.parseSeq
            && !root.loading && root.status === "This file could not be read.", "F42 throwing fallback settles error")
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
        // Sample input: FileView { id: file, then path: (root.active && !root.tooLarge) ? root.path : "" on its own line.
        var readerPath = expression(body(markdownSource, "FileView {"), /\n\s*path:([^\n]*)/)
        var probe = Qt.createQmlObject('import QtQuick\nQtObject {\n'
            + 'id: item\nproperty var root: ({ path: "/remote/A.md", row: { s: ' + remoteRowBytes + ' }, visible: true, '
            + 'manualHold: false, rowState: "text", isMarkdownRow: true, textLimit: ' + remoteLimitBytes + ', truncateText: true })\n'
            + 'property var facts: ({ TEXT: "text" })\nproperty var viewState: ({ markdownView: "rendered" })\n'
            + 'property bool active: false\nproperty string path: ""\nproperty int size: 0\n'
            + 'property int maxBytes: ' + defaultReaderLimitBytes + '\nproperty string view: ""\nproperty bool truncate: false\n'
            + 'property var seen: []\nreadonly property bool tooLarge:' + tooLarge + '\n'
            + 'readonly property string readerPath:' + readerPath + '\n'
            + 'onReaderPathChanged: seen.push(readerPath)\n'
            + 'function apply() {' + callback.replace(/Facts\./g, "facts.").replace(/ViewState\./g, "viewState.")
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
        var marker = "                    Column {\n                        id: listGrid"
        var column = "Column {" + body(source, marker) + "}"
        column = column.replace(/Theme\./g, "theme.")
        var probe = Qt.createQmlObject('import QtQuick\nItem {\nwidth: ' + geometryWidth + '\n'
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
        lazyChecks()
        bindingChecks(source)
        commentChecks(source)
        geometryChecks(source)
    }
}
