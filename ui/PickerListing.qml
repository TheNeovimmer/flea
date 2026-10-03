import QtQuick
import Quickshell
import Quickshell.Io

// Listings can block inside FUSE. Only this read-only worker is replaceable; selection identities
// belong to the picker's separate backend, and the file manager's write backend is never signalled.
Item {
    id: root
    signal message(var value)
    signal pathsResolved(var paths, int request)
    signal failed(string reason)
    signal quitReady()
    property var current: null
    property var pending: null
    property bool quitting: false

    function clear() {
        pending = null
        if (current) {
            current.obsolete = true
            if (current.running) current.signal(9)
        }
    }
    function request(value) {
        if (quitting) return
        // Only list and listpaths have a worker to serve them, so any other request names itself here.
        if (value.c !== "list" && value.c !== "listpaths") { console.warn("PickerListing refused request " + value.c); return }
        pending = value
        if (current) {
            current.obsolete = true
            if (current.running) current.signal(9)
        } else launch()
    }
    function launch() {
        if (quitting || !pending || current) return
        var value = pending
        pending = null
        current = worker.createObject(root, {request: value})
        current.running = true
    }
    function window(start, count) {
        if (current && current.running && !current.obsolete && !quitting)
            current.write(JSON.stringify({c: "window", start: start, count: count}) + "\n")
    }
    // Resolve names without asking metadata for rows outside the held window.
    function paths(rows, request) {
        if (!current || !current.running || current.obsolete || quitting) return false
        current.pathRequests = current.pathRequests.concat([request])
        current.write(JSON.stringify({c: "paths", rows: rows}) + "\n")
        return true
    }
    // Storage class for the grid planner, asked after the listing lands.
    function fsinfo() {
        if (current && current.running && !current.obsolete && !quitting)
            current.write(JSON.stringify({c: "fsinfo"}) + "\n")
    }
    // Sort reorders the worker's own listing without replacing it; the caller re-asks the window after.
    function sort(by, desc, foldersFirst, groupByKind) {
        if (current && current.running && !current.obsolete && !quitting)
            current.write(JSON.stringify({c: "sort", by: by, desc: desc, foldersFirst: foldersFirst, groupByKind: groupByKind}) + "\n")
    }
    // Thumbnails are planned against the rows this worker holds, so the ask goes to it and not to
    // the picker's selection backend, which holds no listing at all. An empty ask names nothing.
    function thumb(rows, cacheOnly) {
        if (!rows || rows.length === 0) return
        if (current && current.running && !current.obsolete && !quitting)
            current.write(JSON.stringify({c: "thumb", rows: rows, cacheOnly: cacheOnly === true}) + "\n")
    }
    // An empty rows cancels everything queued, so an empty list is never sent; see docs/protocol.md.
    function thumbcancel(rows) {
        if (!rows || rows.length === 0) return
        if (current && current.running && !current.obsolete && !quitting)
            current.write(JSON.stringify({c: "thumbcancel", rows: rows}) + "\n")
    }
    function quit() {
        quitting = true
        pending = null
        if (!current) { quitReady(); return }
        current.obsolete = true
        if (current.running) current.signal(9)
    }
    function ended(process, reason) {
        if (current !== process) return
        current = null
        process.destroy()
        if (quitting) quitReady()
        else if (pending) Qt.callLater(launch)
        else if (!process.obsolete) failed(reason)
    }
    Component.onDestruction: if (current && current.running) current.signal(9)

    Component {
        id: worker
        Process {
            id: process
            property var request
            property bool obsolete: false
            property bool started: false
            property var pathRequests: []
            command: [Quickshell.env("FLEA_BIN") || "flea", "--backend"]
            stdinEnabled: true
            onStarted: {
                started = true
                if (obsolete || root.quitting) { signal(9); return }
                write(JSON.stringify(request) + "\n")
            }
            stdout: SplitParser {
                onRead: function(line) {
                    if (process.obsolete || root.quitting || root.current !== process || !line) return
                    // Sample reply: {"t":"paths","paths":["/folder/file.txt"]}; replies follow request order on this worker.
                    try {
                        var message = JSON.parse(line)
                        if (message.t === "paths") {
                            var request = process.pathRequests.shift()
                            if (request !== undefined) root.pathsResolved(message.paths, request)
                        } else root.message(message)
                    }
                    catch (error) { root.failed("The listing backend sent an invalid reply.") }
                }
            }
            onExited: function(code, status) { root.ended(process, "The listing backend exited with code " + code) }
            // A failed QProcess spawn emits runningChanged, but never exited.
            onRunningChanged: if (!running && !started) root.ended(process, "The listing backend could not be started.")
        }
    }
}
