import QtQuick
import "js/Picker.js" as Picker
import "js/Marks.js" as Marks

// Paths come from the listing worker; retained identities stay on the separate check worker.
Item {
    id: root
    required property var picker
    required property var listing
    required property var backend
    property var base: null
    property int anchor: 0
    property int last: -1
    property var pending: null
    property var queued: null

    function endRange() { base = null }
    function reset() {
        endRange()
        pending = null
        queued = null
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
        resolve(Marks.range(picker.shownTotal), [])
    }
    function range(was, index) {
        if (!permitted()) return
        if (base === null || was !== last) {
            base = Picker.paths(picker.marks)
            anchor = was
        }
        last = index
        var lo = Math.min(anchor, index), hi = Math.max(anchor, index)
        var indices = []
        for (var i = lo; i <= hi; i++) indices.push(i)
        resolve(indices, base)
    }
    function resolve(indices, keep) {
        if (picker.markRequest || picker.submitting) { queued = {indices: indices, keep: keep.slice()}; return }
        pending = keep.slice()
        picker.markRequest = -1
        listing.paths(indices)
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
        if (!message.ok) { endRange(); queued = null; picker.say(message.error, true); return }
        picker.marks = Picker.reviewedMarks(picker.marks, message.marks)
        if (message.removed) picker.say(message.removed === 1
            ? "1 selected item moved or changed; select it again."
            : message.removed + " selected items moved or changed; select them again.", true)
        else if (accepting && picker.marks.length) { picker.finish(Picker.RESPONSE_OK, picker.marks); return }
        if (queued) {
            var next = queued
            queued = null
            resolve(next.indices, next.keep)
        }
        if (picker.marksDirty) { picker.marksDirty = false; validate(false) }
    }
    Connections {
        target: root.backend
        function onPaths(paths) {
            if (root.pending === null || root.picker.markRequest !== -1) return
            var desired = root.pending.concat(paths)
            root.pending = null
            root.picker.markRequest = root.picker.check({op: "select", paths: desired, directory: root.picker.folderMode})
        }
    }
}
