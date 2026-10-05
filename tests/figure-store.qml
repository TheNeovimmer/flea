//@ pragma ShellId flea-figure-store-test

import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// The persistent SVG cache through the real helper and store: a figure drawn once answers a repeat from disk with no helper, and no other theme or advance ever does.
ShellRoot {
    id: shell

    function log(line) { console.log("FIGURE_STORE " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property int checks: 0
    property int failures: 0
    property bool done: false
    property int index: -1
    property bool waiting: false
    property int ticket: 0
    // An id no service ticket ever has, so a direct get on the store is told from the service's own.
    readonly property int probeId: 1000000
    property string drawn: ""
    property int sendsMark: 0
    property int exitsMark: 0
    property int hitsMark: 0
    property int missesMark: 0
    readonly property int idleExitMs: 150
    readonly property int watchdogMs: 90000
    readonly property var theme: ({ bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 14, exPx: 7 })
    readonly property var otherTheme: ({ bg: "#101315", fg: "#c0caf5", accent: "#f7768e", font: "monospace", bodyPx: 14, exPx: 7 })
    readonly property var unseenTheme: ({ bg: "#101315", fg: "#c0caf5", accent: "#e0af68", font: "monospace", bodyPx: 14, exPx: 7 })
    readonly property var advancesA: ({ bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 14, exPx: 7, advances: [500, 600], boldAdvances: [550, 650] })
    readonly property var advancesB: ({ bg: "#101315", fg: "#c0caf5", accent: "#7aa2f7", font: "monospace", bodyPx: 14, exPx: 7, advances: [500, 601], boldAdvances: [550, 650] })
    readonly property string source: "\\frac{a}{b}"
    // Most of an entry's size limit, so a kill instead of a drain leaves the store with only a pipe's worth of it.
    readonly property int largeSvgChars: 3500000
    readonly property string largeSvg: "<svg>" + "x".repeat(shell.largeSvgChars) + "</svg>"
    readonly property string largeKey: Flea.FigureService.cacheKeyOf("math", "put then stop", shell.theme, true)
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

    // Forgets the in-memory answers, so only the disk can answer the next ask.
    function forgetMemory() {
        Flea.FigureService.answerCache = ({})
        Flea.FigureService.answerOrder = []
    }

    function mark() {
        shell.sendsMark = Flea.FigureService.sends
        shell.exitsMark = Flea.FigureService.helperExits
        shell.hitsMark = Flea.FigureService.persistent.hits
        shell.missesMark = Flea.FigureService.persistent.misses
    }

    function ask(kind, source, theme) {
        shell.forgetMemory()
        shell.ticket = Flea.FigureService.ask(kind, source, true, theme)
    }

    readonly property var figureBlock: ({ type: "figure", kind: "math", source: shell.source, display: true })
    readonly property var unknownBlock: ({ type: "figure", kind: "math", source: "never drawn", display: true })

    // A case asks or warms; its verdict comes from the answer (cases with a verify) or from the store's known reply (cases with a known).
    readonly property var cases: [
        { act: function () { shell.ask("math", shell.source, shell.theme) },
          verify: function (svg, error, service, disk) {
              shell.drawn = svg
              shell.check(shell.drew(svg, error) && service.sends === shell.sendsMark + 1 && disk.misses === shell.missesMark + 1, "a figure never drawn misses the disk and the helper draws it")
              shell.check(disk.puts === 1, "the helper's answer is written to the disk cache once")
          } },
        { act: function () { shell.ask("math", shell.source, shell.theme) },
          verify: function (svg, error, service, disk) {
              shell.check(shell.drew(svg, error) && svg === shell.drawn, "a repeat answers the drawn bytes")
              shell.check(service.sends === shell.sendsMark && service.helperExits === shell.exitsMark && !service.helperRunning && disk.hits === shell.hitsMark + 1,
                  "a repeat from disk starts no helper and sends it nothing")
          } },
        { act: function () { shell.ask("math", shell.source, shell.otherTheme) },
          verify: function (svg, error, service, disk) {
              shell.check(shell.drew(svg, error) && service.sends === shell.sendsMark + 1 && disk.hits === shell.hitsMark, "another theme is never served the first theme's figure")
          } },
        { act: function () { shell.ask("math", shell.source, shell.advancesA) },
          verify: function (svg, error, service, disk) {
              shell.check(shell.drew(svg, error) && service.sends === shell.sendsMark + 1 && disk.hits === shell.hitsMark, "a first advance table is drawn by the helper")
          } },
        { act: function () { shell.ask("math", shell.source, shell.advancesB) },
          verify: function (svg, error, service, disk) {
              shell.check(shell.drew(svg, error) && service.sends === shell.sendsMark + 1 && disk.hits === shell.hitsMark, "another advance table is never served the first one's figure")
          } },
        { act: function () { shell.ask("math", shell.source, shell.advancesA) },
          verify: function (svg, error, service, disk) {
              shell.check(shell.drew(svg, error) && service.sends === shell.sendsMark && disk.hits === shell.hitsMark + 1, "the first advance table's figure is still on disk")
          } },
        // Every figure of this document is on disk under the theme it is asked under, so warming it asks the store and starts no helper.
        { act: function () { Flea.FigureService.warm([shell.figureBlock], { math: shell.theme }) },
          known: function (all, service) {
              shell.check(all === true && !service.helperRunning && !service.starting && service.sends === shell.sendsMark, "a document whose figures are all on disk starts no helper")
          } },
        // The same figure under a theme never drawn is not known, so the helper starts warm; an idle stop meanwhile is refused and the reply still lands.
        { act: function () {
              Flea.FigureService.warm([shell.figureBlock], { math: shell.unseenTheme })
              shell.check(Flea.FigureService.persistent.stop() === false, "an idle stop is refused while the store owes the warm query's reply")
          },
          known: function (all, service) {
              shell.check(all === false && (service.helperRunning || service.starting), "a figure drawn under another accent does not keep the helper from starting warm")
          } },
        // One figure never drawn: the answer is not all, and the helper starts warm.
        { act: function () { Flea.FigureService.warm([shell.figureBlock, shell.unknownBlock], { math: shell.theme }) },
          known: function (all, service) {
              shell.check(all === false, "a document with a figure never drawn is not all known")
              shell.check(service.helperRunning || service.starting, "the helper is started warm for it")
          } },
        // A get starts the store, then a large put and an idle stop land in one turn: stdin closes and the store drains, where a kill would lose the entry.
        { act: function () { Flea.FigureService.persistent.get(shell.probeId, "math\nnever stored\nfalse\nx") },
          answered: function (disk) {
              disk.put(shell.largeKey, shell.largeSvg)
              shell.check(disk.stop() === true, "an idle stop with only a put in flight is accepted")
              shell.verdictDone()
          } },
        { act: function () { shell.ask("math", "put then stop", shell.theme) },
          verify: function (svg, error, service, disk) {
              shell.check(svg === shell.largeSvg && service.sends === shell.sendsMark && disk.hits === shell.hitsMark + 1, "the put that an idle stop followed at once is on disk")
          } }
    ]

    function drew(svg, error) { return svg.indexOf("<svg") === 0 && error === "" }

    function runNext() {
        shell.waiting = false
        shell.index++
        if (shell.index >= shell.cases.length) {
            shell.finish()
            return
        }
        shell.mark()
        shell.cases[shell.index].act()
    }

    // The next case starts once the helper and the store have both stopped at their idle exit, so each case begins from nothing running.
    function settle() {
        var service = Flea.FigureService
        if (shell.waiting && !service.helperRunning && !service.starting && !service.persistent.active)
            shell.runNext()
    }

    function verdictDone() {
        shell.waiting = true
        Qt.callLater(shell.settle)
    }

    Connections {
        target: Flea.FigureService
        function onDone(ticket, svg, error) {
            var current = shell.cases[shell.index]
            if (ticket !== shell.ticket || !current || !current.verify)
                return
            current.verify(svg, error, Flea.FigureService, Flea.FigureService.persistent)
            shell.verdictDone()
        }
        function onHelperRunningChanged() { Qt.callLater(shell.settle) }
    }

    Connections {
        target: Flea.FigureService.persistent
        // Deferred, so the next case never starts inside the change that announced the stop.
        function onActiveChanged() { Qt.callLater(shell.settle) }
        function onAnswered(id, svg) {
            var current = shell.cases[shell.index]
            if (id === shell.probeId && current && current.answered)
                current.answered(Flea.FigureService.persistent)
        }
        function onKnown(id, all) {
            var current = shell.cases[shell.index]
            if (!current || !current.known)
                return
            // The service's own handler has acted by the time this runs, so a helper it started is already starting.
            Qt.callLater(function () {
                current.known(all, Flea.FigureService)
                shell.verdictDone()
            })
        }
    }

    Timer {
        interval: shell.watchdogMs
        running: !shell.done
        onTriggered: {
            shell.check(false, "the watchdog outlived the verdict at case " + shell.index)
            shell.finish()
        }
    }

    Timer {
        interval: 1
        running: true
        onTriggered: shell.runNext()
    }
}
