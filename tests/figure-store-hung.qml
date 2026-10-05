//@ pragma ShellId flea-figure-store-hung-test

import QtQuick
import Quickshell
import "flea" as Flea

// A store that reads every line and never answers: after replyMs the ticket falls to the helper and draws, and the store is latched off.
ShellRoot {
    id: shell

    function log(line) { console.log("FIGURE_STORE_HUNG " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property int checks: 0
    property int failures: 0
    property bool done: false
    property int ticket: 0
    // Short, so the bound is a quick one; the check is that the reply timer runs at all, so no duration is asserted.
    readonly property int replyMs: 300
    readonly property int watchdogMs: 90000
    readonly property var theme: ({ bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 14, exPx: 7 })
    Component.onCompleted: {
        Flea.ViewState.setTextSize({ mode: 14 })
        Flea.FigureService.persistent.replyMs = shell.replyMs
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

    Connections {
        target: Flea.FigureService
        function onDone(ticket, svg, error) {
            if (ticket !== shell.ticket)
                return
            var service = Flea.FigureService
            shell.check(svg.indexOf("<svg") === 0 && error === "", "a figure the hung store never answered is drawn by the helper")
            shell.check(service.sends === 1 && service.persistent.hits === 0 && service.persistent.misses === 0, "the helper was asked once and the store answered nothing")
            shell.check(service.persistent.available === false, "the store that never answered is latched off for the session")
            shell.finish()
        }
    }

    Timer {
        interval: shell.watchdogMs
        running: !shell.done
        onTriggered: {
            shell.check(false, "the watchdog outlived the verdict: the hung store was never failed")
            shell.finish()
        }
    }

    Timer {
        interval: 1
        running: true
        onTriggered: shell.ticket = Flea.FigureService.ask("math", "x^2", true, shell.theme)
    }
}
