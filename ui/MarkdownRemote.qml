import QtQuick
import QtQuick.Shapes
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

    // The dashes a side of this length holds, laid from its corner: the last one ends at the returned offset.
    // Sample input: 20 answers 15, three dashes at 0, 6 and 12 ending at 15.
    function dashEnd(length) {
        return (Math.max(1, Math.floor((length + root.dashPx) / root.dashPitch)) - 1) * root.dashPitch + root.dashPx
    }

    // The four sides as SVG subpaths, each dashing from its own corner and running half a stroke inside the box.
    // Sample input: (20, 10) with a 1 px hairline answers "M0 0.5 L15 0.5 M0 9.5 L15 9.5 M0.5 0 L0.5 9 M19.5 0 L19.5 9".
    function borderPath(w, h) {
        var half = Theme.spacing.hairline / 2
        var across = root.dashEnd(w)
        var down = root.dashEnd(h)
        return "M0 " + half + " L" + across + " " + half + " M0 " + (h - half) + " L" + across + " " + (h - half)
            + " M" + half + " 0 L" + half + " " + down + " M" + (w - half) + " 0 L" + (w - half) + " " + down
    }

    // One Shape draws all four sides, so a wide card builds a handful of objects instead of a Rectangle per dash.
    Shape {
        id: dashes
        anchors.fill: parent

        ShapePath {
            strokeColor: Theme.color.muted
            strokeWidth: Theme.spacing.hairline
            fillColor: "transparent"
            strokeStyle: ShapePath.DashLine
            // A dash is dashPx long in units of the stroke width, which the hairline sets.
            dashPattern: [root.dashPx / Theme.spacing.hairline, root.dashPx / Theme.spacing.hairline]
            capStyle: ShapePath.FlatCap
            PathSvg { path: root.borderPath(root.width, root.height) }
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
