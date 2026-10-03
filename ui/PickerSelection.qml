import QtQuick
import "js/Picker.js" as Picker
import "js/Marks.js" as Marks

// Paths come from the listing worker; retained identities stay on the separate check worker.
Item {
    id: root
    required property var picker
    required property var listing
    required property var backend
    property var rangeState: null
    property int anchor: 0
    property int last: -1
    property var pending: null
    property var queued: []
    property bool recoveringSelect: false
    property int nextPathsRequest: 0
    readonly property int pathsDeadlineMs: 5000

    function endRange() { rangeState = null }
    function reset() {
        endRange()
        pending = null
        queued = []
        if (picker.markRequest === -1) picker.markRequest = 0
    }
    function permitted() { return picker.marksAllowed && !picker.backendUnavailable && !picker.pendingListings && !picker.listingFailed }
    function available() {
        if (!permitted()) return false
        if (picker.markRequest || picker.submitting) { picker.say("Selection is still being checked."); return false }
        return true
    }
    function toggle(index) {
        if (!available()) return
        endRange()
        var row = picker.rowFor(index)
        if (!row || Picker.directory(row) !== picker.folderMode) return
        picker.markRequest = picker.check({op: "mark", path: Picker.rowPath(picker.path, row.n), directory: picker.folderMode, multiple: true})
    }
    function all() {
        if (!permitted()) return
        endRange()
        resolve(Marks.range(picker.shownTotal), null)
    }
    function range(was, index) {
        if (!permitted()) return
        if (rangeState === null || was !== last) {
            rangeState = {base: null}
            anchor = was
        }
        last = index
        var lo = Math.min(anchor, index), hi = Math.max(anchor, index)
        var indices = []
        for (var i = lo; i <= hi; i++) indices.push(i)
        resolve(indices, rangeState)
    }
    function resolve(indices, range) {
        if (picker.markRequest || picker.submitting) {
            queued = queued.concat([{indices: indices, range: range}])
            return
        }
        pending = {range: range, request: ++nextPathsRequest}
        picker.markRequest = -1
        if (!listing.paths(indices, pending.request)) {
            reset()
            picker.say("The listing backend is not running; reopen this folder.", true)
        }
    }
    function validate(accepting) {
        if (picker.backendUnavailable || (!picker.marks.length && !picker.markRequest)) return
        if (picker.markRequest) { picker.marksDirty = true; return }
        picker.acceptMarks = accepting
        picker.markRequest = picker.check({op: "validate"})
    }
    function received(message) {
        picker.markRequest = 0
        var accepting = picker.acceptMarks
        picker.acceptMarks = false
        var recovering = recoveringSelect
        recoveringSelect = false
        if (!message.ok) {
            endRange()
            queued = []
            picker.say(message.error, true)
            if (message.op === "select") {
                validate(false)
                recoveringSelect = picker.markRequest > 0
            }
            return
        }
        picker.marks = Picker.reviewedMarks(picker.marks, message.marks)
        if (message.removed) {
            var surviving = Picker.paths(picker.marks)
            var ranges = [rangeState, pending ? pending.range : null].concat(queued.map(function(action) { return action.range }))
            for (var i = 0; i < ranges.length; i++) {
                var range = ranges[i]
                if (range && range.base !== null)
                    range.base = range.base.filter(function(path) { return surviving.indexOf(path) >= 0 })
            }
        }
        if (message.removed && !recovering) picker.say(message.removed === 1
            ? "1 selected item moved or changed; select it again."
            : message.removed + " selected items moved or changed; select them again.", true)
        else if (message.skipped && message.skipped.length) {
            var skipped = message.skipped
            var first = skipped[0]
            var tail = skipped.length > 1 ? "; and " + (skipped.length - 1) + " more" : ""
            picker.say("Selected " + picker.marks.length + " of " + (picker.marks.length + skipped.length)
                + "; " + skipped.length + " left alone: " + first.path + ": " + first.why + tail, true)
        }
        else if (accepting && picker.marks.length) { picker.finish(Picker.RESPONSE_OK, picker.marks); return }
        if (queued.length) {
            var next = queued[0]
            queued = queued.slice(1)
            resolve(next.indices, next.range)
        }
        if (picker.marksDirty) { picker.marksDirty = false; validate(false) }
    }
    Timer {
        objectName: "selectionPathsDeadline"
        interval: root.pathsDeadlineMs
        running: root.pending !== null && root.picker.markRequest === -1
        onTriggered: {
            root.reset()
            root.picker.say("The listing backend did not answer the selection request; try again.", true)
        }
    }
    Connections {
        target: root.listing
        function onPathsResolved(paths, request) {
            if (root.pending === null || root.picker.markRequest !== -1 || request !== root.pending.request) return
            var range = root.pending.range
            if (range && range.base === null) range.base = Picker.paths(root.picker.marks)
            var desired = (range ? range.base : Picker.paths(root.picker.marks)).concat(paths)
            var seen = new Set()
            desired = desired.filter(function(path) {
                if (seen.has(path)) return false
                seen.add(path)
                return true
            })
            root.pending = null
            root.picker.markRequest = root.picker.check({op: "select", paths: desired, directory: root.picker.folderMode})
        }
    }
}
