import QtQuick
import "selection" as Selection

// Controlled replies keep the production selection component's asynchronous boundaries explicit.
Item {
    id: root
    property int checks: 0
    property int failures: 0
    readonly property int regularFileMode: 33188
    property var requests: []
    property var indices: []
    function check(label, got, want) {
        checks++
        if (JSON.stringify(got) === JSON.stringify(want)) return
        failures++
        console.log("FAIL " + label + " got=" + JSON.stringify(got) + " expected=" + JSON.stringify(want))
    }
    function paths(names) { return names.map(function(name) { return "/virtual/" + name }) }
    function reply(names, removed) {
        selection.received({ok: true, marks: paths(names).map(function(path) { return {path: path, bytes: 1} }), removed: removed || 0})
    }
    function deliver(names) { backend.paths(paths(names)) }
    function settleQueued() {
        check("queued selection reaches paths reply", picker.markRequest, -1)
        if (picker.markRequest !== -1) return []
        var before = requests.length
        deliver(indices.map(function(index) { return picker.rowFor(index).n }))
        check("queued selection paths reply starts a fresh check", requests.length, before + 1)
        if (requests.length !== before + 1) return []
        var desired = requests[before].paths
        var unique = desired.filter(function(path, index) { return desired.indexOf(path) === index })
        reply(unique.map(function(path) { return path.slice("/virtual/".length) }))
        return picker.marks.map(function(mark) { return mark.path })
    }
    function selected(label, names) {
        check(label, requests[requests.length - 1].paths, paths(names))
        reply(requests[requests.length - 1].paths.map(function(path) { return path.slice("/virtual/".length) }))
        check(label + " final marks", picker.marks.map(function(mark) { return mark.path }), paths(names))
    }
    function reset() {
        selection.reset()
        picker.markRequest = 0
        picker.marks = []
        picker.marksDirty = false
        requests = []
    }
    QtObject {
        id: picker
        property bool marksAllowed: true
        property bool backendUnavailable: false
        property int pendingListings: 0
        property bool listingFailed: false
        property int markRequest: 0
        property bool submitting: false
        property var marks: []
        property bool marksDirty: false
        property bool acceptMarks: false
        property bool folderMode: false
        property string path: "/virtual"
        property int shownTotal: 5
        property string message: ""
        function rowFor(index) { return {n: String.fromCharCode(65 + index), mode: root.regularFileMode} }
        function check(request) { root.requests = root.requests.concat([request]); return root.requests.length }
        function say(text) { message = text }
        function finish() { root.check("validation removal never accepts", true, false) }
    }
    QtObject { id: listing; function paths(indices) { root.indices = indices } }
    QtObject { id: backend; signal paths(var paths) }
    Selection.PickerSelection { id: selection; picker: picker; listing: listing; backend: backend }
    Component.onCompleted: {
        reset()
        selection.range(0, 1)
        deliver(["A", "B"])
        check("first range check remains outstanding", picker.markRequest > 0, true)
        selection.endRange()
        selection.range(2, 3)
        check("second range waits for first reply", requests.length, 1)
        reply(["A", "B"])
        deliver(["C", "D"])
        selected("queued range keeps earlier range", ["A", "B", "C", "D"])

        reset()
        selection.toggle(0)
        check("toggle check remains outstanding", requests[0].op, "mark")
        selection.endRange()
        selection.range(2, 3)
        reply(["A"])
        deliver(["C", "D"])
        selected("queued range keeps earlier toggle", ["A", "C", "D"])

        reset()
        reply(["A", "B"])
        selection.range(2, 3)
        deliver(["C", "D"])
        reply(["A", "B", "C", "D"])
        selection.validate(true)
        reply(["B", "C", "D"], 1)
        check("identity removal message stays", picker.message, "1 selected item moved or changed; select it again.")
        selection.range(3, 4)
        deliver(["C", "D", "E"])
        selected("extension excludes rejected identity", ["B", "C", "D", "E"])

        reset()
        selection.range(0, 3)
        deliver(["A", "B", "C", "D"])
        selection.range(3, 2)
        selection.range(2, 1)
        reply(["A", "B", "C", "D"])
        check("queued shrink dispatches first action", indices, [0, 1, 2])
        settleQueued()
        check("queued shrink dispatches second action", indices, [0, 1])
        deliver(["A", "B"])
        selected("queued shrink keeps original base", ["A", "B"])

        reset()
        reply(["A"])
        selection.range(1, 2)
        deliver(["B", "C"])
        selection.range(2, 3)
        selection.endRange()
        reply(["B", "C"], 1)
        deliver(["B", "C", "D"])
        selected("ended queued range excludes rejected A", ["B", "C", "D"])

        reset()
        selection.toggle(0)
        selection.all()
        selection.range(2, 3)
        reply(["A"])
        check("queued Select All dispatches before later range", indices, [0, 1, 2, 3, 4])
        settleQueued()
        check("later range dispatches after Select All", indices, [2, 3])
        var rangeMarks = settleQueued()
        check("Select All then range produces A to E", rangeMarks, paths(["A", "B", "C", "D", "E"]))
        console.log("picker-selection QML: " + checks + " checks, " + failures + " failed")
        Qt.exit(failures ? 1 : 0)
    }
}
