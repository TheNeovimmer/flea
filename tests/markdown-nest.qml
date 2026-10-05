//@ pragma ShellId flea-markdown-nest-test

import QtQuick
import Quickshell
import "flea" as Flea
import "markdown-nest.js" as Nest

// The real PreviewMarkdown over blocks nested in items and quotes: each draws with its top-level recipe at the item's text column or inside the quote's bars.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_NEST " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    property string dir: Quickshell.env("FLEA_NEST_DIR")
    readonly property var plan: ["nest", "empty", "compact", "gap"]
    readonly property int bodySize: 14
    readonly property string nestTypes: "heading,fence,list,quote,list,quote,quote,list,quote"
    property int step: -1
    property bool done: false
    property int checks: 0
    property int failures: 0
    property int loadsMark: 0
    Component.onCompleted: Flea.ViewState.setTextSize({ mode: shell.bodySize })

    function check(error, name) {
        shell.checks++
        if (error !== "")
            shell.failures++
        shell.log((error === "" ? "CHECK " : "FAIL ") + name + (error === "" ? "" : ": " + error))
    }
    function finish(why) {
        if (shell.done)
            return
        shell.done = true
        shell.log(why !== undefined ? "FAIL " + why : shell.checks + " checks, " + shell.failures + " failed")
        shell.quit()
    }

    FloatingWindow {
        implicitWidth: 560
        implicitHeight: 1400
        color: "#101315"

        Flea.PreviewMarkdown {
            id: md
            anchors.fill: parent
            active: true
            size: 1
            view: "rendered"
        }
    }

    function start(at) {
        shell.step = at
        shell.loadsMark = md.loadRuns
        md.compact = shell.plan[at] === "compact"
        md.path = shell.dir + "/" + shell.plan[at] + ".md"
    }

    // Every block has a delegate, and every formula inside any of them has answered or failed.
    function settled() {
        for (var i = 0; i < md.blockList.length; i++) {
            var delegate = Nest.delegate(md, i)
            if (delegate === null)
                return false
            var maths = Nest.formulas(delegate)
            for (var m = 0; m < maths.length; m++)
                if (maths[m].unsettled !== 0)
                    return false
        }
        return true
    }

    function wrong(ok, text) {
        return ok ? "" : text
    }

    // One fence in a list item or a quote: its left edge, right edge and recipe against the top-level fence.
    function fenceChecks(block, frameName, leftWant, label) {
        var d = Nest.delegate(md, block)
        var frame = Nest.first(d, frameName)
        var fence = Nest.first(d, "fenceBox")
        shell.check(wrong(frame !== null && fence !== null, "no fence inside the " + label), label + " holds a fence block")
        if (frame === null || fence === null)
            return
        var edge = Nest.at(fence, frame)
        shell.check(wrong(Nest.near(edge.x, leftWant), "left edge " + edge.x + ", want " + leftWant), label + "'s fence starts at its text column")
        shell.check(wrong(Nest.near(edge.x + fence.width, frame.width), "right edge " + (edge.x + fence.width) + " of " + frame.width), label + "'s fence runs to the content edge")
        var top = Nest.first(Nest.delegate(md, 1), "fenceBox")
        shell.check(wrong(Nest.recipe(fence) === Nest.recipe(top), Nest.recipe(fence) + " against " + Nest.recipe(top)), label + "'s fence draws the top-level recipe")
    }

    function nestChecks() {
        var types = md.blockList.map(function (b) { return b.type }).join(",")
        shell.check(wrong(types === shell.nestTypes, types), "nest fixture block types")
        var column = Nest.first(Nest.delegate(md, 2), "listColumn")
        var row = column === null ? null : Nest.first(column, "listRow")
        var quote = Nest.first(Nest.delegate(md, 3), "quoteRow")
        if (row === null || quote === null)
            return shell.check("no list row or quote row to measure", "nest fixture builds its list and quote")
        shell.fenceChecks(2, "listColumn", row.children[0].width + row.spacing, "a list item")
        shell.fenceChecks(3, "quoteRow", Nest.BAR_WIDTH + quote.spacing, "a quote")
        var bar = Nest.bars(quote)
        var quoteFence = Nest.first(quote, "fenceBox")
        var fenceEnd = quoteFence === null ? Infinity : Nest.at(quoteFence, quote).y + quoteFence.height
        shell.check(wrong(bar.length === 1 && Nest.near(bar[0].height, quote.height) && bar[0].height >= fenceEnd, bar.length + " bars, first " + (bar.length > 0 ? bar[0].height : 0) + " of " + quote.height + ", fence ends " + fenceEnd),
            "the quote's bar runs the height of its fence")
        for (var m = 4; m <= 5; m++) {
            var maths = Nest.formulas(Nest.delegate(md, m))
            shell.check(wrong(maths.length === 1 && maths[0].text.indexOf("<img") >= 0 && maths[0].text.indexOf("&#94;") < 0 && maths[0].text.indexOf("data-math") < 0,
                maths.length + " formulas, drawn only when an image stands in the line"), (m === 4 ? "an item" : "a quote") + "'s inline formula is drawn")
        }
        var tableQuote = Nest.delegate(md, 6)
        var grid = Nest.first(tableQuote, "tableGrid")
        var tableRow = Nest.first(tableQuote, "quoteRow")
        shell.check(wrong(grid !== null && Nest.near(Nest.at(grid, tableRow).x, Nest.BAR_WIDTH + tableRow.spacing), grid === null ? "no table grid" : "grid at " + Nest.at(grid, tableRow).x),
            "a table in a quote draws its grid inside the bar")
        shell.check(wrong(Nest.textsOf(tableQuote).indexOf("| - |") < 0, "the quote's text still holds the pipe table for Qt"), "a table in a quote leaves no pipe table for Qt to box")
        var itemQuote = Nest.delegate(md, 7)
        var itemColumn = Nest.first(itemQuote, "listColumn")
        var inner = itemColumn === null ? null : Nest.first(itemColumn, "quoteRow")
        var itemRow = itemColumn === null ? null : Nest.first(itemColumn, "listRow")
        var textColumn = itemRow === null ? 0 : itemRow.children[0].width + itemRow.spacing
        shell.check(wrong(inner !== null && Nest.near(Nest.at(inner, itemColumn).x, textColumn), inner === null ? "no quote inside the item" : "quote at " + Nest.at(inner, itemColumn).x + ", want " + textColumn),
            "a quote in an item starts at the item's text column")
        var code = Nest.delegate(md, 8)
        var codeRow = Nest.first(code, "quoteRow")
        var codeFence = Nest.first(code, "fenceBox")
        shell.check(wrong(codeFence !== null && Nest.near(Nest.at(codeFence, codeRow).x, Nest.BAR_WIDTH + codeRow.spacing), codeFence === null ? "indented code drew as text" : "fence at " + Nest.at(codeFence, codeRow).x),
            "indented code in a quote draws as a fence block inside the bar")
    }

    // An empty heading or quote builds nothing and has no height, so only the gaps the list puts between blocks stand between its neighbours.
    function emptyChecks() {
        var types = md.blockList.map(function (b) { return b.type + (b.text === "" ? "-empty" : "") }).join(",")
        shell.check(wrong(types === "run,heading-empty,quote-empty,run", types), "empty fixture block types")
        var heading = Nest.delegate(md, 1)
        var quote = Nest.delegate(md, 2)
        shell.check(wrong(heading.height === 0 && quote.height === 0 && heading.children.length === 1 && quote.children.length === 1,
            "heights " + heading.height + ", " + quote.height + "; children " + heading.children.length + ", " + quote.children.length), "an empty heading and an empty quote build nothing and stand no tall")
        var before = Nest.delegate(md, 0)
        var after = Nest.delegate(md, 3)
        var gap = after.y - (before.y + before.height)
        shell.check(wrong(Nest.near(gap, 3 * md.blockGap), "gap " + gap + ", want " + 3 * md.blockGap), "only the list's gaps stand between the blocks around them")
    }

    // Consecutive paragraphs are consecutive blocks: the gap after a maths line equals every other paragraph gap.
    function gapChecks() {
        var types = md.blockList.map(function (b) { return b.type }).join(",")
        shell.check(wrong(types === "run,run", types), "a maths line and its neighbour are consecutive runs")
        if (md.blockList.length !== 2)
            return
        var maths = Nest.formulas(Nest.delegate(md, 0))
        shell.check(wrong(maths.length === 1 && maths[0].text.indexOf("<img") >= 0, maths.length + " formulas"), "the maths line draws its formula")
        var plain = Nest.formulas(Nest.delegate(md, 1))
        shell.check(wrong(plain.length === 0, plain.length + " formulas"), "the neighbour draws no formula")
        var first = Nest.delegate(md, 0)
        var second = Nest.delegate(md, 1)
        var gap = second.y - first.y - first.height
        shell.check(wrong(Nest.near(gap, md.blockGap), "gap " + gap + ", want " + md.blockGap), "the gap after a maths line equals the block gap")
    }

    // A second text size: the preview column sets the document one token under Quick Look's, and a formula's run must follow it.
    function compactChecks() {
        var plainDelegate = Nest.delegate(md, 0)
        var plain = plainDelegate.children[plainDelegate.children.length - 1]
        var maths = Nest.formulas(Nest.delegate(md, 2))[0]
        var size = md.bodyPx
        shell.check(wrong(size !== shell.bodySize, "the compact size equals the theme body " + size), "the second text size differs from the theme body")
        shell.check(wrong(maths.box === plain.box && maths.box === Math.round(1.7 * size), "box " + maths.box + ", plain " + plain.box + ", want " + Math.round(1.7 * size)),
            "a run with maths keeps the plain run's line box at the second size")
        shell.check(wrong(maths.tallestPicture === 2 * maths.box && maths.font.pixelSize === size, "padding " + maths.tallestPicture + ", font " + maths.font.pixelSize),
            "a formula's picture padding follows the second size")
        shell.check(wrong(maths.bodyPx === size && plain.bodyPx === size, "bodyPx " + maths.bodyPx + " and " + plain.bodyPx + ", want " + size),
            "both runs carry the document's body size")
    }

    function drive() {
        if (shell.step < 0)
            return shell.start(0)
        if (!md.contentReady || md.loadRuns === shell.loadsMark || !shell.settled())
            return
        var name = shell.plan[shell.step]
        try {
            if (name === "nest")
                shell.nestChecks()
            else if (name === "empty")
                shell.emptyChecks()
            else if (name === "compact")
                shell.compactChecks()
            else
                shell.gapChecks()
        } catch (e) {
            return shell.finish("a check threw at " + name + ": " + e)
        }
        if (shell.step + 1 >= shell.plan.length)
            return shell.finish()
        shell.start(shell.step + 1)
    }

    Timer {
        interval: 100
        repeat: true
        running: !shell.done
        onTriggered: shell.drive()
    }

    readonly property int watchdogMs: 60000
    Timer {
        interval: shell.watchdogMs
        repeat: false
        running: !shell.done
        onTriggered: shell.finish("watchdog at step " + shell.step + " (" + shell.plan[Math.max(0, shell.step)] + "): ready " + md.contentReady
            + ", loads " + (md.loadRuns - shell.loadsMark) + ", blocks " + md.blockList.length + ", settled " + shell.settled())
    }
}
