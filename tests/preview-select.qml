//@ pragma ShellId flea-preview-select-test

import QtQuick
import Quickshell
import "flea" as Flea

// A selection change that does not move the cursor reloads the preview column:
// select-all shows multi, back to one shows the single row again, and a lone
// version bump from Marks.follow loads nothing while a plain move loads once.
ShellRoot {
    id: root

    property var failures: []
    property int stage: 0
    property int k: 2
    property int metaMark: 0

    function buildRows() {
        var rows = []
        for (var i = 0; i < 8; i++)
            rows.push({ n: "img" + i + ".jpg", d: false, i: "image-x-generic", p: 420,
                s: 1000 + i, m: 1758835200 + i, t: true, k: 0 })
        return rows
    }

    function check(name, cond, detail) {
        if (cond)
            console.log("PREVIEWSELECT PASS " + name)
        else
            failures.push(name + (detail ? " " + detail : ""))
    }

    function step(index) {
        pane.cursorIndex = index
        preview.followSelection()
    }

    function later(ms) {
        waiter.interval = ms
        waiter.restart()
    }

    function go(next) {
        root.stage = next
        root.flow[next]()
    }

    function done() {
        for (var i = 0; i < root.failures.length; i++)
            console.log("PREVIEWSELECT FAIL " + root.failures[i])
        console.log("PREVIEWSELECT DONE failures=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    QtObject {
        id: backend
        property int metaCalls: 0
        property int thumbCalls: 0
        property int token: 0
        signal metaResult(var message)
        function askMeta(index, wantText, wantMedia, wantArchive) {
            metaCalls += 1
            token += 1
            return token
        }
        function thumb(ask, cacheOnly) { thumbCalls += 1 }
        function thumbcancel(rows) {}
    }

    QtObject {
        id: pane
        property string path: "/tmp/flea-preview-select"
        property int cursorIndex: -1
        property int selectionVersion: 0
        property int selCount: 1
        property var rows: root.buildRows()
        property var kindNames: ({ 0: "" })
        property int settleMs: 120
        property bool storageKnown: true
        property string storageClass: "local"
        property bool listInFlight: false
        property var thumbState: ({ file: {}, order: [] })
        property var backend: backend
        property var listArea: ({ forceActiveFocus: function () {} })
        function rowFor(index) { return (index >= 0 && index < rows.length) ? rows[index] : null }
        function join(path, name) { return path + "/" + name }
        function selectionCount() { return selCount }
        function selectedIndices() {
            if (selCount <= 1)
                return [cursorIndex]
            return [cursorIndex, (cursorIndex + 1) % rows.length, (cursorIndex + 2) % rows.length]
        }
    }

    Window {
        visible: true
        width: 800
        height: 600

        Flea.SelectionPreview {
            id: preview
            width: 800
            height: 600
            pane: pane
            swap: null
        }
    }

    Timer {
        id: waiter
        repeat: false
        onTriggered: root.go(root.stage + 1)
    }

    property var flow: [
        function () { root.later(200) },
        function () {
            root.check("startup sends no backend work", backend.metaCalls === 0,
                "meta=" + backend.metaCalls)
            root.step(root.k)
            root.check("settled single loads", preview.loadedIndex === root.k
                && preview.selectionCount === 1 && preview.previewState !== "multi"
                && backend.metaCalls === 1,
                "loaded=" + preview.loadedIndex + " count=" + preview.selectionCount
                + " state=" + preview.previewState + " meta=" + backend.metaCalls)
            root.later(300)
        },
        function () {
            pane.selCount = 3
            pane.selectionVersion += 1
            preview.replace()
            root.later(300)
        },
        function () {
            root.check("select-all shows multi", preview.previewState === "multi"
                && preview.selectionCount === 3 && preview.loadedSelection === "3:1",
                "state=" + preview.previewState + " count=" + preview.selectionCount
                + " sel=" + preview.loadedSelection)
            pane.selCount = 1
            pane.selectionVersion += 1
            preview.replace()
            root.later(300)
        },
        function () {
            root.check("back to single shows single", preview.loadedIndex === root.k
                && preview.selectionCount === 1 && preview.previewState !== "multi"
                && preview.loadedSelection === "" && backend.metaCalls === 2,
                "loaded=" + preview.loadedIndex + " count=" + preview.selectionCount
                + " state=" + preview.previewState + " sel=" + preview.loadedSelection
                + " meta=" + backend.metaCalls)
            root.metaMark = backend.metaCalls
            pane.selectionVersion += 1
            preview.replace()
            root.later(250)
        },
        function () {
            root.check("lone version bump loads nothing", backend.metaCalls === root.metaMark
                && preview.loadedIndex === root.k,
                "meta=" + backend.metaCalls + " mark=" + root.metaMark
                + " loaded=" + preview.loadedIndex)
            root.metaMark = backend.metaCalls
            pane.cursorIndex = root.k + 1
            pane.selectionVersion += 1
            preview.followSelection()
            preview.replace()
            root.later(300)
        },
        function () {
            root.check("plain move loads exactly once", backend.metaCalls === root.metaMark + 1
                && preview.loadedIndex === root.k + 1 && preview.selectionCount === 1
                && preview.previewState !== "multi",
                "meta=" + backend.metaCalls + " mark=" + root.metaMark
                + " loaded=" + preview.loadedIndex + " state=" + preview.previewState)
            root.done()
        }
    ]

    Component.onCompleted: root.go(0)
}
