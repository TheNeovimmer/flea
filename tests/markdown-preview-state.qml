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

    function bindingChecks() {
        var source = readSource("../ui/PreviewColumn.qml")
        var callback = body(source.slice(source.indexOf("id: markdownLoader")), "onLoaded:")
        var probe = Qt.createQmlObject('import QtQuick\nQtObject {\n'
            + 'id: item\nproperty var root: ({ path: "/remote/A.md", row: { s: ' + remoteRowBytes + ' }, visible: true, '
            + 'manualHold: false, rowState: "text", isMarkdownRow: true, textLimit: ' + remoteLimitBytes + ', truncateText: true })\n'
            + 'property var facts: ({ TEXT: "text" })\nproperty var viewState: ({ markdownView: "rendered" })\n'
            + 'property bool active: false\nproperty string path: ""\nproperty int size: 0\n'
            + 'property int maxBytes: ' + defaultReaderLimitBytes + '\nproperty string view: ""\nproperty bool truncate: false\n'
            + 'property var seen: []\nreadonly property string readerPath: active && size <= maxBytes ? path : ""\n'
            + 'onReaderPathChanged: seen.push({ path: readerPath, size: size, limit: maxBytes })\n'
            + 'function apply() {' + callback.replace(/Facts\./g, "facts.").replace(/ViewState\./g, "viewState.")
            + '} }', gate.sandbox)
        // Evaluate the observer before installing bindings so intermediate reader paths are recorded.
        var initialPath = probe.readerPath
        probe.apply()
        var safe = probe.seen.every(function (value) {
            return value.path === "" || value.size <= gate.remoteLimitBytes
        })
        check(initialPath === "" && safe && probe.active && probe.size === remoteRowBytes && probe.maxBytes === remoteLimitBytes
            && probe.readerPath === "", "F47 oversized remote row never exposes FileView path")
        probe.size = remoteLimitBytes
        check(probe.readerPath === probe.root.path && probe.seen.length > 0, "F47 allowed row exposes reader path")
        probe.destroy()
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
        bindingChecks()
        commentChecks(source)
        geometryChecks(source)
    }
}
