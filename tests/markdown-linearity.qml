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
        { source: '<svg a=b\u00A0/>hidden</svg> tail\n\n<svg\u2003a=b/>hidden</svg> tail\n\n<svg ==/>hidden</svg> tail\n\n<svg =a/>hidden</svg> tail', dir: "/doc" }
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
        // Sample input: onMessage: function (messageObject) { if (...) return; ... }
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
        const parseFallback = { restart() {} };
        const parser = { sendMessage() {} };
        const ask = new Function('root', 'file', 'Markdown', 'parseFallback', 'parser', body('function askParse()'));
        const reply = new Function('root', 'messageObject', body('onMessage: function'));
        const fallbackHandler = 'onTriggered:';
        const fallbackMarker = source.indexOf(fallbackHandler, source.indexOf('id: parseFallback'));
        const fallback = new Function('root', 'Markdown', body(source.slice(fallbackMarker, fallbackMarker + fallbackHandler.length)));
        let failures = 0;
        function check(ok, name) {
            console.log((ok ? 'ok ' : 'FAIL ') + name);
            if (!ok)
                failures++;
        }
        root = { active: true, tooLarge: false, parseSeq: 5, parsing: true, blockList: [], path: '/doc/B.md' };
        file = { loaded: false };
        root.askParse = () => ask(root, file, Markdown, parseFallback, parser);
        new Function('root', body('    onPathChanged: {'))(root);
        reply(root, { seq: 5, blocks: ['A'], error: '' });
        check(root.blockList.length === 0, 'F11 unloaded B rejects A worker reply');
        root = { parseSeq: 5, parsing: true, rawText: 'B', path: '/doc/B.md', blockList: [] };
        fallback(root, Markdown);
        reply(root, { seq: 5, blocks: ['late'], error: '' });
        check(root.blockList[0] === 'fallback', 'F10 fallback rejects late worker reply');
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
                () => {}, { model: [] }, () => { control.text = 'control'; });
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

    function runMeasurements() {
        try {
            var coverage = Work.checkFiles(Qt.application.arguments, readSource);
            var refused = false;
            try {
                Work.checkMethods("source.untrackedScan()", [], "coverage probe");
            } catch (error) {
                refused = String(error).indexOf("uncounted parser method") >= 0;
            }
            if (!refused)
                throw new Error("untracked parser method accepted");
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
            backtickRun: function (n) {
                var s = "";
                while (s.length < n)
                    s += "`a`b";
                return s.slice(0, n);
            }
        };
        var names = ["codeDense", "codeOnly", "bangOpen", "bracketOpen", "angleOpen",
            "delimSoup", "quoteDeep", "listDeep", "backtickRun", "tagCost", "tagAttrs", "linkFrames", "blankList", "blankIndent"];
        Work.install();
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
