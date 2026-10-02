import QtQuick
import QtQml
import "../ui/js/Markdown.js" as Markdown

// Count string operations in Markdown.blocks at two sizes; durations are diagnostic only.
QtObject {
    function readSource(path) {
        var request = new XMLHttpRequest();
        request.open("GET", Qt.resolvedUrl(path), false);
        request.send();
        return request.responseText;
    }

    // Execute actual lifecycle callbacks with a pending replacement and a late worker reply.
    function callbackChecks() {
        const source = readSource('../ui/PreviewMarkdown.qml');
        // Sample input: function landed(messageObject) { if (...) return; ... }
        function body(marker, text = source) {
            const start = text.indexOf('{', text.indexOf(marker));
            let depth = 1, end = start + 1;
            for (; depth && end < text.length; end++) {
                if (text[end] === '{') depth++;
                if (text[end] === '}') depth--;
            }
            return text.slice(start + 1, end - 1);
        }
        let root, file;
        const Markdown = { blocks: () => ['fallback'], dirOf: () => '/doc' };
        const parseFallback = { restart() {}, stop() {} };
        const parserLoader = { active: false, item: { sendMessage() {} } };
        const ask = new Function('root', 'file', 'Markdown', 'parseFallback', 'parserLoader', body('function askParse()'));
        const reply = new Function('root', 'messageObject', body('function landed(messageObject)'));
        const fallbackHandler = 'onTriggered:';
        const fallbackMarker = source.indexOf(fallbackHandler, source.indexOf('id: parseFallback'));
        const fallback = new Function('root', 'Markdown', body(source.slice(fallbackMarker, fallbackMarker + fallbackHandler.length)));
        let failures = 0;
        function check(ok, name) { console.log((ok ? 'ok ' : 'FAIL ') + name); if (!ok) failures++; }
        root = { active: true, tooLarge: false, parseSeq: 5, parsing: true, blockList: [], path: '/doc/B.md' };
        file = { loaded: false };
        root.askParse = () => ask(root, file, Markdown, parseFallback, parserLoader);
        new Function('root', body('    onPathChanged: {'))(root);
        reply(root, { seq: 5, blocks: ['A'], error: '' });
        check(root.blockList.length === 0, 'F11 unloaded B rejects A worker reply');
        root = { parseSeq: 5, parsing: true, rawText: 'B', path: '/doc/B.md', blockList: [] };
        fallback(root, Markdown);
        reply(root, { seq: 5, blocks: ['late'], error: '' });
        check(root.blockList[0] === 'fallback', 'F10 fallback rejects late worker reply');
        root = { active: true, tooLarge: false, parseSeq: 5, rawText: 'small', workerThreshold: 65536,
            path: '/doc/small.md', blockList: [] };
        file.loaded = true;
        ask(root, file, Markdown, parseFallback, parserLoader);
        reply(root, { seq: 5, blocks: ['late'], error: '' });
        check(!parserLoader.active && root.blockList[0] === 'fallback'
            && root.appliedSeq === root.parseSeq && !root.parsing, 'small parse stays inline and rejects late worker reply');
        root.rawText = 'x'.repeat(root.workerThreshold + 1);
        let sent;
        parserLoader.item.sendMessage = message => { sent = message; };
        ask(root, file, Markdown, parseFallback, parserLoader);
        reply(root, { seq: sent.seq, blocks: ['worker'], error: '' });
        check(parserLoader.active && root.parsedOffThread && root.blockList[0] === 'worker'
            && root.appliedSeq === root.parseSeq, 'large parse still sends and lands through the worker');
        const lazy = readSource('markdown-lazy.qml');
        let shell = { done: false, log() { this.done = true; }, quit() {}, fail() { this.done = true; } };
        new Function('shell', 'md', body('function report()', lazy))(shell, { contentReady: false });
        check(!shell.done, 'F2 pending lazy readiness does not judge');
        const memory = readSource('markdown-memory.qml');
        shell.ready = false;
        new Function('shell', 'look', 'column', body('function advance()', memory))(shell, {}, {});
        check(!shell.done, 'F2 pending memory readiness does not judge');
        return failures === 0;
    }

    // Sample input: .import "MdLeaf.js" as Leaf, followed by function blocks(...).
    function loadLibrary(name, cache) {
        if (cache[name]) return cache[name];
        var exports = {};
        cache[name] = exports;
        var request = new XMLHttpRequest();
        request.open("GET", Qt.resolvedUrl("../ui/js/" + name), false);
        request.send();
        if (request.status !== 0 && request.status !== 200)
            throw new Error("cannot load " + name);
        var aliases = [], dependencies = [];
        var code = request.responseText.replace(/^\.pragma.*$/gm, "").replace(
            /^\.import "([^"]+)" as (\w+)\s*$/gm, function (_, file, alias) {
                aliases.push(alias); dependencies.push(loadLibrary(file, cache)); return "";
            });
        code = code.replace(/\.(charAt|indexOf|slice)\s*\(/g, function (_, method) {
            return ".counted_" + method + "(";
        });
        var names = [], declaration = /^(?:function|var)\s+(\w+)/gm, match;
        while ((match = declaration.exec(code)) !== null) names.push(match[1]);
        var fields = names.map(function (key) { return key + ":" + key; });
        var build = Function.apply(null, aliases.concat([code + "\nreturn {" + fields.join(",") + "};"]));
        var values = build.apply(null, dependencies);
        for (var key in values) exports[key] = values[key];
        return exports;
    }

    Component.onCompleted: {
        if (!callbackChecks()) { Qt.exit(1); return; }
        var small = 65536;
        var large = 524288;
        var dir = "/doc";
        var inputs = {
            codeDense: function (n) {
                var s = "";
                while (s.length < n)
                    s += "word `code" + (s.length % 97) + "` ";
                return s.slice(0, n);
            },
            codeOnly: function (n) {
                var s = "";
                while (s.length < n)
                    s += "`ab`";
                return s.slice(0, n);
            },
            bangOpen: function (n) {
                var s = "";
                while (s.length < n)
                    s += "![ ";
                return s.slice(0, n);
            },
            bracketOpen: function (n) {
                var s = "";
                while (s.length < n)
                    s += "[abc ";
                return s.slice(0, n);
            },
            angleOpen: function (n) {
                var s = "";
                while (s.length < n)
                    s += "<abc ";
                return s.slice(0, n);
            },
            delimSoup: function (n) {
                var s = "";
                while (s.length < n)
                    s += "*a **b ";
                return s.slice(0, n);
            },
            quoteDeep: function (n) {
                var depth = 500;
                var head = "";
                for (var d = 0; d < depth; d++)
                    head += "> ";
                var s = head + "deep\n";
                while (s.length < n)
                    s += head + "more text on a quoted line\n";
                return s.slice(0, n);
            },
            listDeep: function (n) {
                var s = "";
                var depth = 0;
                while (s.length < n) {
                    var pad = "";
                    for (var d = 0; d < depth % 12; d++)
                        pad += "  ";
                    s += pad + "- item at depth " + depth + "\n";
                    depth++;
                }
                return s.slice(0, n);
            },
            backtickRun: function (n) {
                var s = "";
                while (s.length < n)
                    s += "`a`b";
                return s.slice(0, n);
            }
        };
        var names = ["codeDense", "codeOnly", "bangOpen", "bracketOpen", "angleOpen",
            "delimSoup", "quoteDeep", "listDeep", "backtickRun"];
        var work = 0;
        var methods = ["charAt", "indexOf", "slice"];
        var originals = {};
        for (var m = 0; m < methods.length; m++) {
            var method = methods[m];
            originals[method] = String.prototype[method];
            String.prototype["counted_" + method] = (function (original) {
                return function () { work++; return original.apply(this, arguments); };
            })(originals[method]);
        }
        var arraySlice = Array.prototype.slice;
        Array.prototype.counted_slice = function () { work++; return arraySlice.apply(this, arguments); };
        var measured = loadLibrary("Markdown.js", {});
        for (var k = 0; k < names.length; k++) {
            var name = names[k];
            var a = inputs[name](small);
            work = 0;
            if (typeof gc === "function")
                gc();
            var t0 = Date.now();
            measured.blocks(a, dir, "#181825", "#c0caf5");
            var t1 = Date.now();
            var workA = work;
            var b = inputs[name](large);
            work = 0;
            if (typeof gc === "function")
                gc();
            var t2 = Date.now();
            measured.blocks(b, dir, "#181825", "#c0caf5");
            var t3 = Date.now();
            var msA = t1 - t0;
            var msB = t3 - t2;
            console.log("WORK " + name + " " + workA + " " + work + " " + msA + " " + msB);
        }
        for (var restore = 0; restore < methods.length; restore++)
            delete String.prototype["counted_" + methods[restore]];
        delete Array.prototype.counted_slice;
        Qt.quit();
    }
}
