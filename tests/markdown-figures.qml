//@ pragma ShellId flea-markdown-figures-test

import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// FigureService against the real helper: answers, the 64-entry cache, the
// idle exit, the timeout restart and the 127 latch. Quits itself.
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

    property string phaseFile: Quickshell.env("FLEA_FIG_PHASE_FILE")
    property int step: 0
    property double t0: 0
    property int sendsMark: 0
    property int answersMark: 0
    property string firstSvg: ""
    property string inlineSvg: ""
    property int ticket: 0
    property var ticks: []
    property double maxGap: 0
    // A source to ask once the current helper has stopped: the phase file
    // only affects the next spawned helper, never the running one.
    property string awaitSource: ""
    // The step an awaited ask lands on; 4, 60, 80 and 100 only wait.
    property int afterAwait: 0
    // Bounded wait for the deadline timer to stop after the last answer.
    property bool awaitTimerStop: false
    property double stopWaitStart: 0
    property int stopWaitMs: 5000
    // The memory phases: sixteen figures no functional step asks for.
    property int measFormulas: 0
    property int measDiagrams: 0
    // How many figures each memory phase renders; the shell checks the phases.
    property int measFormulaN: 10
    property int measDiagramN: 6
    property int measIdleExitMs: 150
    property double idleStoppedAt: 0
    property int idleWaitMs: 5000
    property int prodIdleExitMs: 30000
    property int exitAnswerBoundMs: 2000
    property double exitAskedAt: 0

    // Step order: answers, cache hit, idle exit, timeout restart, 127 latch.
    // The latch is last because it ends rendering for the session.

    Component.onCompleted: {
        if (shell.phaseFile === "") {
            shell.log("FAIL no FLEA_FIG_PHASE_FILE arrived");
            shell.finish(1);
            return;
        }
        shell.check(Flea.FigureService.deadlineRunning === false, "the deadline timer is stopped before the first ask");
        shell.logPss("before");
        shell.step = 20;
        shell.askMeasFormula(0);
    }

    function askMeasFormula(n) {
        shell.ticket = Flea.FigureService.ask("math", "\\psi+" + n, true, shell.theme());
    }

    function askMeasDiagram(n) {
        shell.ticket = Flea.FigureService.ask("mermaid", "flowchart TD\n    P" + n + " --> Q" + n, true, shell.theme());
    }

    // Sample inputs: "Pss: 45120 kB" in /proc/self/smaps_rollup, "VmHWM: 41380 kB" in /proc/<pid>/status.
    function memField(path, key) {
        memView.path = path;
        memView.waitForJob();
        var lines = memView.text().split("\n");
        for (var i = 0; i < lines.length; i++) {
            var cut = lines[i].split(":");
            if (cut.length >= 2 && cut[0] === key)
                return parseInt(cut[1], 10);
        }
        return -1;
    }

    function logPss(phase) {
        shell.log("FIGPSS phase=" + phase + " pss_kb=" + shell.memField("/proc/self/smaps_rollup", "Pss"));
    }

    // The pid is bwrap's; qjs runs below it in the jail's pid namespace, so the peak is the tree's.
    function treePeak(pid) {
        var best = shell.memField("/proc/" + pid + "/status", "VmHWM");
        memView.path = "/proc/" + pid + "/task/" + pid + "/children";
        memView.waitForJob();
        var kids = memView.text().trim().split(/\s+/);
        for (var i = 0; i < kids.length; i++) {
            if (kids[i].length > 0)
                best = Math.max(best, shell.treePeak(kids[i]));
        }
        return best;
    }

    function logHelperPeak() {
        shell.log("FIGHELPER rss_peak_kb=" + shell.treePeak(Flea.FigureService.helperPid));
    }

    function theme() {
        return { bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 14 };
    }

    function askFormula() {
        shell.ticket = Flea.FigureService.ask("math", "\\frac{a}{b}", true, shell.theme());
    }

    // Every helper-reaching step names a source no earlier step asked for:
    // a repeat would answer from the cache and never touch the helper.
    function askFresh(source) {
        shell.ticket = Flea.FigureService.ask("math", source, true, shell.theme());
    }

    function askDiagram() {
        shell.ticket = Flea.FigureService.ask("mermaid", "flowchart TD\n    A --> B", true, shell.theme());
    }

    Connections {
        target: Flea.FigureService
        function onDone(ticket, svg, error) { shell.landed(ticket, svg, error); }
    }

    function landed(ticket, svg, error) {
        if (ticket !== shell.ticket)
            return;
        shell.ticket = 0;
        // Each step arms the next ask, so a late duplicate lands on no ticket.
        if (shell.step === 20) {
            shell.check(svg !== "" && error === "", "measure formula " + shell.measFormulas + " answers");
            shell.measFormulas++;
            if (shell.measFormulas < shell.measFormulaN) {
                shell.askMeasFormula(shell.measFormulas);
            } else {
                shell.logPss("formulas");
                shell.step = 21;
                shell.askMeasDiagram(0);
            }
        } else if (shell.step === 21) {
            shell.check(svg !== "" && error === "", "measure diagram " + shell.measDiagrams + " answers");
            shell.measDiagrams++;
            if (shell.measDiagrams < shell.measDiagramN) {
                shell.askMeasDiagram(shell.measDiagrams);
            } else {
                shell.logPss("diagrams");
                shell.logHelperPeak();
                Flea.FigureService.idleExitMs = shell.measIdleExitMs;
                shell.step = 22;
            }
        } else if (shell.step === 1) {
            shell.check(svg !== "" && error === "", "a formula answers through the helper");
            shell.firstSvg = svg;
            shell.step = 2;
            shell.askDiagram();
        } else if (shell.step === 2) {
            shell.check(svg !== "" && error === "", "a diagram answers through the helper");
            // Sample input: <svg xmlns="http://www.w3.org/2000/svg"> has a namespace, not a fetch.
            var checkedSvg = svg.replace(/xmlns(?::\w+)?="[^"]*"/g, "");
            shell.check(checkedSvg.indexOf("http:") < 0 && checkedSvg.indexOf("https:") < 0, "the diagram answer passes checkSafe");
            shell.step = 3;
            shell.sendsMark = Flea.FigureService.sends;
            shell.answersMark = Flea.FigureService.workerAnswers;
            shell.askFormula();
        } else if (shell.step === 3) {
            shell.check(svg === shell.firstSvg && error === "", "a second identical request is a cache hit");
            shell.check(Flea.FigureService.sends === shell.sendsMark, "the cache hit writes no new helper line");
            shell.check(Flea.FigureService.workerAnswers === shell.answersMark, "the cache hit asks the helper nothing");
            shell.step = 31;
            shell.ticket = Flea.FigureService.ask("math", "\\frac{a}{b}", false, shell.theme());
        } else if (shell.step === 31) {
            shell.check(svg !== "" && svg !== shell.firstSvg && error === "", "the same source inline renders separately from display");
            shell.check(Flea.FigureService.sends === shell.sendsMark + 1, "inline mode sends one new helper line");
            shell.inlineSvg = svg;
            shell.step = 32;
            shell.ticket = Flea.FigureService.ask("math", "\\frac{a}{b}", false, shell.theme());
        } else if (shell.step === 32) {
            shell.check(svg === shell.inlineSvg && error === "", "the inline revisit keeps its own answer");
            shell.check(Flea.FigureService.sends === shell.sendsMark + 1, "the inline revisit sends nothing");
            shell.step = 33;
            shell.askFormula();
        } else if (shell.step === 33) {
            shell.check(svg === shell.firstSvg && error === "", "the display revisit keeps its own answer");
            shell.check(Flea.FigureService.sends === shell.sendsMark + 1, "the display revisit sends nothing");
            shell.step = 4;
            Flea.FigureService.idleExitMs = 150;
            shell.t0 = Date.now();
            shell.awaitSource = "\\sqrt{2}";
            shell.afterAwait = 5;
        } else if (shell.step === 5) {
            shell.check(svg !== "" && error === "", "a request after the idle exit restarts the helper");
            shell.step = 6;
            Flea.FigureService.renderMs = 400;
            shell.writePhase("hang", function () {
                shell.awaitSource = "\\int_0^1 x^2\\,dx";
                shell.afterAwait = 7;
                shell.step = 60;
            });
        } else if (shell.step === 7) {
            shell.check(svg === "" && error === "render timed out", "a helper that never answers times out");
            Flea.FigureService.renderMs = 5000;
            shell.writePhase("answer", function () {
                shell.awaitSource = "\\sum_{n=1}^{\\infty}\\frac{1}{n^2}";
                shell.afterAwait = 9;
                shell.step = 80;
            });
        } else if (shell.step === 9) {
            shell.check(svg !== "" && error === "", "the next request after a timeout starts a fresh helper");
            shell.writePhase("exit42", function () {
                shell.awaitSource = "\\chi+42";
                shell.afterAwait = 14;
                shell.step = 140;
            });
        } else if (shell.step === 14) {
            shell.check(svg === "" && error.indexOf("exited 42") >= 0, "a helper exit names its code");
            shell.check(Date.now() - shell.exitAskedAt < shell.exitAnswerBoundMs, "a helper exit answers before the render deadline");
            shell.check(Flea.FigureService.available, "an ordinary exit leaves a fresh helper available");
            shell.step = 10;
            shell.writePhase("refused", function () {
                shell.awaitSource = "\\binom{n}{k}";
                shell.afterAwait = 11;
                shell.step = 100;
            });
        } else if (shell.step === 11) {
            shell.check(svg === "" && error !== "", "a helper that exits 127 fails the request");
            shell.check(Flea.FigureService.available === false, "the 127 exit latches available false");
            shell.step = 12;
            shell.sendsMark = Flea.FigureService.sends;
            shell.askFresh("\\binom{n}{k}");
        } else if (shell.step === 12) {
            shell.check(svg === "" && error !== "", "a latched service fails without retrying");
            shell.check(Flea.FigureService.sends === shell.sendsMark, "the latch writes no new helper line");
            shell.step = 13;
            // A source no earlier step asked for, so the latched service
            // fails it instead of answering from the cache.
            fenceFig.source = "\\alpha+\\beta";
        }
    }

    Flea.MarkdownFigure {
        id: fenceFig
        width: 400
        kind: "math"
        source: ""
        display: true
        bgHex: "#101315"
        fgHex: "#c0caf5"
        accentHex: "#7aa2f7"
        fontFamily: "monospace"
        bodyPx: 14
        onFailedChanged: {
            if (fenceFig.failed && shell.step === 13) {
                shell.check(true, "the figure shows its fence once the service latches");
                shell.awaitTimerStop = true;
                shell.stopWaitStart = Date.now();
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

    function drive() {
        // The idle exit and the timeout kill are stopped processes, not
        // answers, so the next phase's ask waits for one here.
        if (shell.awaitSource !== "" && !Flea.FigureService.helperRunning) {
            var src = shell.awaitSource;
            shell.awaitSource = "";
            shell.step = shell.afterAwait;
            if (shell.step === 5)
                shell.check(Date.now() - shell.t0 < 5000, "the idle exit stops the process");
            if (shell.step === 14)
                shell.exitAskedAt = Date.now();
            shell.askFresh(src);
        }
        // The idle-phase reading waits past the helper's stop, then the
        // functional flow starts on a production idle exit again.
        if (shell.step === 22 && !Flea.FigureService.helperRunning) {
            shell.step = 23;
            shell.idleStoppedAt = Date.now();
        }
        if (shell.step === 23 && Date.now() - shell.idleStoppedAt > shell.idleWaitMs) {
            shell.step = 0;
            shell.logPss("idle");
            Flea.FigureService.idleExitMs = shell.prodIdleExitMs;
            shell.writePhase("answer", function () { shell.step = 1; shell.askFormula(); });
        }
        // The deadline timer stops on its own tick once waiting is empty.
        if (shell.awaitTimerStop) {
            if (Flea.FigureService.deadlineRunning === false) {
                shell.awaitTimerStop = false;
                shell.check(true, "the deadline timer stops once every answer has landed");
                shell.finish(0);
            } else if (Date.now() - shell.stopWaitStart > shell.stopWaitMs) {
                shell.awaitTimerStop = false;
                shell.check(false, "the deadline timer stops once every answer has landed");
                shell.finish(1);
            }
        }
    }

    FileView {
        id: phaseView
        printErrors: false
    }

    FileView {
        id: memView
        printErrors: false
    }

    function writePhase(name, then) {
        phaseView.path = shell.phaseFile;
        phaseView.waitForJob();
        phaseView.setText(name + "\n");
        phaseView.waitForJob();
        then();
    }

    function finish(extra) {
        if (shell.done)
            return;
        shell.done = true;
        pump.running = false;
        shell.check(shell.maxGap < 2000, "main thread never blocked, max tick gap ms=" + shell.maxGap);
        shell.check(Flea.FigureService.workerAnswers > 0, "every answer came through the helper");
        shell.log("DONE failures=" + (shell.failures + extra));
        shell.quit();
    }
}
