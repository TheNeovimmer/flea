import QtQuick

// Exercise the real figure component against a recording ticket service; tests/figure-harness.py supplies the stub singletons.
Item {
    id: probe
    property int checks: 0
    property int failures: 0
    function check(passed, label) {
        probe.checks++;
        if (!passed) {
            probe.failures++;
            console.log("FAIL " + label);
        }
    }
    MarkdownFigure {
        id: figure
        inline: true
        source: "x^2"
        width: implicitWidth
    }
    Component.onCompleted: Qt.callLater(probe.flip)
    function flip() {
        FigureService.requests = [];
        figure.bgHex = "#111111";
        figure.fgHex = "#eeeeee";
        figure.accentHex = "#aabbcc";
        Qt.callLater(probe.verify);
    }
    function verify() {
        probe.check(FigureService.requests.length === 1, "theme flip requests=" + FigureService.requests.length + ", want 1");
        var finalTheme = FigureService.requests[0];
        probe.check(finalTheme && finalTheme.bg === figure.bgHex && finalTheme.fg === figure.fgHex
            && finalTheme.accent === figure.accentHex, "the coalesced request carries every final colour");
        FigureService.done(figure.ticket, "", "inline render failed");
        probe.check(figure.failed && figure.implicitWidth > 0 && figure.width === figure.implicitWidth,
            "failed inline implicitWidth=" + figure.implicitWidth + ", want a nonzero fence");
        console.log("figure-component: " + probe.checks + " check(s), " + probe.failures + " failed");
        Qt.quit();
    }
}
