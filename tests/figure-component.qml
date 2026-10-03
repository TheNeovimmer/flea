import QtQuick

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
    // Two hops of Qt.callLater put every deferred ask queued during creation ahead of the first check.
    Component.onCompleted: Qt.callLater(probe.hop)
    function hop() {
        Qt.callLater(probe.created);
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
        Qt.callLater(probe.verify);
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
        Qt.callLater(probe.verifyDrop);
    }
    function verifyDrop() {
        probe.check(FigureService.requests.length === 0, "an ask equal to the last request sent requests=" + FigureService.requests.length + ", want 0");
        // A figure still being built schedules nothing, so a change made before creation completes costs no request.
        figure.created = false;
        figure.bgHex = "#444444";
        Qt.callLater(probe.verifyHeld);
    }
    function verifyHeld() {
        probe.check(FigureService.requests.length === 0, "a change before creation completes requests=" + FigureService.requests.length + ", want 0");
        figure.created = true;
        Qt.callLater(probe.verifyQuiet);
    }
    function verifyQuiet() {
        probe.check(FigureService.requests.length === 0, "setting created back requests=" + FigureService.requests.length + ", want 0");
        // The control: the same kind of change on a created figure does ask, so the zeros above are the guard's.
        figure.bgHex = "#555555";
        Qt.callLater(probe.verifySent);
    }
    function verifySent() {
        probe.check(FigureService.requests.length === 1 && FigureService.requests[0].bg === "#555555",
            "a change on a created figure requests=" + FigureService.requests.length + ", want 1 carrying #555555");
        FigureService.done(figure.ticket, "", "inline render failed");
        var gap = Theme.spacing.gap;
        var want = measure.implicitWidth + probe.fenceSides * gap;
        probe.check(figure.failed && measure.implicitWidth > 0 && figure.implicitWidth === want,
            "failed inline implicitWidth=" + figure.implicitWidth + ", want " + want + " (text " + measure.implicitWidth + " plus two gaps of " + gap + ")");
        console.log("figure-component: " + probe.checks + " check(s), " + probe.failures + " failed");
        Qt.quit();
    }
}
