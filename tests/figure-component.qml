import QtQuick
import "markdown-board.js" as Board

// Exercise the real figure component against a recording ticket service; tests/figure-harness.py supplies the stub singletons.
Item {
    id: probe
    property int checks: 0
    property int failures: 0
    // A fence pads its text on the left and on the right.
    readonly property int fenceSides: 2
    function check(passed, label) {
        probe.checks++;
        if (!passed) {
            probe.failures++;
            console.log("FAIL " + label);
        }
    }
    // The same text a failed inline figure fences, measured with no width bound to it.
    Text {
        id: measure
        visible: false
        text: figure.fallbackBody
        textFormat: Text.PlainText
        font.family: figure.fontFamily
        font.pixelSize: figure.bodyPx
    }
    MarkdownFigure {
        id: figure
        inline: true
        source: "x^2"
        bgHex: "#202020"
        fgHex: "#dddddd"
        accentHex: "#445566"
        width: 300
    }
    // A diagram asks nothing until its stage arms it, so the counts of the stages before it stay exact.
    MarkdownFigure {
        id: diagram
        kind: "mermaid"
        source: "A --> B"
        fontFamily: "sans-serif"
        bodyPx: 14
        askArmed: false
        width: 300
    }
    // A figure whose request the service already holds, and one it does not.
    Component {
        id: heldComponent
        MarkdownFigure {
            inline: true
            bgHex: "#202020"
            fgHex: "#dddddd"
            accentHex: "#445566"
            width: 300
        }
    }
    // The advance of one character by an independent ruler, regular or bold, in thousandths of an em.
    readonly property int tableFirst: 32
    readonly property int tableLength: 95
    readonly property int thousand: 1000
    TextMetrics {
        id: ruler
        font.family: diagram.fontFamily
        font.pixelSize: diagram.bodyPx
    }
    function rulerAdvance(code, bold) {
        ruler.font.bold = bold;
        ruler.text = String.fromCharCode(code);
        return ruler.advanceWidth / diagram.bodyPx * probe.thousand;
    }
    // A measured advance matches the ruler's to a thousandth of an em plus the table's own rounding.
    readonly property real advanceTolerance: 1
    // Each stage verifies after the figure's next ask run, or at once when it queued none, so no stage times a wait.
    property int stage: 0
    readonly property var stages: [probe.created, probe.verify, probe.verifyDrop, probe.verifyHeld,
        probe.verifyQuiet, probe.verifySent, probe.verifyAdvance]
    Connections {
        target: figure
        function onAskRunsChanged() {
            Qt.callLater(probe.next);
        }
    }
    // The diagram's ask runs count only once its stage armed it; its creation run answers nothing.
    property bool diagramArmed: false
    Connections {
        target: diagram
        function onAskRunsChanged() {
            if (probe.diagramArmed)
                Qt.callLater(probe.next);
        }
    }
    // A stage that queued an ask waits for its run; one that queued none verifies on the next turn.
    function wait(queued) {
        if (!queued)
            Qt.callLater(probe.next);
    }
    function next() {
        probe.stages[probe.stage++]();
    }
    function created() {
        probe.check(FigureService.requests.length === 1, "creation requests=" + FigureService.requests.length + ", want 1");
        probe.check(FigureService.requests.length > 0 && FigureService.requests[0].bg === "#202020",
            "the creation request carries the colours the figure was created with");
        FigureService.requests = [];
        figure.bgHex = "#111111";
        figure.fgHex = "#eeeeee";
        figure.accentHex = "#aabbcc";
        figure.fontFamily = "sans-serif";
        figure.bodyPx = 15;
        probe.wait(true);
    }
    function verify() {
        probe.check(FigureService.requests.length === 1, "theme flip requests=" + FigureService.requests.length + ", want 1");
        var finalTheme = FigureService.requests[0];
        probe.check(finalTheme && finalTheme.bg === figure.bgHex && finalTheme.fg === figure.fgHex
            && finalTheme.accent === figure.accentHex && finalTheme.font === figure.fontFamily
            && finalTheme.bodyPx === figure.bodyPx, "the coalesced request carries every final colour and font");
        FigureService.requests = [];
        figure.bgHex = "#333333";
        figure.bgHex = "#111111";
        probe.wait(true);
    }
    function verifyDrop() {
        probe.check(FigureService.requests.length === 0, "an ask equal to the last request sent requests=" + FigureService.requests.length + ", want 0");
        // A figure still being built schedules nothing, so a change made before creation completes costs no request.
        figure.created = false;
        figure.bgHex = "#444444";
        probe.wait(false);
    }
    function verifyHeld() {
        probe.check(FigureService.requests.length === 0 && !figure.askPending,
            "a change before creation completes requests=" + FigureService.requests.length + " armed=" + figure.askPending + ", want 0 and not armed");
        figure.created = true;
        probe.wait(false);
    }
    function verifyQuiet() {
        probe.check(FigureService.requests.length === 0 && !figure.askPending,
            "setting created back requests=" + FigureService.requests.length + " armed=" + figure.askPending + ", want 0 and not armed");
        // The control: the same kind of change on a created figure does ask, so the zeros above are the guard's.
        figure.bgHex = "#555555";
        probe.wait(true);
    }
    function verifySent() {
        probe.check(FigureService.requests.length === 1 && FigureService.requests[0].bg === "#555555",
            "a change on a created figure requests=" + FigureService.requests.length + ", want 1 carrying #555555");
        probe.check((FigureService.requests[0].advances || []).length === 0 && (FigureService.requests[0].boldAdvances || []).length === 0, "a formula request carries no advance table");
        FigureService.done(figure.ticket, "", "inline render failed");
        // The host hands the figure the preview's fence pad; the board's 12 at this body is what it is handed.
        var fencePadX = Board.boardPx(Board.BOARD_FENCE_PAD_X, figure.bodyPx);
        figure.fencePadX = fencePadX;
        var want = measure.implicitWidth + probe.fenceSides * fencePadX;
        probe.check(figure.failed && measure.implicitWidth > 0 && figure.implicitWidth === want,
            "failed inline implicitWidth=" + figure.implicitWidth + ", want " + want + " (text " + measure.implicitWidth + " plus two fence pads of " + fencePadX + ")");
        FigureService.requests = [];
        probe.diagramArmed = true;
        diagram.askArmed = true;
        probe.wait(true);
    }
    // The table's worst distance from the ruler, and how many of its entries differ from the other weight's table.
    function worstGap(table, bold) {
        var worst = 0;
        for (var i = 0; i < probe.tableLength; i++)
            worst = Math.max(worst, Math.abs(table[i] - probe.rulerAdvance(probe.tableFirst + i, bold)));
        return worst;
    }
    function differing(a, b) {
        var count = 0;
        for (var i = 0; i < probe.tableLength; i++)
            count += a[i] !== b[i] ? 1 : 0;
        return count;
    }
    function verifyAdvance() {
        var theme = FigureService.requests.length === 1 ? FigureService.requests[0] : {};
        var regular = theme.advances || [];
        var bold = theme.boldAdvances || [];
        probe.check(regular.length === probe.tableLength && bold.length === probe.tableLength,
            "a diagram request carries a table of " + probe.tableLength + " advances, regular " + regular.length + " and bold " + bold.length);
        if (regular.length !== probe.tableLength || bold.length !== probe.tableLength) {
            probe.finish();
            return;
        }
        var regularGap = probe.worstGap(regular, false);
        var boldGap = probe.worstGap(bold, true);
        probe.check(regularGap < probe.advanceTolerance, "every regular advance is the ruler's, worst gap " + regularGap + " thousandths");
        probe.check(boldGap < probe.advanceTolerance, "every bold advance is the bold ruler's, worst gap " + boldGap + " thousandths");
        // The face must be one whose bold advances differ from its regular ones, or the bold gap above could not tell the two tables apart.
        var rulerBold = regular.map(function (v, i) { return Math.round(probe.rulerAdvance(probe.tableFirst + i, true)); });
        var differs = probe.differing(regular, rulerBold);
        probe.check(differs > 0, "the face's bold advances differ from its regular ones in " + differs + " of " + probe.tableLength + " entries");
        probe.verifyHeldAnswer();
        probe.finish();
    }
    // A formula typeset ahead is drawn the moment its figure is created, and sends nothing; a formula the service does not hold asks as always.
    function verifyHeldAnswer() {
        FigureService.requests = [];
        var held = heldComponent.createObject(probe, { source: "held^1" });
        probe.check(held.svg === "<svg/>" && held.ready, "a held formula is drawn at creation svg=" + held.svg);
        probe.check(!held.askPending && FigureService.requests.length === 0, "a held formula asks nothing armed=" + held.askPending + " requests=" + FigureService.requests.length);
        var fresh = heldComponent.createObject(probe, { source: "fresh^2" });
        probe.check(fresh.svg === "" && fresh.askPending, "a formula the service does not hold waits to ask svg=" + fresh.svg + " armed=" + fresh.askPending);
        probe.check(held.ticket === 0 && held.lastRequest !== "", "a held formula takes no ticket and remembers its request");
        // A request still in flight when the figure changes to a held one never lands over the held drawing.
        var late = heldComponent.createObject(probe, { source: "fresh^3" });
        late.ask();
        var inflight = late.ticket;
        late.source = "held^1";
        FigureService.done(inflight, "<svg id=\"late\"/>", "");
        probe.check(inflight > 0 && late.svg === "<svg/>", "a reply in flight landed over the held drawing svg=" + late.svg);
        probe.check(!late.working && !late.askPending, "a held drawing leaves a request working=" + late.working + " armed=" + late.askPending);
    }
    function finish() {
        console.log("figure-component: " + probe.checks + " check(s), " + probe.failures + " failed");
        Qt.quit();
    }
}
