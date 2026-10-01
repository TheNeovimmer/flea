//@ pragma ShellId flea-thumbs-qlprefetch-test

import Quickshell
import QtQuick

// Quick Look's bounded prefetch through the stub backend: one cache-only ask for the next
// row per settled rest, none while a held key is still bursting.
ShellRoot {
    id: shell

    readonly property string uiDir: Quickshell.env("PREVIEW_UI")
    property var failures: []
    property int burstMark: -1

    function log(line) { console.log("THUMBPREFETCH " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond) {
        if (!cond) failures.push(name)
        log((cond ? "PASS " : "FAIL ") + name)
    }
    function done() {
        log("DONE failures=" + failures.length + (failures.length > 0 ? " [" + failures.join(",") + "]" : ""))
        shell.quit()
    }

    QtObject {
        id: backend
        property var calls: []
        function askMeta(index, wantText, wantMedia, wantArchive) { return 0 }
        function thumb(ask, cacheOnly) { calls.push({ ask: ask, cacheOnly: cacheOnly === true }) }
        function thumbcancel(rows) {}
    }

    QtObject {
        id: pane
        property string path: "/t"
        property int cursorIndex: 0
        property var rows: [
            { n: "a.jpg", d: false, i: "image-x-generic", p: 33188, s: 100, m: 1000, t: true, k: 0 },
            { n: "b.jpg", d: false, i: "image-x-generic", p: 33188, s: 101, m: 1001, t: true, k: 0 },
            { n: "c.jpg", d: false, i: "image-x-generic", p: 33188, s: 102, m: 1002, t: true, k: 0 },
            { n: "d.jpg", d: false, i: "image-x-generic", p: 33188, s: 103, m: 1003, t: true, k: 0 }
        ]
        property var kindNames: []
        property var thumbState: ({ file: { 0: "/cache/a.png" }, order: [0] })
        property string storageClass: ""
        property bool storageKnown: true
        property bool listInFlight: false
        property var backend: backend
        property var listArea: ({ forceActiveFocus: function () {} })
        function rowFor(index) { return (index >= 0 && index < rows.length) ? rows[index] : null }
        function join(base, name) { return base + "/" + name }
    }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 600

        Loader {
            id: quick
            anchors.fill: parent
            active: true
            source: "file://" + shell.uiDir + "/Preview.qml"
            onLoaded: { item.pane = pane; kick.restart() }
            onStatusChanged: if (status === Loader.Error) { shell.check("the overlay loads", false); shell.done() }
        }
    }

    function cachedOnly() {
        for (var i = 0; i < backend.calls.length; i++)
            if (backend.calls[i].cacheOnly !== true) return false
        return true
    }

    Timer {
        id: kick
        interval: 200
        repeat: false
        onTriggered: {
            // A settled rest asks the next row's cache entry once, and only cache-only.
            quick.item.open("/t/a.jpg", "image-x-generic", 100, "", "/cache/a.png")
            shell.check("a rest asks once", backend.calls.length === 1)
            shell.check("for the next row", backend.calls.length === 1 && backend.calls[0].ask.join(",") === "1")
            shell.check("cache-only", shell.cachedOnly())
            // A burst an instant later: closed, so neither follow takes a hold; the first
            // loads at once and the second trails it, asking nothing until the settle lands.
            quick.item.close()
            quick.item.lastMoveAt = 0
            quick.item.lastMoveKey = ""
            pane.cursorIndex = 1
            quick.item.follow("/t/b.jpg", "image-x-generic", 101, "", "")
            pane.cursorIndex = 2
            quick.item.follow("/t/c.jpg", "image-x-generic", 102, "", "")
            // The trailing follow trails synchronously, so it asks nothing at once either.
            shell.check("the trailing follow asks nothing at once", backend.calls.length === 2)
            shell.burstMark = backend.calls.length
            midBurst.restart()
        }
    }

    Timer {
        id: midBurst
        interval: 60
        repeat: false
        // Inside the settle window the trailing follow asked for nothing at all.
        onTriggered: {
            shell.check("nothing asks mid-burst", backend.calls.length === shell.burstMark)
            trailPoll.restart()
        }
    }

    Timer {
        id: trailPoll
        interval: 50
        repeat: true
        property int waited: 0
        // The trailing rest asks its own next row once, and still cache-only.
        onTriggered: {
            waited += interval
            if (backend.calls.length > shell.burstMark) {
                stop()
                shell.check("the trailing rest asks once more", backend.calls.length === shell.burstMark + 1)
                shell.check("for the row after it",
                    backend.calls[backend.calls.length - 1].ask.join(",") === "3")
                shell.check("still cache-only", shell.cachedOnly())
                shell.done()
            } else if (waited > 2000) {
                stop()
                shell.check("the trailing rest asks once more", false)
                shell.done()
            }
        }
    }
}
