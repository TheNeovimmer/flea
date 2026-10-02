import QtQuick
import "." as Flea
import "js/Icons.js" as Icons

// The Markdown bar and pane, loaded only for a Markdown file; a held picture covers the whole item.
Item {
    id: root

    property bool active: false
    property string path: ""
    property string iconName: ""
    property int size: 0
    property string view: "rendered"
    property int maxBytes: 1048576
    property bool truncate: false

    signal closeRequested

    readonly property var bodyItem: doc.bodyItem
    readonly property string rawText: doc.rawText
    readonly property string status: doc.status
    readonly property string lineLabel: doc.lineLabel
    readonly property bool contentReady: doc.contentReady
    readonly property bool loading: doc.loading
    readonly property bool blank: doc.blank

    Item {
        id: bar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 27

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.spacing.hairline
            color: Theme.color.muted
            opacity: 0.4
        }

        Flea.Glyph {
            id: barMark
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            maxSize: 16
            name: Icons.glyphFor(root.iconName)
            color: Theme.color.foreground
        }

        // corner: a filename is arbitrary text, so PlainText, the same rule every name on this surface follows.
        Text {
            id: barName
            anchors.left: barMark.right
            anchors.leftMargin: 9
            anchors.right: barLines.left
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: root.path.substring(root.path.lastIndexOf("/") + 1)
            color: Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
        }

        Text {
            id: barLines
            anchors.right: barSegment.left
            anchors.rightMargin: 9
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
            anchors.rightMargin: 9
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
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.hitMin
            height: parent.height
            glyphSize: Theme.font.caption
            glyph: "x"
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
    }
}
