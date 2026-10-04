import QtQuick
import "." as Flea
import "js/Icons.js" as Icons
import "js/Markdown.js" as Markdown

// The board's placeholder spans the content with a dashed muted box around a left-aligned muted image glyph and sentence on one line.
Item {
    id: root

    // The blocked image's host, which the sentence names.
    property string host: ""
    // RenderedPreviews' remote box is a 1 px CSS dashed border: 3 px dashes with 3 px gaps.
    readonly property int dashPx: 3
    readonly property int dashPitch: 2 * root.dashPx
    // The delegate sets the width; the dashes and the sentence follow it.
    height: remoteRow.implicitHeight + 2 * Theme.spacing.gap

    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: root.dashPx
        Repeater {
            model: Math.max(1, Math.floor((root.width + root.dashPx) / root.dashPitch))
            delegate: Rectangle { width: root.dashPx; height: Theme.spacing.hairline; color: Theme.color.muted }
        }
    }

    Row {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: root.dashPx
        Repeater {
            model: Math.max(1, Math.floor((root.width + root.dashPx) / root.dashPitch))
            delegate: Rectangle { width: root.dashPx; height: Theme.spacing.hairline; color: Theme.color.muted }
        }
    }

    Column {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        spacing: root.dashPx
        Repeater {
            model: Math.max(1, Math.floor((root.height + root.dashPx) / root.dashPitch))
            delegate: Rectangle { width: Theme.spacing.hairline; height: root.dashPx; color: Theme.color.muted }
        }
    }

    Column {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        spacing: root.dashPx
        Repeater {
            model: Math.max(1, Math.floor((root.height + root.dashPx) / root.dashPitch))
            delegate: Rectangle { width: Theme.spacing.hairline; height: root.dashPx; color: Theme.color.muted }
        }
    }

    Row {
        id: remoteRow
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing.gap
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.gap
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.gap

        Flea.Glyph {
            id: remoteMark
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.chromeMarkSize
            height: Theme.chromeMarkSize
            maxSize: Theme.chromeMarkSize
            name: Icons.glyphFor("image-x-generic")
            color: Theme.color.muted
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - remoteMark.width - parent.spacing
            text: Markdown.placeholder(root.host)
            color: Theme.color.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
    }
}
