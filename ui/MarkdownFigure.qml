import QtQuick

// One rendered figure: the helper's SVG at its aspect ratio within the pane width, or fenced source when rendering fails.
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
    // The body font's x-height at bodyPx: a display formula draws its ex at this height, so maths and prose letters stand level.
    property real xHeight: bodyMetrics.xHeight
    // The helper receives the x-height in hundredths of a pixel, so a font that settles late changes the request.
    readonly property int xHeightRounding: 100

    FontMetrics {
        id: bodyMetrics
        font.family: root.fontFamily
        font.pixelSize: root.bodyPx
    }

    // A diagram sizes labels by the font's em advance, the mean over printable ASCII, exact for monospace; maths sends none.
    readonly property string advanceSample: " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    // The helper receives the advances in thousandths of an em, so a font that settles late changes the request.
    readonly property int advanceRounding: 1000
    property real advance: root.kind !== "mermaid" ? 0 : Math.round(regularAdvance.advanceWidth / (root.advanceSample.length * root.bodyPx) * root.advanceRounding) / root.advanceRounding
    property real boldAdvance: root.kind !== "mermaid" ? 0 : Math.round(boldedAdvance.advanceWidth / (root.advanceSample.length * root.bodyPx) * root.advanceRounding) / root.advanceRounding
    TextMetrics {
        id: regularAdvance
        font.family: root.fontFamily
        font.pixelSize: root.bodyPx
        text: root.kind === "mermaid" ? root.advanceSample : ""
    }
    TextMetrics {
        id: boldedAdvance
        font.family: root.fontFamily
        font.pixelSize: root.bodyPx
        font.bold: true
        text: root.kind === "mermaid" ? root.advanceSample : ""
    }

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
            exPx: Math.round(root.xHeight * root.xHeightRounding) / root.xHeightRounding,
            advance: root.advance, boldAdvance: root.boldAdvance,
            muted: root.mutedHex, surface: root.surfaceHex };
    }
    // Nothing is asked until the figure is created, so its construction-time assignments cost no request.
    property bool created: false
    // The request this figure last sent; an ask for the same state is dropped, so a burst of changes renders once.
    property string lastRequest: ""
    function ask() {
        root.askRuns++;
        // Offscreen property changes invalidate the settled figure until it enters the viewport.
        if (!root.askArmed || root.source === "" || !root.inView) {
            root.ticket = 0;
            root.svg = "";
            root.error = "";
            root.lastRequest = "";
            return;
        }
        var theme = root.hexTheme();
        var request = JSON.stringify([root.kind, root.source, root.display, theme]);
        if (request === root.lastRequest)
            return;
        root.lastRequest = request;
        root.ticket = FigureService.ask(root.kind, root.source, root.display, theme);
    }
    // The wait, in ms, that lets the list lay the delegate out before the one ask reads its place.
    readonly property int askSettleMs: 50
    // The suite counts ask runs and reads the armed deferred ask, so it waits and asserts without timing.
    property int askRuns: 0
    readonly property bool askPending: askTimer.running
    // Every property change lands on the one deferred ask, so the changes of one burst send one request.
    function schedule() {
        if (root.created)
            askTimer.restart();
    }

    onKindChanged: root.schedule()
    onSourceChanged: root.schedule()
    onDisplayChanged: root.schedule()
    onBgHexChanged: root.schedule()
    onFgHexChanged: root.schedule()
    onAccentHexChanged: root.schedule()
    onMutedHexChanged: root.schedule()
    onSurfaceHexChanged: root.schedule()
    onFontFamilyChanged: root.schedule()
    onBodyPxChanged: root.schedule()
    onXHeightChanged: root.schedule()
    onAdvanceChanged: root.schedule()
    onBoldAdvanceChanged: root.schedule()
    onAskArmedChanged: root.schedule()
    // Entering the viewport requests an unsettled figure after layout.
    onInViewChanged: if (root.created && root.inView && root.askArmed && root.source !== "" && root.ticket === 0 && root.svg === "" && root.error === "") root.ask()
    Component.onCompleted: {
        root.created = true;
        root.schedule();
    }

    // ListView places the delegate after it completes, so the one ask waits out layout and inView reads the placed position.
    Timer {
        id: askTimer
        interval: root.askSettleMs
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
    readonly property int fallbackChars: 2000
    readonly property string fallbackBody: root.source.length > root.fallbackChars
        ? root.source.slice(0, root.fallbackChars) + "… (" + (root.source.length - root.fallbackChars) + " more)"
        : root.source
    // The fence pads every edge by one gap, so a width or a height adds both of its sides.
    readonly property real fencePadding: Theme.spacing.gap
    readonly property real fenceBothSides: fallbackItem.anchors.leftMargin + fallbackItem.anchors.rightMargin
    Rectangle {
        id: fallback
        visible: root.failed
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: fallbackItem.implicitHeight + root.fenceBothSides
        color: root.fallbackColor
        Text {
            id: fallbackItem
            anchors.fill: parent
            anchors.margins: root.fencePadding
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

    implicitWidth: root.inline ? (root.failed ? fallbackItem.implicitWidth + root.fenceBothSides : root.inlineWidth) : root.width
    // A failed inline still draws its fence, so it sizes to the fence rather than the line it never became.
    implicitHeight: root.inline ? (root.failed ? fallback.height : root.bodyPx)
        : root.failed ? fallback.height : root.fitHeight
    height: root.implicitHeight
}
