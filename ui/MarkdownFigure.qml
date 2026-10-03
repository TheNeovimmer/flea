import QtQuick

// One rendered figure: a maths formula or a Mermaid diagram, drawn from the SVG the shared figure worker answers. Block mode sizes to the natural size, scales down to fit the width and never up; a display formula centres, a diagram sits left like a fenced block. Inline mode sizes to the line height for $...$ beside text. Pending reserves no height and draws nothing; an error draws the source as the board's fenced block, so a figure is never worse than the code it came from.
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
    function ask() {
        if (root.source === "") {
            root.ticket = 0;
            root.svg = "";
            root.error = "";
            return;
        }
        root.ticket = FigureService.ask(root.kind, root.source,
            root.display, root.hexTheme());
    }

    onKindChanged: root.ask()
    onSourceChanged: root.ask()
    onDisplayChanged: root.ask()
    onBgHexChanged: root.ask()
    onFgHexChanged: root.ask()
    onAccentHexChanged: root.ask()
    onFontFamilyChanged: root.ask()
    onBodyPxChanged: root.ask()
    Component.onCompleted: root.ask()

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
    Rectangle {
        id: fallback
        visible: root.failed
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: fallbackItem.implicitHeight + 2 * Theme.spacing.gap
        color: Theme.color.surface
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
