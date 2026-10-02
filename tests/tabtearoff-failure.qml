//@ pragma ShellId flea-tabtearoff-failure-test
import QtQuick
import Quickshell
import Quickshell.Io
import "tests/js/tabbarfixture.js" as Fixture
import "ui/js/Tabs.js" as Tabs

ShellRoot {
    id: root
    property var pane: null
    property var bar: null
    property var launchAck: null
    property var geometry: null
    property bool staleGeometry: false
    property int launchAcks: 0
    property QtObject firstPane: QtObject { signal opened(string path) }
    property QtObject secondPane: QtObject { signal opened(string path) }
    readonly property int stubWaitMs: 500 // Wait for the detached child receipt before inspecting it.
    FileView { id: exited; path: ""; blockLoading: true }
    Connections {
        target: root.geometry
        function onRectChanged() { if (root.geometry.rect && root.geometry.rect.x !== 200) root.staleGeometry = true }
    }
    Component.onCompleted: {
        root.pane = Fixture.pair()
        root.bar = Fixture.bar(root.pane, Quickshell)
        root.bar.tabLiftBegan(1)
        root.bar.tearOffAt()
        var comp = Qt.createComponent("ui/boot/fleatab.qml")
        var geoComp = Qt.createComponent("geometry.qml")
        if (geoComp.status !== Component.Ready) console.log("GEOMETRY FAIL load=" + geoComp.errorString())
        root.geometry = geoComp.createObject(null)
        root.geometry.begin("first", {})
        root.geometry.begin("latest", {})
        root.launchAck = comp.createObject(root, { panes: [root.firstPane, root.secondPane],
            tabBar: { sendTaken: function () { root.launchAcks++ } },
            launchPid: "111", launchToken: "destination", launchPath: "/tmp/destination" })
    }
    Timer {
        interval: root.stubWaitMs
        running: true
        onTriggered: {
            exited.path = Quickshell.env("FLEA_STUB_MARKER") || ""
            exited.reload()
            var spawned = exited.text().indexOf("exited") >= 0
            var kept = Tabs.count(root.pane) === 2
            if (root.bar.drainLifts) {
                for (var i = 0; i < root.bar.outstandingLifts.length; i++)
                    root.bar.outstandingLifts[i].liftedAt = Date.now() - Tabs.ACK_WAIT_MS - 1
                root.bar.drainLifts()
            }
            root.firstPane.opened("/tmp/unrelated")
            var premature = root.launchAcks !== 0
            root.secondPane.opened("/tmp/destination")
            root.firstPane.opened("/tmp/destination")
            var geometryOk = root.geometry && root.geometry.rect && root.geometry.rect.x === 200 && !root.staleGeometry
            console.log("GEOMETRY " + (geometryOk ? "PASS" : "FAIL") + " queryToken=" + root.geometry.queryToken + " rect=" + JSON.stringify(root.geometry.rect) + " stale=" + root.staleGeometry)
            console.log("LAUNCHACK " + (!premature && root.launchAcks === 1 ? "PASS" : "FAIL") + " acknowledgments=" + root.launchAcks)
            console.log("TEAROFF " + (spawned && kept && Tabs.count(root.pane) === 2 ? "PASS" : "FAIL")
                + " stubExited=" + spawned + " sourceTabs=" + Tabs.count(root.pane))
            Quickshell.execDetached(["kill", String(Quickshell.processId)])
        }
    }
}
