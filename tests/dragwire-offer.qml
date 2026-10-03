import QtQuick

Item {
    Component.onCompleted: {
        // Sample argv: qml6 tests/dragwire-offer.qml -- /tmp/FileDrag.qml.
        var args = Qt.application.arguments
        var separator = args.indexOf("--")
        var path = separator >= 0 ? args[separator + 1] : "../ui/FileDrag.qml"
        var component = Qt.createComponent(Qt.resolvedUrl(path))
        if (component.status !== Component.Ready) {
            console.log("FAIL file offer component: " + component.errorString())
            Qt.exit(1)
            return
        }
        var drag = component.createObject(null, { pane: null })
        if (!drag) {
            console.log("FAIL file offer instance: " + component.errorString())
            Qt.exit(1)
            return
        }
        var cases = [
            ["plain", false, false, false, Qt.CopyAction],
            ["ctrl", false, true, false, Qt.CopyAction],
            ["shift", false, false, true, Qt.MoveAction],
            ["ctrl plus shift without link", false, true, true, Qt.CopyAction],
            ["ctrl with shift", true, true, true, Qt.LinkAction]
        ]
        var failed = 0
        for (var i = 0; i < cases.length; i++) {
            var test = cases[i]
            drag.dragLink = test[1]
            drag.dragCopy = test[2]
            drag.dragShift = test[3]
            var actual = drag.Drag.supportedActions
            if (actual !== test[4]) {
                failed++
                console.log("FAIL " + test[0] + " file offer: got " + actual + ", expected " + test[4])
            }
        }
        drag.destroy()
        console.log("file offers: " + cases.length + " checks, " + failed + " failed")
        Qt.exit(failed > 0 ? 1 : 0)
    }
}
