import QtQuick
import "js/MarkdownPictures.js" as Pictures

// The pictures one Markdown text holds: their natural sizes from hidden images, and the text with the wide ones scaled to its width; ui/MarkdownText.qml builds it for a text with a picture only.
Item {
    id: root

    required property MarkdownText host

    readonly property var urls: Pictures.urls(root.host.markdown)
    // Each decoded picture's natural size by address; count and implicitWidth notify when an image arrives and loads.
    readonly property var sizes: {
        var found = ({})
        for (var i = 0; i < gallery.count; i++) {
            var image = gallery.itemAt(i)
            if (image && image.implicitWidth > 0)
                found[root.urls[i]] = { w: image.implicitWidth, h: image.implicitHeight }
        }
        return found
    }
    readonly property var fitted: Pictures.fit(root.host.markdown, root.sizes, Math.floor(root.host.width - root.host.leftPadding - root.host.rightPadding))
    // The text to draw, and the tallest picture in it as it draws, 0 until one is decoded.
    readonly property string shown: root.fitted.text
    readonly property real tallest: root.fitted.tallest

    Repeater {
        id: gallery
        model: root.urls
        delegate: Image {
            required property string modelData
            visible: false
            asynchronous: true
            source: modelData
        }
    }
}
