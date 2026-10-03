//@ pragma ShellId flea-startup-objects-test
import QtQuick
import Quickshell

ShellRoot {
    id: root
    readonly property int startupObjectLimit: 702
    readonly property int sectorsWrittenField: 6
    readonly property int deadlineProbeMs: 1200
    readonly property int sectorChangeDelayMs: 600
    readonly property int deadlineSlackMs: 200
    readonly property int reloadWaitMs: 2000
    property bool finished: false
    property int stableSamples: 0
    property int lastTotal: -1
    property int phase: 0
    property var device: null
    property var reader: null
    property var chainTimer: null
    property double chainStartedAt: 0
    property double pollStartedAt: 0
    property double chainExpiredAt: 0

    function finish(ok, reason) {
        if (finished) return
        finished = true
        console.log("STARTUP_OBJECTS " + (ok ? "PASS " : "FAIL ") + reason)
        console.log("STARTUP_OBJECTS DONE")
        if (body.item) body.item.quitBackends()
        retire.start()
    }

    function census(start) {
        var seen = [], counts = {}
        function walk(object) {
            if (!object || seen.indexOf(object) >= 0) return
            seen.push(object)
            // Sample input: "PowerSectorsReader_QMLTYPE_42(0x1234)" becomes "PowerSectorsReader".
            var type = String(object).split("(")[0].replace(/_QML(TYPE)?_\d+/g, "")
            counts[type] = (counts[type] || 0) + 1
            var groups = [object.children, object.data, object.resources]
            for (var g = 0; g < groups.length; g++) {
                var group = groups[g]
                if (!group) continue
                for (var i = 0; i < group.length; i++) walk(group[i])
            }
            if (object.contentItem) walk(object.contentItem)
            if (object.item) walk(object.item)
        }
        walk(start || window)
        return { total: seen.length, counts: counts, objects: seen }
    }

    function checkDemand() {
        var sample = census()
        if (phase === 1) {
            if ((sample.counts.PowerSectorsReader || 0) !== 1)
                return finish(false, "first power-off did not build exactly one reader")
            reader = sample.objects.filter(function (object) {
                return String(object).indexOf("PowerSectorsReader_") === 0
            })[0]
            if (reader.owner !== device || !reader.path.endsWith("/stat"))
                return finish(false, "reader lost its owner or disk path")
            phase = 2
        } else if (phase === 2 && device._powerSectors.length > 0) {
            // Sample input: "1 0 2 3 0 0 42 0 0 0 0 0 0 0 0", field 6 is sectors written ("42").
            if (device._powerSectors !== String(reader.text()).trim().split(/\s+/)[sectorsWrittenField])
                return finish(false, "disk write count did not reach the host")
            if (Date.now() - chainStartedAt < sectorChangeDelayMs || device._streamPending) return
            device._powerSectors = "not-a-sector-count"
            phase = 3
            pollStartedAt = Date.now()
            var listingsBefore = device._listingsStarted
            device.poll()
            if (device._listingsStarted !== listingsBefore + 1)
                return finish(false, "production poll did not start while the chain was active")
        } else if (phase === 3) {
            if (device._powerSectors !== "not-a-sector-count") phase = 4
            else if (Date.now() - pollStartedAt >= reloadWaitMs)
                return finish(false, "production poll did not reload the disk write count")
        } else if (phase === 4 && chainExpiredAt > 0) {
            if (chainExpiredAt < pollStartedAt + deadlineProbeMs - deadlineSlackMs)
                return finish(false, "a changed sector count did not rearm the running chain deadline")
            console.log("STARTUP_OBJECTS DEADLINE initial=" + deadlineProbeMs + " changeAfter="
                + (pollStartedAt - chainStartedAt) + " expiredAfter=" + (chainExpiredAt - chainStartedAt))
            if (reader.path !== "" || census().counts.PowerSectorsReader !== 1)
                return finish(false, "reader was not retained and idle after the chain")
            chainTimer.interval = device.powerOffWaitMs
            device._powerSectors = ""
            device._powerOffDisk = Quickshell.env("STARTUP_OBJECTS_DISK")
            phase = 5
        } else if (phase === 5 && device._powerSectors.length > 0) {
            var next = census().objects.filter(function (object) {
                return String(object).indexOf("PowerSectorsReader_") === 0
            })
            if (next.length !== 1 || next[0] !== reader)
                return finish(false, "a later chain rebuilt the reader")
            device._powerOffDisk = ""
            finish(true, "total=" + lastTotal + " limit=" + startupObjectLimit + " reader=0->1 retained=1 reload=ok deadline=ok")
        }
    }

    Connections {
        target: root.chainTimer
        function onTriggered() { root.chainExpiredAt = Date.now() }
    }

    FloatingWindow {
        id: window
        implicitWidth: 800
        implicitHeight: 600
        Loader {
            id: body
            anchors.fill: parent
            source: "file://" + Quickshell.env("STARTUP_OBJECTS_UI") + "/WindowBody.qml"
            onLoaded: item.host = window
            onStatusChanged: if (status === Loader.Error) root.finish(false, "WindowBody failed to load")
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (root.finished || !body.item) return
            if (root.phase > 0) { root.checkDemand(); return }
            var pane = body.item.currentPane
            if (pane.listInFlight || pane.listingState !== "ready" || pane.total !== 3) return
            var sample = root.census()
            root.stableSamples = sample.total === root.lastTotal ? root.stableSamples + 1 : 0
            root.lastTotal = sample.total
            if (root.stableSamples < 3) return
            console.log("STARTUP_OBJECTS TOTAL " + sample.total)
            var names = Object.keys(sample.counts).sort()
            for (var i = 0; i < names.length; i++)
                console.log("STARTUP_OBJECTS TYPE " + names[i] + " " + sample.counts[names[i]])
            if (sample.total > root.startupObjectLimit)
                return root.finish(false, "total=" + sample.total + " limit=" + root.startupObjectLimit)
            var rows = sample.objects.filter(function (object) {
                return String(object).indexOf("Row_") === 0
            })
            if (rows.length !== pane.total || rows.some(function (row) { return typeof row.dateStamp !== "function" }))
                return root.finish(false, "date stamp is not deferred until a consumer asks")
            var devices = sample.objects.filter(function (object) {
                return String(object).indexOf("DeviceMounts_") === 0
            })
            if (devices.length !== 1)
                return root.finish(false, "expected one device host")
            root.device = devices[0]
            var cold = root.census(root.device).counts
            if ((cold.PowerSectorsReader || 0) !== 0 || cold.FileView !== 1)
                return root.finish(false, "disk-write FileView exists before first power-off")
            root.phase = 1
            root.device._powerOffDisk = Quickshell.env("STARTUP_OBJECTS_DISK")
            root.device._powerOffQueue = []
            root.device.powerOffNext()
            var timers = root.census(root.device).objects.filter(function (object) {
                return String(object).indexOf("QQmlTimer") === 0 && object.interval === root.device.powerOffWaitMs && object.running
            })
            if (timers.length !== 1)
                return root.finish(false, "powerOffNext did not arm exactly one chain deadline")
            root.chainTimer = timers[0]
            // Shorten the real chain's timer before sampling progress, then observe its actual expiry.
            root.chainTimer.interval = root.deadlineProbeMs
            root.chainStartedAt = Date.now()
        }
    }
    Timer { id: retire; interval: 200; onTriggered: Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    Timer { interval: 12000; running: true; onTriggered: root.finish(false, "listing did not settle") }
}
