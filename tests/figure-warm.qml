//@ pragma ShellId flea-figure-warm-test

import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// A document with figures starts the helper before its figures are asked for; every other document leaves it stopped.
ShellRoot {
    id: shell

    function log(line) { console.log("FIGURE_WARM " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property string figures: Quickshell.env("FLEA_FIGURE_WARM_FIGURES")
    property string plain: Quickshell.env("FLEA_FIGURE_WARM_PLAIN")
    property int checks: 0
    property int failures: 0
    property bool done: false
    property int step: 0
    property int exitsMark: 0
    property var pidMark: 0
    property int ticket: 0
    readonly property int idleExitMs: 150
    readonly property int watchdogMs: 90000
    Component.onCompleted: {
        Flea.ViewState.setTextSize({ mode: 14 })
        Flea.FigureService.idleExitMs = shell.idleExitMs
    }

    function check(passed, why) {
        shell.checks++
        if (!passed)
            shell.failures++
        shell.log((passed ? "PASS " : "FAIL ") + why)
    }

    function finish() {
        if (shell.done)
            return
        shell.done = true
        shell.log(shell.checks + " checks, " + shell.failures + " failed")
        shell.quit()
    }

    // The helper's own command line, read from /proc: bwrap's argv carries the helper's flags last.
    FileView {
        id: cmdline
        printErrors: false
    }
    function commandOf(pid) {
        cmdline.path = "/proc/" + pid + "/cmdline"
        cmdline.reload()
        cmdline.waitForJob()
        return cmdline.text().split("\u0000").join(" ")
    }

    // Three documents, each inactive until its step, so each one's parse is its own event.
    Flea.PreviewMarkdown {
        id: sourceDoc
        width: 560
        height: 800
        active: false
        view: "source"
        path: shell.figures
        size: 1
    }
    Flea.PreviewMarkdown {
        id: plainDoc
        width: 560
        height: 800
        active: false
        view: "rendered"
        path: shell.plain
        size: 1
    }
    Flea.PreviewMarkdown {
        id: figuresDoc
        width: 560
        height: 800
        active: false
        view: "rendered"
        path: shell.figures
        size: 1
    }

    // A document that parsed with the service still stopped: one turn later nothing has started it.
    function settledStopped(label) {
        Qt.callLater(function () {
            shell.check(!Flea.FigureService.helperRunning && !Flea.FigureService.starting && Flea.FigureService.helperExits === shell.exitsMark,
                label + " leaves the helper stopped")
            shell.next()
        })
    }

    function next() {
        shell.step++
        // Source view parses the document and may send no figure request, so it warms nothing.
        if (shell.step === 1)
            sourceDoc.active = true
        else if (shell.step === 2)
            plainDoc.active = true
        // The rendered figures document, active at last: the helper starts with no figure asked for.
        else if (shell.step === 3)
            figuresDoc.active = true
    }

    Connections {
        target: sourceDoc
        function onContentReadyChanged() {
            if (sourceDoc.contentReady && shell.step === 1)
                shell.settledStopped("a source view of a document with figures")
        }
    }

    Connections {
        target: plainDoc
        function onContentReadyChanged() {
            if (plainDoc.contentReady && shell.step === 2)
                shell.settledStopped("a rendered document with no figures")
        }
    }

    // The warm helper, answered once, ends at the idle exit like any other; the next ask starts it again.
    // The exit count and the running flag change in separate turns, so both signals come here.
    function idleEnded() {
        var service = Flea.FigureService
        if (shell.step === 5 && service.helperExits === shell.exitsMark + 1 && !service.helperRunning) {
            shell.check(true, "the idle exit still ends a warm helper")
            shell.step = 6
            shell.ticket = service.ask("math", "x^2+1", true, { bg: "#101315", fg: "#c0caf5", font: "monospace", bodyPx: 14 })
        }
    }

    Connections {
        target: Flea.FigureService
        function onHelperRunningChanged() {
            shell.idleEnded()
            if (!Flea.FigureService.helperRunning || shell.step !== 3)
                return
            var service = Flea.FigureService
            shell.check(service.sends === 0 && service.workerAnswers === 0 && service.pending.length === 0 && Object.keys(service.waiting).length === 0,
                "the resting figures document starts the helper before any figure is asked of it")
            shell.exitsMark = service.helperExits
            shell.pidMark = service.helperPid
            shell.step = 4
            shell.ticket = service.ask("math", "\\frac{a}{b}", true, { bg: "#101315", fg: "#c0caf5", font: "monospace", bodyPx: 14 })
        }
        function onDone(ticket, svg, error) {
            if (ticket !== shell.ticket)
                return
            var service = Flea.FigureService
            if (shell.step === 4) {
                shell.check(svg.indexOf("<svg") === 0 && error === "", "the first figure is answered")
                shell.check(service.helperExits === shell.exitsMark && service.helperPid === shell.pidMark && service.sends >= 1, "by the helper the warm start made, not a second one")
                var command = shell.commandOf(service.helperPid)
                shell.check(command.indexOf("--warm=mermaid,math") >= 0, "that helper was started warm for the document's kinds in order: " + command.slice(-50))
                shell.step = 5
            } else if (shell.step === 6) {
                shell.check(svg.indexOf("<svg") === 0 && error === "", "a figure after the idle exit restarts a plain helper")
                shell.check(shell.commandOf(service.helperPid).indexOf("--warm") < 0, "the restart carries no warm kinds: the start read them once")
                shell.finish()
            }
        }
        function onHelperExitsChanged() { shell.idleEnded() }
    }

    Timer {
        interval: shell.watchdogMs
        running: !shell.done
        onTriggered: {
            shell.check(false, "the watchdog outlived the verdict at step " + shell.step)
            shell.finish()
        }
    }

    // The inactive document is the moving cursor: it holds the figures path and the helper stays stopped.
    Timer {
        id: first
        interval: 1
        running: true
        onTriggered: {
            shell.check(!Flea.FigureService.helperRunning && !Flea.FigureService.starting, "a document that is not active (a moving cursor) starts nothing")
            shell.next()
        }
    }
}
