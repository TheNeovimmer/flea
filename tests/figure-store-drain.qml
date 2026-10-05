//@ pragma ShellId flea-figure-store-drain-test

import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// A store that answers but ignores EOF never ends its drain: past drainMs it is killed, what waits behind it is drawn by the helper, and the next store starts clean.
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
    // Short, so the bound is a quick one; the check is that the drain timer runs at all, so no duration is asserted.
    readonly property int drainMs: 300
    readonly property int idleExitMs: 150
    readonly property int watchdogMs: 90000
    readonly property var theme: ({ bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 14, exPx: 7 })
    Component.onCompleted: {
        Flea.ViewState.setTextSize({ mode: 14 })
        Flea.FigureService.idleExitMs = shell.idleExitMs
        Flea.FigureService.persistent.drainMs = shell.drainMs
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

    Connections {
        target: Flea.FigureService
        function onDone(ticket, svg, error) {
            if (ticket !== shell.ticket)
                return
            var service = Flea.FigureService
            if (shell.step === 1) {
                shell.check(shell.drew(svg, error), "a figure the stub store missed is drawn by the helper")
                shell.step = 2
            } else if (shell.step === 3) {
                shell.check(shell.drew(svg, error), "a figure that waited behind the hung drain is drawn by the helper")
                shell.check(!shell.alive(shell.hungPid), "the store that ignored EOF is gone")
                shell.step = 4
                shell.askNext("x^4")
            } else if (shell.step === 4) {
                var fresh = service.persistent
                shell.check(shell.drew(svg, error) && fresh.available && fresh.misses === 2 && fresh.hits === 0, "the next store starts clean and answers itself, and the hung drain latched nothing")
                shell.finish()
            }
        }
    }

    Connections {
        target: Flea.FigureService.persistent
        // The idle stop closed stdin and the stub ignores EOF: a get now queues behind the hung drain.
        function onStoppingChanged() {
            var disk = Flea.FigureService.persistent
            if (!disk.stopping || shell.step !== 2)
                return
            shell.hungPid = disk.pid
            shell.step = 3
            // Deferred past the service's idle handler, which is still stopping the helper when the store announces its stop.
            Qt.callLater(function () { shell.askNext("x^3") })
        }
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
