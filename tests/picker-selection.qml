import QtQuick
import "selection" as Selection

// Controlled replies keep the production selection component's asynchronous boundaries explicit.
Item {
    id: root
    property int checks: 0
    property int failures: 0
    readonly property int regularFileMode: 33188
    readonly property int testPathsDeadlineMs: 1
    readonly property int deadlineObservationMs: 50
    property int expiredPathsRequest: 0
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
    function deliverPaths(values, request) {
        backend.paths(values)
        listing.pathsResolved(values, request === undefined ? listing.pathRequest : request)
    }
    function deliver(names) { deliverPaths(paths(names)) }
    function settleQueued() {
        check("queued selection reaches paths reply", picker.markRequest, -1)
        if (picker.markRequest !== -1) return []
        var before = requests.length
        deliver(indices.map(function(index) { return picker.rowFor(index).n }))
        check("queued selection paths reply starts a fresh check", requests.length, before + 1)
        if (requests.length !== before + 1) return []
        var desired = requests[before].paths
        var unique = desired.filter(function(path, index) { return desired.indexOf(path) === index })
        var outstanding = picker.markRequest
        reply(unique.map(function(path) { return path.slice("/virtual/".length) }))
        // A completed check may already have started the next queued paths request.
        check("queued selection check reply completes", picker.markRequest === outstanding, false)
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
        picker.acceptMarks = false
        picker.message = ""
        picker.messageError = false
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
        property bool messageError: false
        function rowFor(index) { return {n: String.fromCharCode(65 + index), mode: root.regularFileMode} }
        function check(request) { root.requests = root.requests.concat([request]); return root.requests.length }
        function say(text, error) {
            message = text
            messageError = error === true
        }
        function finish() { root.check("validation removal never accepts", true, false) }
    }
    QtObject {
        id: listing
        property bool running: true
        property int pathRequest: 0
        signal pathsResolved(var paths, int request)
        function paths(indices, request) {
            if (!running) return false
            root.indices = indices
            pathRequest = request || 0
            return true
        }
    }
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

        reset()
        picker.message = ""
        selection.received({ok: true, marks: [{path: "/virtual/A", bytes: 1}], skipped: [
            {path: "/virtual/broken", why: "file or folder not found"},
            {path: "/virtual/locked", why: "permission denied"}
        ]})
        check("F20 partial selection names first skipped path and remaining count", picker.message,
            "Selected 1 of 3; 2 left alone: /virtual/broken: file or folder not found; and 1 more")
        check("F20 partial selection keeps valid mark", picker.marks.map(function(mark) { return mark.path }), ["/virtual/A"])

        reset()
        picker.message = ""
        listing.running = false
        selection.all()
        check("F23 unavailable listing clears pending", selection.pending, null)
        check("F23 unavailable listing clears mark request", picker.markRequest, 0)
        check("F23 unavailable listing names failure", picker.message, "The listing backend is not running; reopen this folder.")
        check("F23 unavailable listing sends no selection check", requests.length, 0)
        listing.running = true

        reset()
        picker.marks = [{path: "/a/held", bytes: 1}]
        picker.path = "/b"
        picker.shownTotal = 2
        selection.all()
        deliverPaths(["/b/first", "/b/second"])
        var desired = ["/a/held", "/b/first", "/b/second"]
        check("F24 Ctrl+A in b preserves marks from a", requests[0].paths, desired)
        selection.received({ok: true, marks: requests[0].paths.map(function(path) { return {path: path, bytes: 1} })})
        selection.all()
        deliverPaths(["/b/first", "/b/second"])
        check("F24 repeated Ctrl+A sends unchanged desired set", requests[1].paths, desired)
        selection.received({ok: true, marks: requests[1].paths.map(function(path) { return {path: path, bytes: 1} })})
        check("F24 repeated Ctrl+A keeps unchanged marks", picker.marks.map(function(mark) { return mark.path }), desired)

        reset()
        picker.marks = [{path: "/a/stale", bytes: 1}]
        selection.all()
        deliverPaths(["/b/first", "/b/second"])
        check("F34 refused select includes retained identity", requests[0].paths, ["/a/stale", "/b/first", "/b/second"])
        var refusal = "Selected item changed; select it again."
        selection.received({op: "select", ok: false, error: refusal})
        check("F34 refused select asks exactly one validation", requests.length, 2)
        check("F34 refused select asks validation of retained marks", requests.length > 1 ? requests[1].op : "", "validate")
        check("F34 refused select keeps standing message", picker.message, refusal)
        if (requests.length > 1) {
            selection.received({op: "validate", ok: true, marks: [], removed: 1})
            check("F34 validation removes stale identity", picker.marks, [])
            check("F34 validation preserves refusal message", picker.message, refusal)
            check("F34 validation does not ask again", requests.length, 2)
            selection.all()
            deliverPaths(["/b/first", "/b/second"])
            check("F34 retry selects without stale identity", requests[2].paths, ["/b/first", "/b/second"])
            selection.received({op: "select", ok: true, marks: [{path: "/b/first", bytes: 1}, {path: "/b/second", bytes: 1}]})
            check("F34 retry leaves requested marks", picker.marks.map(function(mark) { return mark.path }), ["/b/first", "/b/second"])
        }

        reset()
        picker.marks = [{path: "/a/stale", bytes: 1}]
        selection.all()
        deliverPaths(["/b/first"])
        selection.received({op: "select", ok: false, error: refusal})
        var validations = requests.length
        selection.received({op: "validate", ok: false, error: "The picker check stopped; reopen this request."})
        check("F34 refused validation never asks again", requests.length, validations)
        check("F34 refused validation clears guard", picker.markRequest, 0)

        reset()
        var timers = selection.data.filter(function(child) { return child.objectName === "selectionPathsDeadline" })
        if (timers.length) timers[0].interval = testPathsDeadlineMs
        selection.all()
        expiredPathsRequest = listing.pathRequest
        selection.range(0, 1)
        check("F33 stalled paths queues later selection", selection.queued.length, 1)
        deadlineObservation.start()
    }
    Timer {
        id: deadlineObservation
        interval: root.deadlineObservationMs
        onTriggered: {
            root.check("F33 stalled paths resets sentinel", picker.markRequest, 0)
            root.check("F33 stalled paths clears pending", selection.pending, null)
            root.check("F33 stalled paths clears queue", selection.queued, [])
            var refusal = "The listing backend did not answer the selection request; try again."
            root.check("F33 stalled paths names visible refusal", picker.message, refusal)
            root.check("F33 stalled paths keeps error visible", picker.messageError, true)
            root.deliverPaths(["/b/late"], root.expiredPathsRequest)
            root.check("F33 late reply sends no check", root.requests.length, 0)
            root.check("F33 late reply leaves marks", picker.marks, [])
            root.check("F33 late reply leaves message", picker.message, refusal)

            root.reset()
            selection.all()
            root.deliverPaths(["/b/late"], root.expiredPathsRequest)
            root.check("F33 expired reply cannot complete retry", picker.markRequest, -1)
            root.check("F33 expired reply during retry sends no check", root.requests.length, 0)
            root.deliverPaths(["/b/fresh"])
            root.check("F33 fresh reply starts one check", root.requests.length, 1)
            root.check("F33 fresh reply selects requested path", root.requests.length ? root.requests[0].paths : [], ["/b/fresh"])
            selection.received({op: "select", ok: true, marks: [{path: "/b/fresh", bytes: 1}]})
            root.check("F33 fresh reply completes retry", picker.markRequest, 0)
            console.log("picker-selection QML: " + root.checks + " checks, " + root.failures + " failed")
            Qt.exit(root.failures ? 1 : 0)
        }
    }
}
