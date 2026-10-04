//@ pragma ShellId flea-markdown-mathsize-test

import QtQuick
import Quickshell
import "flea" as Flea
import "markdown-figures-render.js" as Checks
import "markdown-mathsize.js" as Size

// Display formulas through the real helper draw at the body font's x-height at each text size, wide ones fitted.
ShellRoot {
    id: shell
    // The text sizes the suite draws at, in order; the second change proves a rendered formula is not served at the first size.
    readonly property var sizes: [14, 12]
    property int sizeAt: 0
    property int askMark: 0
    property bool done: false
    property bool settling: false
    property int checks: 0
    property int failures: 0

    function log(line) { console.log("MARKDOWN_MATHSIZE " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(error, name) {
        shell.checks++
        if (error !== "") shell.failures++
        shell.log((error === "" ? "CHECK " : "FAIL ") + name + (error === "" ? "" : ": " + error))
    }

    // The font the body text uses: MarkdownText takes this family at the pane's body pixel size.
    FontMetrics {
        id: bodyFont
        font.family: Flea.Theme.font.family
        font.pixelSize: Flea.Theme.font.body
    }

    FloatingWindow {
        id: window
        implicitWidth: 560
        implicitHeight: 600
        color: "#101315"
        Flea.PreviewMarkdown {
            id: md
            anchors.fill: parent
            active: true
            path: Quickshell.env("FLEA_MARKDOWN_FIGURE_FIXTURE")
            size: 1
            view: "rendered"
        }
    }

    // A font whose x-height the container cannot supply: the seam forces the measured height, here the 9 px the defect capture showed at body 14.
    readonly property real forcedXHeight: 9
    Flea.MarkdownFigure {
        id: forced
        parent: window.contentItem
        opacity: 0
        width: 560
        source: "x^2"
        bodyPx: 14
        fgHex: "#c0caf5"
    }
    Component.onCompleted: {
        Flea.ViewState.setTextSize({ mode: shell.sizes[0] })
        forced.xHeight = shell.forcedXHeight
    }

    // Every formula has answered the current size's ask and decoded its image.
    function ready() {
        if (!md.contentReady || md.blockList.length !== 4 || Flea.Theme.font.body !== shell.sizes[shell.sizeAt])
            return false
        for (var i = 1; i <= 3; i++) {
            var fig = Checks.figure(md, i)
            var image = Checks.imageOf(fig)
            if (!fig || !fig.ready || fig.working || fig.askPending || fig.askRuns <= shell.askMark
                    || fig.bodyPx !== Flea.Theme.font.body || !image || image.status !== Image.Ready || image.height <= 0)
                return false
        }
        var held = Checks.imageOf(forced)
        return forced.ready && !forced.working && !forced.askPending && forced.askRuns > 0 && held !== null
            && held.status === Image.Ready && held.height > 0
    }

    function measure() {
        var body = Flea.Theme.font.body
        var xHeight = bodyFont.xHeight
        shell.log("body " + body + "px x-height " + xHeight.toFixed(2) + "px")
        shell.check(xHeight > 0 ? "" : "the body font reports no x-height", "body x-height measured at " + body)
        var names = ["x^2", "frac", "wide"]
        for (var i = 1; i <= 3; i++) {
            var fig = Checks.figure(md, i)
            var image = Checks.imageOf(fig)
            if (i < 3)
                shell.check(Size.mathExError(fig, image, xHeight), names[i - 1] + " ex matches body x-height at " + body)
            else
                shell.check(Size.mathFitError(fig, image, fig.width), names[i - 1] + " fits the pane at " + body)
        }
        if (shell.sizeAt === 0) {
            shell.check(forced.xHeight === shell.forcedXHeight ? "" : "the figure keeps no xHeight seam, it reads " + forced.xHeight, "figure exposes its body x-height")
            shell.check(Size.mathExError(forced, Checks.imageOf(forced), shell.forcedXHeight), "ex follows a 9px body x-height at 14")
        }
        shell.sizeAt++
        if (shell.sizeAt < shell.sizes.length) {
            shell.askMark = Math.max(Checks.figure(md, 1).askRuns, Checks.figure(md, 2).askRuns, Checks.figure(md, 3).askRuns)
            Flea.ViewState.setTextSize({ mode: shell.sizes[shell.sizeAt] })
            shell.settling = false
        } else {
            shell.done = true
            shell.log(shell.checks + " checks, " + shell.failures + " failed")
            shell.quit()
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: !shell.done
        onTriggered: if (!shell.settling && shell.ready()) {
            shell.settling = true
            shell.measure()
        }
    }
    Timer {
        interval: 30000
        running: !shell.done
        onTriggered: {
            shell.done = true
            shell.log("FAIL display formulas never settled at size " + shell.sizes[shell.sizeAt])
            shell.quit()
        }
    }
}
