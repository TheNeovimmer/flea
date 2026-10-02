import QtQuick
import "." as Flea

// RenderedPreviews: the Markdown bar and pane, loaded only for a Markdown file,
// so a window that never shows one never compiles them. The bar is the board's
// own and the PDF viewer's grammar: the Markdown mark, the name, its line count
// right after it, the settings strip's segmented control at 20 px, and close.
// A held picture covers the whole item.
Item {
    id: root

    property bool active: false
    property string path: ""
    property int size: 0
    property string view: "rendered"
    property int maxBytes: 1048576
    property bool truncate: false

    signal closeRequested

    readonly property var bodyItem: doc.bodyItem
    readonly property string rawText: doc.rawText
    readonly property string status: doc.status
    readonly property string lineLabel: doc.lineLabel
    // Quick Look's seam reads figures through this pane, so it forwards the document's blocks.
    readonly property var blockList: doc.blockList
    function figureInfo(i) { return doc.figureInfo(i) }
    function blockItem(i) { return doc.blockItem(i) }
    readonly property bool contentReady: doc.contentReady
    readonly property bool loading: doc.loading
    readonly property bool blank: doc.blank
    // The page is the chrome surface, so code sits on the window colour (md_rendered code_bg).
    readonly property color codeSurface: doc.codeSurface

    // The render suite reads the bar's order off these rects, the way PdfViewer.buttonFor opens its buttons.
    function barGeometry() {
        return { mark: barMark, markName: barMark.name, name: barName, nameEnd: barName.x + Math.min(barName.width, barName.implicitWidth),
            lines: barLines, segment: barSegment, close: barClose, height: bar.height, ready: root.contentReady }
    }

    // No fill of its own: Quick Look's surface is already the chrome colour and rounds the corners this bar sits under.
    Item {
        id: bar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.chromeHeight

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.spacing.hairline
            color: Theme.color.foreground
            opacity: 0.12
        }

        // The Markdown mark of the LanguageMarks set, in foreground like the PDF viewer's kind mark.
        Flea.Glyph {
            id: barMark
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacing.rowPaddingX
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.chromeMarkSize
            height: Theme.chromeMarkSize
            name: "markdown"
            color: Theme.color.foreground
        }

        // corner: a filename is arbitrary text, so PlainText, the same rule every name on this surface follows.
        Text {
            id: barName
            anchors.left: barMark.right
            anchors.leftMargin: Theme.spacing.gap
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, barSegment.x - x - 2 * Theme.spacing.gap
                - (barLines.visible ? barLines.implicitWidth : 0)))
            text: root.path.substring(root.path.lastIndexOf("/") + 1)
            color: Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
        }

        Text {
            id: barLines
            anchors.left: barName.right
            anchors.leftMargin: Theme.spacing.gap
            anchors.verticalCenter: parent.verticalCenter
            text: root.lineLabel
            visible: root.contentReady
            color: Theme.color.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            textFormat: Text.PlainText
        }

        Flea.SettingsSegment {
            id: barSegment
            anchors.right: barClose.left
            anchors.rightMargin: Theme.spacing.gap
            anchors.verticalCenter: parent.verticalCenter
            options: ["Rendered", "Source"]
            value: ViewState.markdownView === "source" ? "Source" : "Rendered"
            controlHeight: 20
            onPicked: function (index) {
                ViewState.changeLeaf("preview", { markdownView: index === 0 ? "rendered" : "source" })
            }
        }

        Flea.ChromeButton {
            id: barClose
            gesturePolicy: TapHandler.ReleaseWithinBounds
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacing.rowPaddingX
            anchors.verticalCenter: parent.verticalCenter
            glyph: "x"
            accessName: "Close"
            onActivated: root.closeRequested()
        }
    }

    Flea.PreviewMarkdown {
        id: doc
        anchors.fill: parent
        anchors.topMargin: bar.height
        active: root.active
        view: root.view
        path: root.path
        size: root.size
        maxBytes: root.maxBytes
        truncate: root.truncate
        codeSurface: Theme.color.background
    }
}
