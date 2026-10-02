import QtQuick
import QtQml
import "../ui/js/Markdown.js" as Markdown

// Times Markdown.blocks over pathological inputs at two sizes in Qt's own JS
// engine. Prints one TIMES line per input: name smallMs largeMs ratio.
QtObject {
    Component.onCompleted: {
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
        for (var k = 0; k < names.length; k++) {
            var name = names[k];
            var a = inputs[name](small);
            var t0 = Date.now();
            Markdown.blocks(a, dir, "#181825", "#c0caf5");
            var t1 = Date.now();
            var b = inputs[name](large);
            var t2 = Date.now();
            Markdown.blocks(b, dir, "#181825", "#c0caf5");
            var t3 = Date.now();
            var msA = t1 - t0;
            var msB = t3 - t2;
            var ratio = msA === 0 ? (msB === 0 ? 1 : 99) : msB / msA;
            console.log("TIMES " + name + " " + msA + " " + msB + " " + ratio.toFixed(2));
        }
        // The 1 MiB report figure: dense code spans, the reviewer's worst case.
        var mega = inputs.codeOnly(1048576);
        var m0 = Date.now();
        Markdown.blocks(mega, dir, "#181825", "#c0caf5");
        console.log("TIMES codeOnly1M -1 " + (Date.now() - m0) + " -");
        Qt.quit();
    }
}
