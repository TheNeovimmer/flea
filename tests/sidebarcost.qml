//@ pragma ShellId flea-sidebarcost-count-test
import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Picker.js" as Picker
import "flea/js/Ops.js" as Ops

// Count real objects and method calls, including hidden objects; no timing threshold.
ShellRoot {
    id: shell
    property int checks: 0
    property int failures: 0
    property var calls: ({modes: 0, selection: 0})
    property int phase: 0
    property var replies: []

    function check(name, actual, expected) {
        checks += 1
        if (actual !== expected) {
            failures += 1
            console.log("BOOTLOAD FAIL " + name + " got=" + actual + " expected=" + expected)
        } else console.log("BOOTLOAD ok " + name)
    }
    function objects(item, seen) {
        if (!item || seen.indexOf(item) >= 0) return seen
        seen.push(item)
        var groups = [item.children || [], item.resources || []]
        for (var g = 0; g < groups.length; g++)
            for (var i = 0; i < groups[g].length; i++) objects(groups[g][i], seen)
        return seen
    }
    function dragCount(item) {
        return objects(item, []).filter(function(o) { return String(o).indexOf("QQuickDragHandler") >= 0 }).length
    }
    function lines() {
        return objects(sidebar, []).filter(function(o) {
            return String(o).indexOf("QQuickRectangle") >= 0 && o.width === sidebar.width
                && o.height === Flea.Theme.accentEdge * Flea.Theme.spacing.hairline
                && String(o.color) === String(Flea.Theme.color.accent)
        })
    }
    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 700
        Flea.Sidebar {
            id: sidebar
            width: 220
            height: 700
            onRecentRequested: function(paths, requester) { shell.replies.push({paths: paths, requester: requester}) }
        }
        Flea.Backend { id: probeBackend }
        Flea.Pane {
            id: pane
            x: 220
            width: 680
            height: 700
            backend: probeBackend
            // Preserve the real helpers' cursor dependency so a sticky menu gate cannot pass.
            function permissionSelection() {
                Ops.targetIndices(pane)
                shell.calls.selection += 1
                return {p: 0o100644}
            }
            function permissionModes() {
                Ops.targetIndices(pane)
                shell.calls.modes += 1
                return [0o100644]
            }
        }
    }
    function advance() {
        if (phase === 0) {
            if (sidebar.entries.length < 4 || Flea.Favourites.inspection.running
                || Object.keys(Flea.Favourites.statuses).length !== 3) return
            var favourites = 0
            for (var i = 0; i < sidebar.entries.length; i++) {
                var favourite = sidebar.entries[i].kind === "favourite"
                if (favourite) favourites += 1
                check("row " + i + " drag objects", dragCount(sidebar.railItemFor(i)), favourite ? 1 : 0)
            }
            check("three favourite fixtures", favourites, 3)
            check("one sidebar insertion object", lines().length, 1)
            check("closed menu selection calls", calls.selection, 0)
            check("closed menu mode calls", calls.modes, 0)
            sidebar.reorderLine = 0
            phase = 1
        } else if (phase <= 3) {
            var slot = phase === 1 ? 0 : phase === 2 ? 1 : 3
            var line = lines().filter(function(o) { return o.visible })
            check("slot " + slot + " has one visible line", line.length, 1)
            var base = sidebar.entries.length - 3
            var row = sidebar.railItemFor(base + Math.min(slot, 2))
            var expected = row.mapToItem(sidebar, 0, slot === 3 ? row.height : 0).y
                - (slot === 3 ? Flea.Theme.accentEdge * Flea.Theme.spacing.hairline : 0)
            check("slot " + slot + " line position", line.length ? line[0].mapToItem(sidebar, 0, 0).y : -1, expected)
            check("line accent thickness", line.length ? line[0].height : -1, Flea.Theme.accentEdge * Flea.Theme.spacing.hairline)
            sidebar.reorderLine = phase === 1 ? 1 : phase === 2 ? 3 : -1
            phase += 1
        } else if (phase === 4) {
            check("idle line hidden", lines().filter(function(o) { return o.visible }).length, 0)
            pane.contextMenu().openAt(Qt.point(260, 40))
            check("open menu selection computed", calls.selection > 0, true)
            check("open menu modes computed", calls.modes > 0, true)
            check("open menu mode value", pane.contextMenu().rowMode, 0o100644)
            check("open menu modes value", JSON.stringify(pane.contextMenu().selectionModes), "[33188]")
            pane.contextMenu().close()
            phase += 1
        } else if (phase === 5) {
            var before = calls.modes + calls.selection
            pane.cursorIndex += 1
            check("closed menu stays unevaluated after cursor move", calls.modes + calls.selection, before)
            check("no Recent parse at settle", sidebar.recentReads, 0)
            var next = Object.assign({}, Flea.ViewState.state)
            next.places = Object.assign({}, next.places, {showRecent:true})
            Flea.ViewState.state = next
            phase = 6
        } else if (phase === 6) {
            check("Recent location token unchanged", sidebar.recentEntries[0].path, Picker.RECENT)
            check("Recent label unchanged", sidebar.recentEntries[0].label, Picker.RECENT_LABEL)
            sidebar.readRecent(pane)
            sidebar.readRecent(null)
            sidebar.readRecent(pane)
            check("in-flight Recent joins each asker once", sidebar.recentRequesters.length, 2)
            phase = 7
        } else if (phase === 7) {
            if (!sidebar.recentKept) return
            check("one Recent parse for all askers", sidebar.recentReads, 1)
            check("both Recent askers answered", replies.length, 2)
            check("Recent paths from lazy reader", JSON.stringify(sidebar.recentPaths), JSON.stringify([Quickshell.env("HOME") + "/a/example.txt"]))
            check("first Recent asker preserved", replies[0].requester === pane, true)
            check("rail Recent asker preserved", replies[1].requester, null)
            sidebar.readRecent(pane)
            check("Recent cache answers without a parse", sidebar.recentReads, 1)
            check("cached Recent asker answered", replies.length, 3)
            console.log("BOOTLOAD DONE " + checks + " checks, " + failures + " failed")
            Qt.quit()
        }
    }
    Timer { interval: 100; running: true; repeat: true; onTriggered: shell.advance() }
    Timer { interval: 10000; running: true; onTriggered: { console.log("BOOTLOAD FAIL stalled"); Qt.quit() } }
}
