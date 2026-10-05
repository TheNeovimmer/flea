//@ pragma ShellId flea-figure-store-drain-test

import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// A line queued behind a drain is drawn by the helper within drainMs and the draining store is left alone; only a store still draining at drainHangMs is killed, and one that commits slowly keeps its put.
ShellRoot {
    id: shell

    function log(line) { console.log("FIGURE_STORE_DRAIN " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property int checks: 0
    property int failures: 0
    property bool done: false
    property int step: 0
    property int ticket: 0
    property var hungPid: 0
    property bool released: false
    property int sendsMark: 0
    // "hang" is a store that answers every line and ignores EOF; "slow" commits its puts for longer than drainMs after EOF and then exits.
    readonly property string mode: Quickshell.env("FLEA_DRAIN_MODE")
    // Short, so the bounds are quick ones; the checks are on what each bound does, so no duration is asserted.
    readonly property int drainMs: 300
    readonly property int drainHangMs: shell.mode === "hang" ? 4000 : 600000
    readonly property int idleExitMs: 150
    readonly property int watchdogMs: 90000
    readonly property var theme: ({ bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 14, exPx: 7 })
    Component.onCompleted: {
        Flea.ViewState.setTextSize({ mode: 14 })
        Flea.FigureService.idleExitMs = shell.idleExitMs
        Flea.FigureService.persistent.drainMs = shell.drainMs
        Flea.FigureService.persistent.drainHangMs = shell.drainHangMs
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

    function drew(svg, error) { return svg.indexOf("<svg") === 0 && error === "" }

    FileView {
        id: cmdline
        printErrors: false
    }
    // A process that is gone has no cmdline to read.
    function alive(pid) {
        cmdline.path = "/proc/" + pid + "/cmdline"
        cmdline.reload()
        cmdline.waitForJob()
        return cmdline.text().length > 0
    }

    function askNext(source) {
        shell.ticket = Flea.FigureService.ask("math", source, true, shell.theme)
    }

    // The hung store is gone and the next one starts clean; the slow store has exited and its put reads back.
    function drainEnded() {
        var disk = Flea.FigureService.persistent
        if (shell.step !== 4)
            return
        if (shell.mode === "hang" && disk.exits >= 1) {
            shell.check(disk.hangKills === 1 && !shell.alive(shell.hungPid) && disk.available, "the store that ignored EOF is killed at the hang bound, gone and not latched")
            shell.step = 5
            shell.askNext("x^4")
        } else if (shell.mode === "slow" && !disk.active) {
            shell.step = 6
            shell.sendsMark = Flea.FigureService.sends
            Flea.FigureService.answerCache = ({})
            Flea.FigureService.answerOrder = []
            shell.askNext("x^2")
        }
    }

    Connections {
        target: Flea.FigureService
        function onDone(ticket, svg, error) {
            if (ticket !== shell.ticket)
                return
            var service = Flea.FigureService
            var disk = service.persistent
            if (shell.step === 1) {
                shell.check(shell.drew(svg, error), "a figure the stub store missed is drawn by the helper")
                shell.step = 2
            } else if (shell.step === 3) {
                shell.check(shell.drew(svg, error), "a figure that waited behind the drain is drawn by the helper")
                shell.step = 4
                shell.drainEnded()
            } else if (shell.step === 5) {
                shell.check(shell.drew(svg, error) && disk.available && disk.misses === 2 && disk.hits === 0, "the next store starts clean and answers itself")
                shell.finish()
            } else if (shell.step === 6) {
                shell.check(shell.drew(svg, error) && disk.hits === 1 && service.sends === shell.sendsMark, "the put the slow drain committed reads back from disk with no helper")
                shell.finish()
            }
        }
    }

    Connections {
        target: Flea.FigureService.persistent
        // The idle stop closed stdin and the stub keeps draining: a get now queues behind the drain.
        function onStoppingChanged() {
            var disk = Flea.FigureService.persistent
            if (!disk.stopping || shell.step !== 2)
                return
            shell.hungPid = disk.pid
            shell.step = 3
            // Deferred past the service's idle handler, which is still stopping the helper when the store announces its stop.
            Qt.callLater(function () { shell.askNext("x^3") })
        }
        // The line behind the drain is answered a miss while the store is still draining, alive and not killed.
        function onAnswered(id, svg) {
            var disk = Flea.FigureService.persistent
            if (id !== shell.ticket || shell.step !== 3 || shell.released)
                return
            shell.released = true
            shell.check(svg === "" && disk.stopping && disk.hangKills === 0 && shell.alive(shell.hungPid), "a line queued behind the drain is answered a miss while the store is still draining, alive")
        }
        function onExitsChanged() { shell.drainEnded() }
        function onActiveChanged() { shell.drainEnded() }
    }

    Timer {
        interval: shell.watchdogMs
        running: !shell.done
        onTriggered: {
            shell.check(false, "the watchdog outlived the verdict at step " + shell.step)
            shell.finish()
        }
    }

    Timer {
        interval: 1
        running: true
        onTriggered: {
            shell.step = 1
            shell.askNext("x^2")
        }
    }
}
