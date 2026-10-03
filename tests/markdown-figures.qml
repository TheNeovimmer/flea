//@ pragma ShellId flea-markdown-figures-test

import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "figure-memory" as Memory

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
    // Bound the wait for the idle helper's exit event.
    readonly property int idleExitBoundMs: 5000
    property alias idleExitWait: idleExitWaitTimer
    property int helperExitsMark: 0
    property int renderDeadlineMark: 0
    property int sendsMark: 0
    property int answersMark: 0
    property string firstSvg: ""
    property string inlineSvg: ""
    property int ticket: 0
    property int pendingPumpCallbacks: 0
    property bool hangingDeadlineArmed: false
    readonly property int hangingRenderLimitMs: 300000
    readonly property int tickIntervalMs: 50
    // Pump callbacks prove liveness before the test makes the hanging ticket overdue.
    readonly property int requiredPendingPumpCallbacks: 2
    readonly property int expiredTicketDeadline: 0
    readonly property int recoveredRenderMs: 5000
    readonly property int watchdogMs: 150000
    // A source to ask once the current helper has stopped: the phase file
    // only affects the next spawned helper, never the running one.
    property string awaitSource: ""
    // The step an awaited ask lands on; 4, 60, 80 and 100 only wait.
    property int afterAwait: 0
    // Bounded wait for the deadline timer to stop after the last answer.
    property bool awaitTimerStop: false
    readonly property int stopWaitMs: 5000
    // The memory phases: sixteen figures no functional step asks for.
    property int measFormulas: 0
    property int measDiagrams: 0
    // How many figures each memory phase renders; the shell checks the phases.
    property int measFormulaN: 10
    property int measDiagramN: 6
    property int measIdleExitMs: 150
    readonly property int idleWaitMs: 5000
    property int prodIdleExitMs: 30000

    // Step order: answers, cache hit, idle exit, timeout restart, 127 latch.
    // The latch is last because it ends rendering for the session.

    Component.onCompleted: {
        if (shell.phaseFile === "") {
            shell.log("FAIL no FLEA_FIG_PHASE_FILE arrived");
            shell.finish(1);
            return;
        }
        shell.check(Flea.FigureService.deadlineRunning === false, "the deadline timer is stopped before the first ask");
        memory.checkReload(shell.phaseFile, shell.writePhase, shell.check, function () {
            shell.writePhase("answer", function () {
                shell.logPss("before");
                shell.step = 20;
                shell.askMeasFormula(0);
            });
        });
    }

    function askMeasFormula(n) {
        shell.ticket = Flea.FigureService.ask("math", "\\psi+" + n, true, shell.theme());
    }

    function askMeasDiagram(n) {
        shell.ticket = Flea.FigureService.ask("mermaid", "flowchart TD\n    P" + n + " --> Q" + n, true, shell.theme());
    }

    function logPss(phase) {
        var sample = memory.snapshot("/proc/self/smaps_rollup");
        shell.log("FIGPSS phase=" + phase + " pss_kb=" + sample.pss + " read_seq=" + sample.readSequence
            + " anonymous_kb=" + sample.anonymous + " rss_kb=" + sample.rss);
    }

    function logHelperPeak() {
        shell.log("FIGHELPER rss_peak_kb=" + memory.treePeak(Flea.FigureService.helperPid));
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
                shell.helperExitsMark = Flea.FigureService.helperExits;
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
            Flea.FigureService.idleExitMs = shell.measIdleExitMs;
            shell.helperExitsMark = Flea.FigureService.helperExits;
            shell.idleExitWait.start();
            shell.awaitSource = "\\sqrt{2}";
            shell.afterAwait = 5;
        } else if (shell.step === 5) {
            shell.check(svg !== "" && error === "", "a request after the idle exit restarts the helper");
            shell.step = 6;
            Flea.FigureService.renderMs = shell.hangingRenderLimitMs;
            shell.writePhase("hang", function () {
                shell.awaitSource = "\\int_0^1 x^2\\,dx";
                shell.afterAwait = 7;
                shell.step = 60;
            });
        } else if (shell.step === 7) {
            shell.check(svg === "" && error === "render timed out", "a helper that never answers times out");
            shell.check(Flea.FigureService.deadlineExpirations > shell.renderDeadlineMark, "the hanging helper answers from the deadline event");
            shell.check(shell.hangingDeadlineArmed && shell.pendingPumpCallbacks === shell.requiredPendingPumpCallbacks,
                "pending-ticket pump callbacks precede the hanging deadline");
            Flea.FigureService.renderMs = shell.recoveredRenderMs;
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
            shell.check(Flea.FigureService.deadlineExpirations === shell.renderDeadlineMark, "a helper exit answers before the render deadline event");
            shell.check(Flea.FigureService.helperExits > shell.helperExitsMark, "the helper exit event precedes its answer");
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
                deadlineStopWait.start();
            }
        }
    }

    Timer {
        interval: shell.watchdogMs
        repeat: false
        running: true
        onTriggered: {
            shell.log("FAIL the watchdog outlived the verdict");
            shell.finish(1);
        }
    }

    Timer {
        id: pump
        interval: shell.tickIntervalMs
        repeat: true
        running: true
        onTriggered: {
            shell.drive();
        }
    }

    function drive() {
        if (shell.step === 7 && !shell.hangingDeadlineArmed
                && Flea.FigureService.written.indexOf(shell.ticket) >= 0) {
            shell.check(shell.ticket > 0 && Flea.FigureService.waiting[shell.ticket] !== undefined
                && Flea.FigureService.deadlineExpirations === shell.renderDeadlineMark,
                "pump callback sees the hanging ticket still waiting and unanswered");
            shell.pendingPumpCallbacks++;
            if (shell.pendingPumpCallbacks === shell.requiredPendingPumpCallbacks) {
                shell.hangingDeadlineArmed = true;
                Flea.FigureService.waiting[shell.ticket].deadline = shell.expiredTicketDeadline;
            }
        }
        // The idle exit and the timeout kill are stopped processes, not
        // answers, so the next phase's ask waits for one here.
        if (shell.awaitSource !== "" && !Flea.FigureService.helperRunning
                && Flea.FigureService.helperExits > shell.helperExitsMark) {
            var src = shell.awaitSource;
            shell.awaitSource = "";
            shell.step = shell.afterAwait;
            if (shell.step === 5) {
                shell.idleExitWait.stop();
                shell.check(true, "the idle exit event stops the process");
            }
            shell.helperExitsMark = Flea.FigureService.helperExits;
            shell.renderDeadlineMark = Flea.FigureService.deadlineExpirations;
            shell.askFresh(src);
        }
        // The idle-phase reading waits past the helper's stop, then the
        // functional flow starts on a production idle exit again.
        if (shell.step === 22 && !Flea.FigureService.helperRunning
                && Flea.FigureService.helperExits > shell.helperExitsMark) {
            shell.step = 23;
            memoryIdleWait.start();
        }
        // The deadline timer stops on its own tick once waiting is empty.
        if (shell.awaitTimerStop && Flea.FigureService.deadlineRunning === false) {
            shell.awaitTimerStop = false;
            deadlineStopWait.stop();
            shell.check(true, "the deadline timer stops once every answer has landed");
            shell.finish(0);
        }
    }

    function idleWaitExpired() {
        if (!Flea.FigureService.helperRunning && Flea.FigureService.helperExits > shell.helperExitsMark) {
            shell.drive();
            return;
        }
        shell.awaitSource = "";
        shell.check(false, "the idle exit event arrives before the wait timer fires");
        shell.finish(1);
    }

    Timer {
        id: idleExitWaitTimer
        interval: shell.idleExitBoundMs
        onTriggered: shell.idleWaitExpired()
    }

    Timer {
        id: memoryIdleWait
        interval: shell.idleWaitMs
        onTriggered: {
            shell.step = 0;
            shell.logPss("idle");
            Flea.FigureService.idleExitMs = shell.prodIdleExitMs;
            shell.writePhase("answer", function () {
                shell.step = 1;
                shell.askFormula();
            });
        }
    }

    Timer {
        id: deadlineStopWait
        interval: shell.stopWaitMs
        onTriggered: {
            shell.awaitTimerStop = false;
            shell.check(Flea.FigureService.deadlineRunning === false, "the deadline timer stops before the wait timer fires");
            shell.finish(0);
        }
    }

    FileView {
        id: phaseView
        printErrors: false
    }

    Memory.FigureMemory {
        id: memory
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
        shell.check(Flea.FigureService.workerAnswers > 0, "every answer came through the helper");
        shell.log("DONE failures=" + (shell.failures + extra));
        shell.quit();
    }
}
