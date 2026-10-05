// Bound: the hidden images read this helper's root to note their sizes, and only its own Repeater builds them.
pragma ComponentBehavior: Bound
import QtQuick
import "js/MarkdownPictures.js" as Pictures

// The pictures one Markdown text holds: their natural sizes from hidden images, and the text with the wide ones scaled to its width; ui/MarkdownText.qml builds it for a text with a picture only.
Item {
    id: root

    required property MarkdownText host

    readonly property var urls: Pictures.urls(root.host.markdown)
    // Each decoded picture's natural size by address, kept after the hidden Image releases its own copy.
    property var known: ({})
    // One address is noted once; replacing the map notifies the sizes below, which a mutated key never does.
    function noteSize(url, w, h) {
        if (root.known[url] !== undefined)
            return
        var next = {}
        for (var key in root.known)
            next[key] = root.known[key]
        next[url] = { w: w, h: h }
        root.known = next
    }
    readonly property var sizes: root.known
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
            // An address loads only until its size is known, so no decoded copy outlives the note.
            source: root.known[modelData] === undefined ? modelData : ""
            onStatusChanged: if (status === Image.Ready && implicitWidth > 0) root.noteSize(modelData, implicitWidth, implicitHeight)
        }
    }
}
