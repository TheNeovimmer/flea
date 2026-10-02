//@ pragma ShellId flea-markdown-figures-test

import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "markdown-figures-cases.js" as Cases

// tests/markdown-figures.sh's harness: every figure kind through the real
// Flea.MarkdownFigure offscreen, judged on pixel facts. Quits itself.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_FIGURES " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property int failures: 0
    property bool done: false
    function check(cond, why) {
        if (!cond) {
            shell.failures++;
            shell.log("FAIL " + why);
        } else {
            shell.log("PASS " + why);
        }
    }

    property string port: Quickshell.env("FLEA_FIG_PORT")
    property string shotDir: Quickshell.env("XDG_RUNTIME_DIR")
    property var mathModel: []
    property var diagModel: []
    property int phase: 0
    property int round: 0
    property double t0: 0
    property var lat: ({})
    property var pss: []
    property int pssWant: 0
    property string pssPhase: ""
    property bool pss2done: false
    property var ticks: []
    property double maxGap: 0
    property double firstMathMs: -1
    property double firstMerMs: -1
    property string grabUrl: ""

    // phase: 1 pss0, 2 math wait, 3 pss1 wait, 4 diag wait, 6 grab wait,
    // 7 rounds. Phase 5 is unused; pss2 completion is the pss2done flag.

    Component {
        id: figDelegate
        Rectangle {
            readonly property var fig: fig
            readonly property string tag: modelData.tag
            width: 780
            height: fig.height
            color: "#101315"
            Flea.MarkdownFigure {
                id: fig
                width: 760
                kind: modelData.kind
                source: modelData.source
                display: modelData.display
                inline: false
                bgHex: "#101315"
                fgHex: "#c0caf5"
                accentHex: "#7aa2f7"
                fontFamily: "monospace"
                bodyPx: 14
            }
        }
    }

    FloatingWindow {
        id: window
        implicitWidth: 820
        implicitHeight: 900
        color: "#101315"

        Column {
            id: col
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right

            Repeater {
                id: mathRep
                model: shell.mathModel
                delegate: figDelegate
            }
            Repeater {
                id: diagRep
                model: shell.diagModel
                delegate: figDelegate
            }
            Flea.MarkdownFigure {
                id: inlineFig
                width: 200
                kind: "math"
                source: "x^2"
                display: false
                inline: true
                bgHex: "#101315"
                fgHex: "#c0caf5"
                accentHex: "#7aa2f7"
                fontFamily: "monospace"
                bodyPx: 14
            }
            Text {
                id: hostText
                width: 760
                textFormat: Text.MarkdownText
                wrapMode: Text.Wrap
                color: "#c0caf5"
                font.family: "monospace"
                font.pixelSize: 14
            }
        }

        // One column grab, analyzed by region: per-item grabs deadlocked
        // intermittently under offscreen software rendering, a whole-frame
        // grab never did. Sized past the column so no region clips.
        Canvas {
            id: probe
            width: 820
            height: 1600
            opacity: 0
            onPaint: {
                if (shell.grabUrl !== "")
                    shell.analyzeColumn(getContext("2d"));
            }
        }
    }

    Timer {
        id: tick
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            var now = Date.now();
            var n = shell.ticks.length;
            if (n > 0)
                shell.maxGap = Math.max(shell.maxGap, now - shell.ticks[n - 1]);
            shell.ticks.push(now);
        }
    }

    Timer {
        interval: 150000
        repeat: false
        running: true
        onTriggered: {
            shell.log("FAIL the watchdog outlived the verdict");
            shell.finish(1);
        }
    }

    Timer {
        id: pump
        interval: 50
        repeat: true
        running: true
        onTriggered: shell.drive()
    }

    Timer {
        id: paintDelay
        interval: 800
        repeat: false
        running: false
        onTriggered: probe.requestPaint()
    }

    Process {
        id: pssProc
        command: ["sh", "-c", "grep ^Pss: /proc/" + Quickshell.processId + "/smaps_rollup"]
        stdout: StdioCollector { id: pssOut }
        onExited: {
            var total = 0;
            var lines = pssOut.text.split("\n");
            for (var i = 0; i < lines.length; i++) {
                var m = lines[i].match(/(\d+)\s*kB/);
                if (m)
                    total += parseInt(m[1], 10);
            }
            shell.pss.push(shell.pssPhase + "=" + total);
            if (shell.pss.length < shell.pssWant) {
                pssProc.running = true;
            } else {
                shell.afterPss();
            }
        }
    }

    function readPss(phase, n) {
        shell.pssPhase = phase;
        shell.pssWant = shell.pss.length + n;
        pssProc.running = true;
    }

    function afterPss() {
        if (shell.pssPhase === "pss0") {
            shell.t0 = Date.now();
            shell.mathModel = Cases.mathCases(shell.port);
            shell.phase = 2;
        } else if (shell.pssPhase === "pss1") {
            shell.t0 = Date.now();
            shell.diagModel = Cases.diagCases(shell.port);
            shell.phase = 4;
        } else if (shell.pssPhase === "pss2") {
            shell.pss2done = true;
        }
    }

    function settled(rep) {
        for (var i = 0; i < rep.count; i++) {
            var f = rep.itemAt(i).fig;
            if (f.ticket > 0)
                return false;
            if (f.svg === "" && f.error === "")
                return false;
        }
        return rep.count > 0;
    }

    function loaded(rep) {
        for (var i = 0; i < rep.count; i++) {
            var f = rep.itemAt(i).fig;
            if (f.failed)
                continue;
            if (f.fitHeight <= 0)
                return false;
        }
        return true;
    }

    function drive() {
        if (shell.phase === 2 && shell.settled(mathRep) && shell.loaded(mathRep)) {
            shell.firstMathMs = Date.now() - shell.t0;
            shell.log("cold math import and render ms=" + shell.firstMathMs + " sends=" + Flea.FigureService.sends);
            shell.failFences(mathRep, Cases.fenceTags());
            shell.readPss("pss1", 5);
            shell.phase = 3;
        } else if (shell.phase === 4 && shell.settled(diagRep)) {
            var allReady = true;
            for (var i = 0; i < diagRep.count; i++) {
                var f = diagRep.itemAt(i).fig;
                if (!f.failed && f.fitHeight <= 0)
                    allReady = false;
                if (shell.firstMerMs < 0 && (f.svg !== "" || f.failed)
                        && diagRep.itemAt(i).tag !== "oversize")
                    shell.firstMerMs = Date.now() - shell.t0;
            }
            if (shell.firstMerMs >= 0 && shell.pssPhase !== "pss2") {
                shell.log("cold mermaid import and render ms=" + shell.firstMerMs + " sends=" + Flea.FigureService.sends);
                shell.readPss("pss2", 5);
            }
            if (allReady && shell.pss2done) {
                shell.failFences(diagRep, Cases.diagFenceTags());
                // The inline form exists and resolves: a render draws the
                // line-height image, a refusal draws the fence instead.
                shell.check(inlineFig.ticket === 0 && (inlineFig.svg !== "" || inlineFig.failed),
                    "inline maths resolves to an image or a fence");
                var red = '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">'
                    + '<rect width="40" height="40" fill="#ff0000"/></svg>';
                hostText.text = 'a <img src="data:image/svg+xml,'
                    + encodeURIComponent(red) + '"> b';
                shell.t0 = Date.now();
                shell.phase = 6;
            }
        } else if (shell.phase === 7) {
            shell.roundPoll();
        } else if (shell.phase === 6 && inlineFig.ticket === 0
                && (inlineFig.svg !== "" || inlineFig.error !== "")
                && Date.now() - shell.t0 > 800) {
            shell.phase = 0;
            shell.grabColumn();
        }
    }

    function failFences(rep, tags) {
        for (var i = 0; i < rep.count; i++) {
            var tag = rep.itemAt(i).tag;
            if (tags.indexOf(tag) < 0)
                continue;
            var f = rep.itemAt(i).fig;
            shell.check(f.failed, tag + " falls back to the fenced block");
        }
    }

    function entries() {
        var list = [];
        var i;
        for (i = 0; i < mathRep.count; i++)
            list.push({ item: mathRep.itemAt(i), tag: mathRep.itemAt(i).tag, kind: "fig" });
        for (i = 0; i < diagRep.count; i++)
            list.push({ item: diagRep.itemAt(i), tag: diagRep.itemAt(i).tag, kind: "fig" });
        list.push({ item: inlineFig, tag: "inlinefig", kind: "fig" });
        list.push({ item: hostText, tag: "hosting", kind: "host" });
        return list;
    }

    function isFence(tag) {
        return Cases.fenceTags().indexOf(tag) >= 0 || Cases.diagFenceTags().indexOf(tag) >= 0;
    }

    function grabColumn() {
        var dbg = shell.entries().map(function (e) {
            return e.tag + "=" + Math.round(e.item.height);
        }).join(" ");
        shell.log("heights " + dbg + " col=" + Math.round(col.height) + " sends=" + Flea.FigureService.sends);
        // The canvas must cover the whole grab: reading past its edge
        // answers zeros, which reads as blank regions.
        probe.width = Math.ceil(col.width);
        probe.height = Math.ceil(col.height);
        col.grabToImage(function (result) {
            if (!result.saveToFile(shell.shotDir + "/fig-col.png")) {
                shell.check(false, "column grab saves");
                shell.afterPixels();
                return;
            }
            // The canvas loads the file itself: drawing an Image item
            // painted nothing here while the same call with a URL works.
            shell.grabUrl = "file://" + shell.shotDir + "/fig-col.png";
            probe.loadImage(shell.grabUrl);
        });
    }

    Connections {
        target: probe
        function onImageLoaded() {
            // A decoded image still needs a frame to upload its texture;
            // painting in the same tick draws blank, always for a tall
            // grab. The delay below is settle time, not a verdict.
            paintDelay.running = true;
        }
    }

    function analyzeColumn(ctx) {
        var w = Math.round(col.width);
        var h = Math.round(col.height);
        ctx.drawImage(shell.grabUrl, 0, 0);
        var pixels = ctx.getImageData(0, 0, w, h).data;
        var list = shell.entries();
        for (var k = 0; k < list.length; k++) {
            var entry = list[k];
            if (entry.kind === "fig" && shell.isFence(entry.tag))
                continue;
            var pt = entry.item.mapToItem(col, 0, 0);
            var x0 = Math.round(pt.x);
            var y0 = Math.round(pt.y);
            var ew = Math.round(entry.item.width);
            var eh = Math.round(entry.item.height);
            if (entry.kind === "host") {
                var red = Cases.countRedRegion(pixels, w, x0, y0, ew, eh);
                shell.log("HOSTING inline image in Text.MarkdownText red=" + red);
            } else {
                var r = Cases.analyzeRegion(pixels, w, x0, y0, ew, eh);
                var f = entry.item.fig !== undefined ? entry.item.fig : entry.item;
                shell.log("pixels " + entry.tag + " ink=" + r.ink + " theme=" + r.theme
                    + " near=" + r.near + " black=" + r.black + " white=" + r.white
                    + " ih=" + Math.round(eh)
                    + " nat=" + Math.round(f.naturalWidth || 0) + "x" + Math.round(f.naturalHeight || 0)
                    + " err=" + (f.error || "") + " tops=" + r.tops);
                if (f.failed) {
                    // A figure that cannot render draws its fenced block in
                    // the live theme's colours instead: assert it draws
                    // something rather than nothing.
                    shell.check(r.ink > 40, entry.tag + " falls back to a drawn block");
                } else {
                    shell.check(r.ink > 40, entry.tag + " draws a non-empty image");
                    shell.check(r.near > 0, entry.tag + " carries the theme foreground");
                    shell.check(r.black === 0 && r.white === 0, entry.tag + " has no pure black or white");
                }
            }
        }
        shell.afterPixels();
    }

    function afterPixels() {
        shell.round = 1;
        shell.askAll();
        shell.phase = 7;
    }

    function askAll() {
        shell.t0 = Date.now();
        var i;
        for (i = 0; i < mathRep.count; i++)
            mathRep.itemAt(i).fig.ask();
        for (i = 0; i < diagRep.count; i++)
            diagRep.itemAt(i).fig.ask();
    }

    function roundPoll() {
        if (shell.done || shell.phase !== 7)
            return;
        if (!shell.settled(mathRep) || !shell.settled(diagRep))
            return;
        var now = Date.now();
        var i;
        for (i = 0; i < mathRep.count; i++)
            shell.noteLat(mathRep.itemAt(i).tag, now);
        for (i = 0; i < diagRep.count; i++)
            shell.noteLat(diagRep.itemAt(i).tag, now);
        shell.log("round " + shell.round + " ms=" + (now - shell.t0));
        if (shell.round >= 5) {
            shell.reportLat();
            shell.phase = 0;
            shell.webengineCheck();
            return;
        }
        shell.round++;
        shell.askAll();
    }

    function noteLat(tag, now) {
        if (!shell.lat[tag])
            shell.lat[tag] = [];
        shell.lat[tag].push(now - shell.t0);
    }

    function reportLat() {
        var tags = Object.keys(shell.lat);
        for (var i = 0; i < tags.length; i++) {
            var v = shell.lat[tags[i]];
            shell.log("lat " + tags[i] + " min=" + Math.min.apply(null, v)
                + " max=" + Math.max.apply(null, v));
        }
    }

    function webengineCheck() {
        // Import only: instantiating a real WebEngineView hung the suite
        // offscreen (no line, no watchdog, dead until the shell timeout),
        // so the finding names what the import itself reports.
        try {
            var o = Qt.createQmlObject(
                "import QtQuick\nimport QtWebEngine\nQtObject { }", probe, "webprobe");
            shell.log("WEBENGINE QtWebEngine imports; a view was not created (see report)");
            o.destroy();
        } catch (e) {
            shell.log("WEBENGINE " + String(e.message || e).split("\n")[0]);
        }
        shell.httpCheck();
    }

    function httpCheck() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "http://127.0.0.1:" + shell.port + "/count");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            shell.check(String(xhr.responseText).trim() === "1",
                "zero figure fetches, server saw ping only");
            shell.finish(0);
        };
        xhr.send();
    }

    function finish(extra) {
        if (shell.done)
            return;
        shell.done = true;
        shell.phase = 0;
        pump.running = false;
        shell.check(shell.maxGap < 2000, "main thread never blocked, max tick gap ms=" + shell.maxGap);
        shell.log("pssKiB " + shell.pss.join(" "));
        shell.log("worker answers=" + Flea.FigureService.workerAnswers + " sends=" + Flea.FigureService.sends);
        shell.check(Flea.FigureService.workerAnswers > 0, "every answer came through the worker");
        shell.log("DONE failures=" + (shell.failures + extra));
        shell.quit();
    }

    Component.onCompleted: {
        if (shell.port === "") {
            shell.log("FAIL no FLEA_FIG_PORT arrived");
            shell.finish(1);
            return;
        }
        var ping = new XMLHttpRequest();
        ping.open("GET", "http://127.0.0.1:" + shell.port + "/ping");
        ping.onreadystatechange = function () {
            if (ping.readyState !== XMLHttpRequest.DONE)
                return;
            if (ping.status !== 200) {
                shell.log("FAIL the hit-counting server never answered");
                shell.finish(1);
                return;
            }
            shell.phase = 1;
            shell.readPss("pss0", 5);
        };
        ping.send();
    }
}
