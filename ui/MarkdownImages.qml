import QtQuick

// A row of local images from one HTML block, wrapped at the pane width with each line centred or left, every image keeping its own link.
Item {
    id: root

    // Each image as the parser hands it: { url, alt, width (optional), link (optional) }.
    property var images: []
    property bool centred: false
    // The space between neighbours on a line and between lines.
    property int gap: 0
    // The pane's scheme gate for a link around an image, as MarkdownText takes one.
    property var linkGate: null

    // One { x, y } per image and the total height, read from the sizes the images report as they decode.
    readonly property var arrangement: root.arrange(strip.count, root.width)
    height: root.arrangement.height

    // Sample input: three images 40, 40 and 90 wide on a 100 wide pane with gap 4 make two lines, the first 84 wide and the third alone.
    function arrange(count, limit) {
        var places = []
        var y = 0
        var from = 0
        while (from < count) {
            var to = from
            var used = 0
            var tall = 0
            while (to < count) {
                var pic = strip.itemAt(to)
                var w = pic ? pic.width : 0
                if (to > from && used + root.gap + w > limit)
                    break
                used += (to > from ? root.gap : 0) + w
                tall = Math.max(tall, pic ? pic.height : 0)
                to++
            }
            var x = root.centred ? Math.round((limit - used) / 2) : 0
            for (var k = from; k < to; k++) {
                var one = strip.itemAt(k)
                places.push({ x: x, y: y + tall - (one ? one.height : 0) })
                x += (one ? one.width : 0) + root.gap
            }
            y += tall + root.gap
            from = to
        }
        return { places: places, height: Math.max(0, y - root.gap) }
    }

    Repeater {
        id: strip
        model: root.images.length
        delegate: Image {
            id: pic
            readonly property var spec: root.images[index]
            // An HTML width attribute sets the picture's width, else it keeps its own, never wider than the pane; the height keeps the picture's ratio.
            readonly property real fitWidth: Math.min(pic.spec.width > 0 ? pic.spec.width : pic.implicitWidth, root.width)
            width: pic.fitWidth
            height: pic.implicitWidth > 0 ? pic.fitWidth * pic.implicitHeight / pic.implicitWidth : 0
            x: index < root.arrangement.places.length ? root.arrangement.places[index].x : 0
            y: index < root.arrangement.places.length ? root.arrangement.places[index].y : 0
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            autoTransform: true
            source: pic.spec.url

            // A badge wrapped in a link opens it through the pane's link gate.
            TapHandler { enabled: pic.spec.link !== undefined; gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: if (root.linkGate !== null && root.linkGate(pic.spec.link)) Qt.openUrlExternally(pic.spec.link) }
            HoverHandler { enabled: pic.spec.link !== undefined; cursorShape: Qt.PointingHandCursor }
        }
    }
}
