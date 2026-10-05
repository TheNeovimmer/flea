import QtQuick
import QtQml
import "../ui/js/Markdown.js" as Markdown
import "markdown-work.js" as Work

// Count string operations in Markdown.blocks at two sizes; durations are diagnostic only.
QtObject {
    id: gate
    property var workerInputs: [
        { source: "- parent\n    [img]: pic.png\n\n![x][img]\n\n- see[^a]\n\n[^a]: Note.", dir: "/doc" },
        { source: "> ```\n> code\n\n[img]: pic.png\n\n![x][img]", dir: "/doc" },
        { source: "- parent\n```\n[img]: pic.png\n```\n\n![x][img]", dir: "/doc" },
        { source: "> - parent\n>\n>     [img]: pic.png\n\n![x][img]", dir: "/doc" },
        { source: "> > [img]: pic.png\n\n![x][img]", dir: "/doc" },
        { source: "- > ```\n  > [img]: pic.png\n  > ```\n\n![x][img]", dir: "/doc" },
        { source: "10. parent\n\n\t[img]: pic.png\n\n![x][img]", dir: "/doc" },
        { source: "> - ```\n>   code\n> - [img]: pic.png\n\n![x][img]", dir: "/doc" },
        { source: "![x](pic.png)", dir: "" },
        { source: "Title\n===\n[img]: pic.png\n\n![x][img]", dir: "/doc" },
        { source: "Title\n-\n[img]: pic.png\n\n![x][img]", dir: "/doc" },
        { source: "> Title\n===", dir: "/doc" },
        { source: "> \t> [img]: pic.png\n\n![x][img]", dir: "/doc" },
        { source: "> \t- [img]: pic.png\n\n![x][img]", dir: "/doc" },
        { source: "> -\t-\t-\n> [img]: pic.png\n\n![x][img]", dir: "/doc" },
        { source: "[img]: <pic.png\n\n![x][img]", dir: "/doc" },
        { source: "[img]: [cover].png\n\n![x][img]", dir: "/doc" },
        { source: "5. [img]: pic.png\n6. next", dir: "/doc" },
        { source: "1.\n2. shown", dir: "/doc" },
        { source: "- [img]:\npic.png\n  visible", dir: "/doc" },
        { source: "[^a]: first\n    second  \n    third\n\nsee[^a]", dir: "/doc" },
        { source: "```foo``` is inline code\nfollowing prose", dir: "/doc" },
        { source: "a < b > c\nI <3 you > them", dir: "/doc" },
        { source: "![x](caf%C3%A9.png)\n\n![x](file:///doc/100%25.png)\n\n![x](file:///doc/%2541.png)", dir: "/doc" },
        { source: "![x](foo&#65583;bar.png)", dir: "/doc" },
        { source: '<img src="pic.png"><span title="\uE0020\uE003">tail</span>', dir: "/doc" },
        { source: "before <svg/> rest\n\nbefore <svg><svg/></svg> tail", dir: "/doc" },
        { source: 'before <svg a=b/>hidden</svg> tail\n\nbefore <svg><svg a=b/>hidden</svg>hidden</svg> tail', dir: "/doc" },
        { source: '<svg a=b\u00A0/>hidden</svg> tail\n\n<svg\u2003a=b/>hidden</svg> tail\n\n<svg ==/>hidden</svg> tail\n\n<svg =a/>hidden</svg> tail', dir: "/doc" }, { source: "- ```\n  ![x](http://h/a.png)\n  <img src=\"http://h/b.png\">\n  ```\n\n> ```\n> ![x](http://h/c.png)\n> ```\n\n- a\n  - ```\n    ![x](http://h/d.png)\n    ```", dir: "/doc" }, { source: "[Foo\n  bar]: pic.png '\nt\nu\n'\n\n![x][foo bar]\n\n[a](\n/u)", dir: "/doc" }, { source: "> [a]: /u\n\ntail", dir: "/doc" }, { source: "> [a]: /u\n> [b]: /v\n\n- > [c]: /w", dir: "/doc" }, { source: "[a]: <x\\\ny>\n\n[b](<x\\\ny>)", dir: "/doc" }
    ]
    property int workerReplies: 0
    readonly property int workerDeadlineMs: 10000
    property WorkerScript workerProbe: WorkerScript {
        source: "../ui/MarkdownWorker.js"
        onMessage: function (message) {
            var input = gate.workerInputs[message.seq]
            var expected = Markdown.blocks(input.source, input.dir, "#181825", "#c0caf5")
            if (message.error !== "" || JSON.stringify(message.blocks) !== JSON.stringify(expected)) {
                console.log("FAIL worker parser differs from QML imports: " + message.error)
                Qt.exit(1)
                return
            }
            gate.workerReplies++
            if (gate.workerReplies === gate.workerInputs.length) {
                console.log("ok worker matches QML imports for " + gate.workerReplies + " inputs")
                gate.runMeasurements()
            }
        }
    }
    property Timer workerWatchdog: Timer {
        interval: gate.workerDeadlineMs
        running: gate.workerReplies < gate.workerInputs.length
        onTriggered: {
            console.log("FAIL worker parser never answered")
            Qt.exit(1)
        }
    }
    Component.onCompleted: {
        for (var i = 0; i < workerInputs.length; i++) {
            var input = workerInputs[i]
            workerProbe.sendMessage({ seq: i, source: input.source, dir: input.dir,
                chrome: "#181825", ink: "#c0caf5" })
        }
    }

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
        // The product's own dropParse, parseNow, rememberScroll and restoreScroll bodies, bound to each stub root; the list is an empty stub.
        const drop = new Function('root', body('function dropParse()'));
        const landing = new Function('root', 'Markdown', 'text', 'dir', 'chrome', 'ink', body('function parseNow('));
        const restore = new Function('root', 'body', body('function restoreScroll()'));
        const remember = new Function('root', 'body', body('function rememberScroll()'));
        const list = { originY: 0, topMargin: 0, bottomMargin: 0, contentHeight: 0, height: 0, contentY: 0 };
        function wired(r) {
            r.dropParse = () => drop(r);
            r.pointFile = () => {}; // quicklook-firstframe judges the pointing, the path handler only needs it callable
            r.parseNow = (text, dir, chrome, ink) => landing(r, Markdown, text, dir, chrome, ink);
            r.restoreScroll = () => restore(r, list);
            r.rememberScroll = () => remember(r, list);
            return r;
        }
        // The fallback timer's handler, searched from its own id so an earlier Timer's handler is never the one found.
        const fallback = new Function('root', 'Markdown', body('onTriggered:', source.slice(source.indexOf('id: parseFallback'))));
        let failures = 0;
        function check(ok, name) {
            console.log((ok ? 'ok ' : 'FAIL ') + name);
            if (!ok)
                failures++;
        }
        root = wired({ active: true, tooLarge: false, parseSeq: 5, parsing: true, blockList: [], path: '/doc/B.md' });
        file = { loaded: false, text: () => root.rawText };
        root.askParse = () => ask(root, file, Markdown, parseFallback, parserLoader);
        new Function('root', 'reloadCoalesce', body('    onPathChanged: {'))(root, { stop() {} });
        reply(root, { seq: 5, blocks: ['A'], error: '' });
        check(root.blockList.length === 0, 'F11 unloaded B rejects A worker reply');
        root = wired({ parseSeq: 5, parsing: true, askedText: 'B', askedDir: '/doc', path: '/doc/B.md', blockList: [] });
        fallback(root, Markdown);
        reply(root, { seq: 5, blocks: ['late'], error: '' });
        check(root.blockList[0] === 'fallback', 'F10 fallback rejects late worker reply');
        root = wired({ active: true, tooLarge: false, parseSeq: 5, rawText: 'small', workerThreshold: 65536,
            path: '/doc/small.md', blockList: [] });
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
        const htmlSource = readSource('../ui/js/MdHtml.js');
        check(htmlSource.indexOf('.import "MdEscape.js" as MdEscape') >= 0
            && htmlSource.indexOf('function escapeHtmlText(') < 0, 'R2 HTML reuses dependency-free escapeText');
        const validator = readSource('markdown-linearity.sh');
        check(validator.indexOf("| awk") < 0 && validator.indexOf('while read -r name') >= 0,
            'R2 validator uses a plain Bash read loop');
        const security = readSource('markdown-security.qml');
        const control = { text: "" };
        const imageStatus = { Loading: Image.Loading, Ready: Image.Ready, Error: Image.Error };
        const pending = { children: [], source: "http://stub/delayed.png",
            status: imageStatus.Loading, asynchronous: true };
        const corpus = { children: [pending] };
        const settled = security.indexOf('function imagesSettled(') < 0 ? () => true
            : new Function('Image', 'return function imagesSettled(item) {'
                + body('function imagesSettled(', security) + '}')(imageStatus);
        const drain = new Function('started', 'md', 'fixture', 'Url', 'Html', 'Resolve',
            'validationFailures', 'log', 'Qt', 'control', 'counter', 'XMLHttpRequest', 'root',
            'imagesSettled', 'resourceUrls', 'resourceProbes', 'finishDrain',
            'referenceResolution', 'expectedReferences', 'fail', 'Blocks', 'HtmlSecurity',
            body('function startDrain()', security));
        function tryDrain() {
            drain(false, { contentReady: true, blockList: ['corpus'] }, '/doc/a.md',
                { dirOf: () => '/doc', classifyImage: () => ({ kind: 'dropped' }) },
                { sanitizeTag: () => ({ emit: '' }) }, { resolvePair: () => '' }, [], () => {},
                { callLater: callback => callback() }, control, 'http://stub',
                function () {
                    this.open = () => {};
                    this.send = () => {};
                }, corpus, settled,
                () => {}, { model: [] }, () => { control.text = 'control'; },
                () => ({ total: 0, resolved: 0 }), 0, () => { control.text = 'failed'; }, { blocks: () => [] }, { failures: () => [] });
        }
        tryDrain();
        check(control.text === '', 'R2 control waits for every Loading corpus Image');
        pending.status = imageStatus.Error;
        tryDrain();
        check(control.text !== '', 'R2 Error corpus Image releases control');
        return failures === 0;
    }

    // Sample input: .import "MdLeaf.js" as Leaf, followed by function blocks(...).
    function loadLibrary(name, cache, mutant) {
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
                aliases.push(alias);
                dependencies.push(loadLibrary(file, cache, mutant));
                return "";
            });
        if (mutant === true && name === "MdHtml.js")
            code = code.replace(/    if \(dead !== undefined && dead !== null && i < dead.tagDead\)\n        return null\n/, "");
        if (mutant === "suffix" && name === "MdBlocks.js")
            code = code.replace("function blocks(source, dir, chrome, ink) {",
                "function blocks(source, dir, chrome, ink) {\n"
                + "    var suffixSink = 0;\n"
                + "    for (var i = 0; i < source.length; i++) {\n"
                + "        suffixSink += source.substring(i).lastIndexOf('z');\n"
                + "    }\n"
                + "    if (suffixSink > 0) throw new Error('suffix sink');\n");
        code = Work.instrument(code, aliases, name);
        if (name === "MdRun.js")
            code += "\ncountFrameStep = function () { String.prototype.counted_charAt.call('x', 0); };\n";
        var names = [], declaration = /^(?:function|var)\s+(\w+)/gm, match;
        while ((match = declaration.exec(code)) !== null) names.push(match[1]);
        var fields = names.map(function (key) { return key + ":" + key; });
        var build = Function.apply(null, aliases.concat([code + "\nreturn {" + fields.join(",") + "};"]));
        var values = build.apply(null, dependencies);
        for (var key in values) exports[key] = values[key];
        return exports;
    }

    function coverageChecks() {
        var coverageName = "MdCoverageProbe.js";
        var firstSourceLine = 1;
        var blockRegexLine = 2;
        var commentRegexLine = 3;
        var lexicalError = " in parser coverage " + coverageName + ":";
        var braceError = "unsupported slash after closing brace in parser coverage " + coverageName + ":";
        var probes = [
            { name: "plain", source: "source.untrackedScan()" },
            { name: "regex quote", source: '(/[\"]/, source.untrackedScan("payload"))' },
            { name: "regex line comment", source: "(/[//]/, source.untrackedScan())" },
            { name: "regex block comment", source: "(/[/*]/, source.untrackedScan()) /* closed */" },
            { name: "division after call", source: "source.slice(0) / source.untrackedScan() / divisor" },
            { name: "division after number", source: "10 / source.untrackedScan() / divisor" },
            { name: "division after identifier", source: "count / source.untrackedScan() / divisor" },
            { name: "increment after line break", source: 'i\n++ /"/.test(z)',
                error: "unsupported increment or decrement after line break" + lexicalError + blockRegexLine },
            { name: "decrement after line break", source: 'i\n-- /"/.test(z)',
                error: "unsupported increment or decrement after line break" + lexicalError + blockRegexLine },
            { name: "increment after CR", source: 'i\r++ /"/.test(z)',
                error: "unsupported increment or decrement after line break" + lexicalError + blockRegexLine },
            { name: "increment after CRLF", source: 'i\r\n++ /"/.test(z)',
                error: "unsupported increment or decrement after line break" + lexicalError + blockRegexLine },
            { name: "increment after line separator", source: 'i\u2028++ /"/.test(z)',
                error: "unsupported increment or decrement after line break" + lexicalError + blockRegexLine },
            { name: "decrement after paragraph separator", source: 'i\u2029-- /"/.test(z)',
                error: "unsupported increment or decrement after line break" + lexicalError + blockRegexLine },
            { name: "increment after multiline comment", source: 'i /* comment\n*/ ++ /"/.test(z)',
                error: "unsupported increment or decrement after line break" + lexicalError + blockRegexLine },
            { name: "increment after line comment", source: 'i // comment\n++ /"/.test(z)',
                error: "unsupported increment or decrement after line break" + lexicalError + blockRegexLine },
            { name: "increment after CR line comment", source: 'i // comment\r++ /"/.test(z)',
                error: "unsupported increment or decrement after line break" + lexicalError + blockRegexLine },
            { name: "increment after line separator comment", source: 'i // comment\u2028++ /"/.test(z)',
                error: "unsupported increment or decrement after line break" + lexicalError + blockRegexLine },
            { name: "decrement after paragraph separator comment", source: 'i // comment\u2029-- /"/.test(z)',
                error: "unsupported increment or decrement after line break" + lexicalError + blockRegexLine },
            { name: "decrement after newline then comment", source: 'i\n/* comment */ -- /"/.test(z)',
                error: "unsupported increment or decrement after line break" + lexicalError + blockRegexLine },
            { name: "regex quote after block", source: 'if (ready) {}\n/[\"]/.test(source); source.untrackedScan("payload")',
                error: braceError + blockRegexLine },
            { name: "regex line comment after block", source: "if (ready) {}\n/[//]/.test(source); source.untrackedScan()",
                error: braceError + blockRegexLine },
            { name: "regex after block comments", source: "if (ready) {} /* comment\n*/ // comment\n/[//]/.test(source)",
                error: braceError + commentRegexLine },
            { name: "division after object", source: "var ratio = {} / divisor", error: braceError + firstSourceLine },
            { name: "line comment after block", source: "if (ready) {} // comment\nsource.untrackedScan()" },
            { name: "block comment after block", source: "if (ready) {} /* comment */ source.untrackedScan()" },
            { name: "keyword property", source: "source.return / source.untrackedScan() / divisor" },
            { name: "keyword property call", source: "Leaf.if(ready) / source.untrackedScan() / divisor", aliases: ["Leaf"] },
            { name: "spread operator", source: "fn(.../[//]/.source); source.untrackedScan()" },
            { name: "extends keyword", source: "class Child extends /[//]/.constructor {} source.untrackedScan()" },
            { name: "default keyword", source: "export default /[//]/; source.untrackedScan()" },
            { name: "break statement", source: "while (ready) { break\n/[//]/.test(source); source.untrackedScan() }",
                error: "unsupported slash after break" + lexicalError + blockRegexLine },
            { name: "labelled break", source: "outer: while (ready) { break outer\n/[//]/.test(source); source.untrackedScan() }",
                error: "unsupported slash after break" + lexicalError + blockRegexLine },
            { name: "continue statement", source: "while (ready) { continue\n/[//]/.test(source); source.untrackedScan() }",
                error: "unsupported slash after continue" + lexicalError + blockRegexLine },
            { name: "debugger statement", source: "debugger\n/[//]/.test(source); source.untrackedScan()",
                error: "unsupported slash after debugger" + lexicalError + blockRegexLine },
            { name: "await identifier", source: "await / source.untrackedScan() / divisor",
                error: "unsupported contextual keyword await" + lexicalError + firstSourceLine },
            { name: "yield identifier", source: "yield / source.untrackedScan() / divisor",
                error: "unsupported contextual keyword yield" + lexicalError + firstSourceLine },
            { name: "for await head", source: 'for await (x of y) /"/.test(z)',
                error: "unsupported contextual keyword await" + lexicalError + firstSourceLine },
            { name: "plain await", source: "\nawait",
                error: "unsupported contextual keyword await" + lexicalError + blockRegexLine },
            { name: "async function", source: "\nasync function parse() {}",
                error: "unsupported contextual keyword async" + lexicalError + blockRegexLine },
            { name: "plain yield", source: "\nyield",
                error: "unsupported contextual keyword yield" + lexicalError + blockRegexLine },
            { name: "await after CR line comment", source: "// comment\rawait",
                error: "unsupported contextual keyword await" + lexicalError + blockRegexLine },
            { name: "async after line separator comment", source: "// comment\u2028async",
                error: "unsupported contextual keyword async" + lexicalError + blockRegexLine },
            { name: "yield after paragraph separator comment", source: "// comment\u2029yield",
                error: "unsupported contextual keyword yield" + lexicalError + blockRegexLine },
            { name: "await property division", source: "obj.await / source.untrackedScan() / divisor" },
            { name: "of keyword", source: "for (var part of /[//]/.source) source.untrackedScan()",
                error: "unsupported slash after contextual keyword of" + lexicalError + firstSourceLine },
            { name: "Unicode identifier", source: "caf\u00e9 / source.untrackedScan() / divisor",
                error: "unsupported token" + lexicalError + firstSourceLine },
            { name: "escaped identifier", source: "caf\\u00e9 / source.untrackedScan() / divisor",
                error: "unsupported token" + lexicalError + firstSourceLine },
            { name: "template literal", source: "`source.untrackedScan()`",
                error: "unsupported template literal" + lexicalError + firstSourceLine },
            { name: "division after bracket", source: "source[0] / source.untrackedScan() / divisor" },
            { name: "division after postfix", source: "count++ / source.untrackedScan() / divisor" }
        ];
        var failures = 0;
        for (var p = 0; p < probes.length; p++) {
            var refused = false;
            try {
                Work.checkMethods(probes[p].source, probes[p].aliases || [], coverageName);
            } catch (error) {
                var expected = probes[p].error || "uncounted parser method " + coverageName + ": untrackedScan";
                refused = String(error) === "Error: " + expected;
            }
            console.log((refused ? "ok " : "FAIL ") + "coverage " + probes[p].name + " refuses unsafe scan");
            if (!refused)
                failures++;
        }
        try {
            Work.checkMethods('(/["/\\\\]\\.untrackedScan\\(\\)/).test(source)', [], "regex body probe");
            Work.checkMethods('if (ready) /[//]\\.untrackedScan\\(\\)/.test(source)', [], "control regex probe");
            Work.checkMethods('return /[/*]\\.untrackedScan\\(\\)/.test(source)', [], "return regex probe");
            Work.checkMethods('"source.untrackedScan()" /* source.untrackedScan() */', [], "literal probe");
            Work.checkMethods('if (ready) {} // source.untrackedScan()\nsource.slice(0)', [], "block line comment probe");
            Work.checkMethods('if (ready) {} /* source.untrackedScan() */ source.slice(0)', [], "block comment probe");
            Work.checkMethods('source.slice(0) / divisor; count / divisor', [], "division probe");
            Work.checkMethods('(count) / divisor; source[0] / divisor; count++ / divisor; count-- / divisor', [], "operand probe");
            Work.checkMethods('source.return / divisor; Leaf.if(ready) / divisor', ["Leaf"], "keyword property probe");
            Work.checkMethods('obj.await / divisor', [], "await property probe");
            Work.checkMethods('obj.async / divisor', [], "async property probe");
            Work.checkMethods('obj.yield / divisor', [], "yield property probe");
            Work.checkMethods('awaitable + asyncWork + yielded', [], "contextual keyword prefix probe");
            Work.checkMethods('"await async yield" /* await async yield */', [], "contextual keyword literal probe");
            var postfixDivision = "i++ / 2";
            if (Work.stripLiterals(postfixDivision, coverageName) !== postfixDivision)
                throw new Error("postfix division was stripped");
            console.log("ok coverage i++ / 2 scans as division");
            console.log("ok coverage ignores methods inside literals and comments");
        } catch (error) {
            console.log("FAIL coverage literal contents: " + error);
            failures++;
        }
        return failures === 0;
    }

    function runMeasurements() {
        if (!coverageChecks()) {
            Qt.exit(1);
            return;
        }
        try {
            var coverage = Work.checkFiles(Qt.application.arguments, readSource);
            console.log("ok static method coverage for " + coverage + " parser files, unknown method refused");
        } catch (error) {
            console.log("FAIL " + error);
            Qt.exit(1);
            return;
        }
        if (!callbackChecks()) {
            Qt.exit(1);
            return;
        }
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
            tagCost: function (n) {
                var unit = "<b>x</b>";
                return unit.repeat(Math.floor(n / unit.length));
            },
            tagAttrs: function (n) {
                var unit = '<svg a=b/>hidden</svg><svg><svg a=b/>hidden</svg>hidden</svg><b title="b"/>x</b>'
                    + '<svg a=b\u00A0/>hidden</svg><svg a=b\u000B/>hidden</svg><svg a=b\u2003/>hidden</svg><svg a=b\uFEFF/>hidden</svg>'
                    + '<svg\u00A0a=b/>hidden</svg><svg\u000Ba=b/>hidden</svg><svg\u2003a=b/>hidden</svg><svg\uFEFFa=b/>hidden</svg>'
                    + '<svg ==/>hidden</svg><svg =a/>hidden</svg><svg a=b\t/>kept</svg>';
                return unit.repeat(Math.floor(n / unit.length));
            },
            linkFrames: function (n) {
                var opener = "![";
                var link = "[x](https://x)";
                var count = Math.floor(n / (opener.length + link.length));
                return opener.repeat(count) + link.repeat(count);
            },
            blankList: function (n) {
                var half = Math.floor(n / 2);
                return "- parent\n" + "\n".repeat(half) + "- " + "x".repeat(half);
            },
            blankIndent: function (n) {
                var half = Math.floor(n / 2);
                return "- parent\n" + "\n".repeat(half) + " ".repeat(half) + "x";
            },
            spaceFlood: function (n) {
                var unit = "&#32;";
                return "x" + unit.repeat(Math.floor(n / unit.length)) + "y";
            },
            spaceAlternate: function (n) {
                var unit = "&#32; ";
                return unit.repeat(Math.floor(n / unit.length)) + "y";
            },
            spaceTrail: function (n) {
                var unit = " &#32;";
                return "x" + unit.repeat(Math.floor(n / unit.length)) + "\ny";
            },
            spaceIndent: function (n) {
                var longIndent = 10;
                var unit = "\n" + " ".repeat(longIndent) + "&#32;";
                return "a" + unit.repeat(Math.floor(n / unit.length)) + "\nb";
            },
            punctTail: function (n) {
                var url = "https://example.com/x";
                var tailLength = n - url.length;
                var tailParts = 2;
                var parenLength = Math.floor(tailLength / tailParts);
                return url + ")".repeat(parenLength) + ".".repeat(tailLength - parenLength);
            },
            // Many HTML blocks, each a badge row with a remote picture, a table cell picture and a heading.
            htmlBlocks: function (n) {
                var unit = '<p align="center">\n<a href="https://x.example/a"><img src="img/a.png" alt="a"></a>\n'
                    + '<img src="img/b.png" width="40">\n<img src="https://x.example/c.png">\n</p>\n\n'
                    + '<table><tr><td><img src="img/d.png"></td></tr></table>\n\n<h2 align="center">T</h2>\n\n';
                return unit.repeat(Math.floor(n / unit.length));
            },
            // One HTML block of many lines, each line holding images and a break.
            htmlLines: function (n) {
                var line = '<a href="https://x.example/a"><img src="img/a.png"></a><img src="img/b.png"><br>\n';
                return '<div align="center">\n' + line.repeat(Math.floor(n / line.length)) + '</div>';
            },
            // One line of one HTML block holding many linked images.
            htmlRow: function (n) {
                var badge = '<a href="https://x.example/a"><img src="img/a.png"></a>';
                return '<p align="center">' + badge.repeat(Math.floor(n / badge.length)) + '</p>';
            },
            // Many image wrappers nested in one another, each opener with its own image and the closers at the end.
            htmlNested: function (n) {
                var open = '<div align="center">\n<img src="img/a.png">\n';
                var close = "</div>\n";
                var depth = Math.floor(n / (open.length + close.length));
                return open.repeat(depth) + close.repeat(depth);
            },
            backtickRun: function (n) {
                var s = "";
                while (s.length < n)
                    s += "`a`b";
                return s.slice(0, n);
            },
            // Every item holds a fence, so each parses its own parts.
            fenceItems: function (n) {
                var s = "";
                while (s.length < n)
                    s += "- item\n  ```js\n  var a = 1;\n  ```\n";
                return s.slice(0, n);
            },
            // Quotes, items and fences alternate to the nesting limit and past it, so each level reads its lines again.
            nestMixed: function (n) {
                var head = "";
                for (var d = 0; d < 24; d++)
                    head += d % 2 === 0 ? "> " : "- ";
                var s = "";
                while (s.length < n)
                    s += head + "```\n" + head + "code\n" + head + "```\n";
                return s.slice(0, n);
            }
        };
        var names = ["codeDense", "codeOnly", "bangOpen", "bracketOpen", "angleOpen",
            "delimSoup", "quoteDeep", "listDeep", "backtickRun", "tagCost", "tagAttrs", "linkFrames", "blankList", "blankIndent", "spaceFlood", "spaceAlternate", "spaceTrail", "spaceIndent", "punctTail",
            "htmlBlocks", "htmlLines", "htmlRow", "htmlNested", "fenceItems", "nestMixed"];
        Work.install();
        Work.work = 0;
        var uppercaseInput = "Note";
        var uppercaseCode = Work.instrument("return source.toUpperCase()", [], "uppercase probe");
        var uppercaseResult = new Function("source", uppercaseCode)(uppercaseInput);
        if (uppercaseResult !== "NOTE" || Work.work !== uppercaseInput.length) {
            console.log("FAIL toUpperCase work=" + Work.work);
            Qt.exit(1);
            return;
        }
        console.log("ok toUpperCase counted work=" + Work.work);
        var sizeRatio = 8;
        var marginNumerator = 3;
        var marginDenominator = 2;
        var workLimit = sizeRatio * marginNumerator / marginDenominator;
        var mutantSmall = 2048;
        var mutantLarge = mutantSmall * sizeRatio;
        var mutant = loadLibrary("Markdown.js", {}, true);
        Work.work = 0;
        var mutantUnit = "< ";
        mutant.blocks(mutantUnit.repeat(mutantSmall / mutantUnit.length), dir, "#181825", "#c0caf5");
        var mutantA = Work.work;
        Work.work = 0;
        mutant.blocks(mutantUnit.repeat(mutantLarge / mutantUnit.length), dir, "#181825", "#c0caf5");
        if (Work.work <= mutantA * workLimit) {
            console.log("FAIL dead-tag mutant accepted work=" + mutantA + "/" + Work.work);
            Qt.exit(1);
            return;
        }
        console.log("ok dead-tag mutant rejected work=" + mutantA + "/" + Work.work);
        var suffixMutant = loadLibrary("Markdown.js", {}, "suffix");
        Work.work = 0;
        suffixMutant.blocks("x".repeat(mutantSmall), dir, "#181825", "#c0caf5");
        var suffixA = Work.work;
        Work.work = 0;
        suffixMutant.blocks("x".repeat(mutantLarge), dir, "#181825", "#c0caf5");
        if (Work.work <= suffixA * workLimit) {
            console.log("FAIL suffix-scan mutant accepted work=" + suffixA + "/" + Work.work);
            Qt.exit(1);
            return;
        }
        console.log("ok suffix-scan mutant rejected work=" + suffixA + "/" + Work.work);
        var measured = loadLibrary("Markdown.js", {});
        var frameSmall = 20000;
        var frameLarge = 160000;
        var tagSmall = 4095;
        var tagLarge = 32760;
        for (var k = 0; k < names.length; k++) {
            var name = names[k];
            var a = inputs[name](name === "linkFrames" ? frameSmall : name === "tagCost" ? tagSmall : small);
            Work.work = 0;
            if (typeof gc === "function")
                gc();
            var t0 = Date.now();
            measured.blocks(a, dir, "#181825", "#c0caf5");
            var t1 = Date.now();
            var workA = Work.work;
            var b = inputs[name](name === "linkFrames" ? frameLarge : name === "tagCost" ? tagLarge : large);
            Work.work = 0;
            if (typeof gc === "function")
                gc();
            var t2 = Date.now();
            measured.blocks(b, dir, "#181825", "#c0caf5");
            var t3 = Date.now();
            var msA = t1 - t0;
            var msB = t3 - t2;
            console.log("WORK " + name + " " + workA + " " + Work.work + " " + msA + " " + msB);
        }
        Work.uninstall();
        Qt.quit();
    }
}
