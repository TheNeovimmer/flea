import QtQuick

// One rendered figure: the helper's SVG, or fenced source when rendering fails.
Item {
    id: root

    property string kind: "math"
    property string source: ""
    property bool display: true
    property bool inline: false
    property string bgHex: "#101315"
    property string fgHex: "#c0caf5"
    property string accentHex: "#7aa2f7"
    property string fontFamily: Theme.font.family
    property int bodyPx: Theme.font.body

    readonly property bool failed: root.error !== ""
    readonly property bool ready: root.svg !== ""
    readonly property bool working: root.ticket > 0
    property string svg: ""
    property string error: ""
    property int ticket: 0

    function hexTheme() {
        return { bg: root.bgHex, fg: root.fgHex, accent: root.accentHex,
            font: root.fontFamily, bodyPx: root.bodyPx };
    }
    // Nothing is asked until the figure is created, so its construction-time assignments cost no request.
    property bool created: false
    // The request this figure last sent; an ask for the same state is dropped, so a burst of changes renders once.
    property string lastRequest: ""
    function ask() {
        if (root.source === "") {
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
    // Every trigger lands on the one deferred ask, so the changes of one burst send one request.
    function schedule() {
        if (root.created)
            Qt.callLater(root.ask);
    }

    onKindChanged: root.schedule()
    onSourceChanged: root.schedule()
    onDisplayChanged: root.schedule()
    onBgHexChanged: root.schedule()
    onFgHexChanged: root.schedule()
    onAccentHexChanged: root.schedule()
    onFontFamilyChanged: root.schedule()
    onBodyPxChanged: root.schedule()
    Component.onCompleted: {
        root.created = true;
        root.schedule();
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

    // Data URLs keep figures out of the filesystem entirely; Qt SVG takes them through Image like any other URL (proven in tests/markdown-figures).
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

    // The board's fenced block: chrome surface, plain source text. A refused source many kilobytes long elides to its head, so one fallback can never size the column past what a frame can hold.
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
        color: Theme.color.surface
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
