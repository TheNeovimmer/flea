import QtQuick

// Figures keep their aspect ratio, fit the pane width, and fall back to source on failure.
Item {
    id: root

    property string kind: "math"
    property string source: ""
    property bool display: true
    property bool inline: false
    property string bgHex: "#101315"
    property string fgHex: "#c0caf5"
    property string accentHex: "#7aa2f7"
    property string mutedHex: ""
    property string surfaceHex: ""
    // The failed figure's fence sits on the code surface of the pane that holds it.
    property color fallbackColor: Theme.color.surface
    property string fontFamily: Theme.font.family
    property int bodyPx: Theme.font.body

    readonly property bool failed: root.error !== ""
    readonly property bool ready: root.svg !== ""
    readonly property bool working: root.ticket > 0
    property string svg: ""
    property string error: ""
    property int ticket: 0
    // The Source view sends no figure requests.
    property bool askArmed: true
    // Offscreen delegates retain settled figures and send no requests.
    property bool inView: true

    function hexTheme() {
        return { bg: root.bgHex, fg: root.fgHex, accent: root.accentHex,
            font: root.fontFamily, bodyPx: root.bodyPx,
            muted: root.mutedHex, surface: root.surfaceHex };
    }
    function ask() {
        // Offscreen property changes invalidate the settled figure until it enters the viewport.
        if (!root.askArmed || root.source === "" || !root.inView) {
            root.ticket = 0;
            root.svg = "";
            root.error = "";
            return;
        }
        root.ticket = FigureService.ask(root.kind, root.source,
            root.display, root.hexTheme());
    }

    onKindChanged: askTimer.restart()
    onSourceChanged: askTimer.restart()
    onDisplayChanged: askTimer.restart()
    onBgHexChanged: askTimer.restart()
    onFgHexChanged: askTimer.restart()
    onAccentHexChanged: askTimer.restart()
    onMutedHexChanged: askTimer.restart()
    onSurfaceHexChanged: askTimer.restart()
    onFontFamilyChanged: askTimer.restart()
    onBodyPxChanged: askTimer.restart()
    onAskArmedChanged: askTimer.restart()
    // Entering the viewport requests an unsettled figure after layout.
    onInViewChanged: if (root.inView && root.askArmed && root.source !== "" && root.ticket === 0 && root.svg === "" && root.error === "") root.ask()
    Component.onCompleted: askTimer.restart()

    // Coalesce property changes until layout places the delegate in its viewport.
    Timer {
        id: askTimer
        interval: 50
        onTriggered: root.ask()
    }

    Connections {
        target: FigureService
        function onDone(ticket, svg, error) {
            if (ticket !== root.ticket)
                return;
            root.ticket = 0;
            if (svg !== "") {
                root.svg = svg;
                root.error = "";
            } else {
                root.svg = "";
                root.error = error;
            }
        }
    }

    // Data URLs deliver figures to Qt SVG without filesystem writes.
    readonly property string dataUrl: root.svg === "" ? ""
        : "data:image/svg+xml," + encodeURIComponent(root.svg)

    Image {
        id: figure
        visible: !root.inline && root.svg !== ""
        anchors.top: parent.top
        anchors.left: root.centred ? undefined : parent.left
        anchors.horizontalCenter: root.centred ? parent.horizontalCenter : undefined
        source: root.dataUrl
        cache: false
        asynchronous: true
        width: root.fitWidth
        height: root.fitHeight
        fillMode: Image.PreserveAspectFit
    }

    // An inline formula beside text: line height tall, aspect kept.
    Image {
        id: inlineFigure
        visible: root.inline && root.svg !== ""
        anchors.top: parent.top
        source: root.dataUrl
        cache: false
        asynchronous: true
        height: root.bodyPx
        width: root.inlineWidth
        fillMode: Image.PreserveAspectFit
    }

    // A failed figure draws bounded source on the code surface.
    readonly property string fallbackBody: root.source.length > 2000
        ? root.source.slice(0, 2000) + "… (" + (root.source.length - 2000) + " more)"
        : root.source
    Rectangle {
        id: fallback
        visible: root.failed
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: fallbackItem.implicitHeight + 2 * Theme.spacing.gap
        color: root.fallbackColor
        Text {
            id: fallbackItem
            anchors.fill: parent
            anchors.margins: Theme.spacing.gap
            text: root.fallbackBody
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.color.foreground
            font.family: root.fontFamily
            font.pixelSize: root.bodyPx
        }
    }

    readonly property bool centred: root.kind === "math" && root.display && !root.inline
    readonly property real naturalWidth: !root.inline && figure.implicitWidth > 0 ? figure.implicitWidth : 0
    readonly property real naturalHeight: !root.inline && figure.implicitHeight > 0 ? figure.implicitHeight : 0
    // Integer geometry keeps the raster 1:1: a fractional item size would resample the whole figure and blend every flat fill.
    readonly property real fitWidth: root.naturalWidth <= 0 ? 0 : Math.round(Math.min(root.naturalWidth, root.width))
    readonly property real fitHeight: root.naturalWidth <= 0 ? 0 : Math.round(root.naturalHeight * (root.fitWidth / root.naturalWidth))
    readonly property real inlineWidth: root.inline && inlineFigure.implicitHeight > 0
        ? Math.round(inlineFigure.implicitWidth * (root.bodyPx / inlineFigure.implicitHeight)) : 0

    implicitWidth: root.inline ? root.inlineWidth : root.width
    // A failed inline still draws its fence, so it sizes to the fence rather than the line it never became.
    implicitHeight: root.inline ? (root.failed ? fallback.height : root.bodyPx)
        : root.failed ? fallback.height : root.fitHeight
    height: root.implicitHeight
}
