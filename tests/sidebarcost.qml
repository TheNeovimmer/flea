//@ pragma ShellId flea-sidebarcost-count-test
import QtQuick
import QtTest
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
    // Sidebar040 specimen 1: the 3 px bar lies 1 px in the row above its boundary and 2 px under it.
    readonly property int barAboveBoundary: 1
    readonly property int barBelowBoundary: 2
    readonly property int dragOneRow: 1
    readonly property int dragTwoRows: 2
    readonly property int dragUpNudge: -5
    // Past Qt's 10 px drag threshold, so the first move activates the handler on its own.
    readonly property int dragLead: 14
    property var dragRows: []
    property real dragStartX: 0
    property real dragStartY: 0

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
    function dragHandler(item) {
        return objects(item, []).filter(function(o) { return String(o).indexOf("QQuickDragHandler") >= 0 })[0]
    }
    function visibleLines() { return lines().filter(function(o) { return o.visible }) }
    // The bar's edges against one boundary, whole pixels, in the rail's own coordinates.
    function checkBar(name, boundary) {
        var line = visibleLines()
        check(name + " has one visible bar", line.length, 1)
        if (line.length === 0) return
        var top = line[0].mapToItem(sidebar, 0, 0).y
        check(name + " starts " + barAboveBoundary + " px above its boundary", boundary - top, barAboveBoundary)
        check(name + " ends " + barBelowBoundary + " px under its boundary", top + line[0].height - boundary, barBelowBoundary)
    }
    function favouriteRow(slot) { return sidebar.railItemFor(sidebar.entries.length - 3 + slot) }
    function boundaryOf(line) {
        var row = favouriteRow(Math.min(line, 2))
        return row.mapToItem(sidebar, 0, line === 3 ? row.height : 0).y
    }
    // Every rail row's opacity, favourites first: the held one draws at the ghost value, the rest at 1.
    function opacities() {
        var out = []
        for (var i = 0; i < sidebar.entries.length; i++) out.push(sidebar.railItemFor(i).opacity)
        return out
    }
    // The pointer moves to dy under its press; the handler counts from its press, and Qt holds the newest move until
    // another event arrives, so three moves leave the last one delivered.
    readonly property int dragMoves: 3
    function dragTo(dy) {
        for (var i = 0; i < dragMoves; i++)
            pointer.mouseMove(favouriteRow(0), dragStartX, dragStartY + dy + i, 1, Qt.LeftButton, Qt.NoModifier)
    }
    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 700
        Flea.Sidebar {
            id: sidebar
            width: 220
            height: 700
            onRecentRequested: function(paths, requester, visits) { shell.replies.push({paths: paths, requester: requester, visits: visits}) }
        }
        TestEvent { id: pointer }
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
            var boundary = row.mapToItem(sidebar, 0, slot === 3 ? row.height : 0).y
            checkBar("slot " + slot, boundary)
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
            check("Recent rail row ships off", sidebar.recentEntries.length, 0)
            check("hidden rail query also keeps Recent off", Flea.RailPlaces.recentEntries.length, 0)
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
            var recentFile = Quickshell.env("HOME") + "/a/example.txt"
            var visited = Date.parse("2026-09-30T12:00:00Z") / 1000
            check("pane Recent reply preserves visit time", replies[0].visits[recentFile], visited)
            check("rail Recent reply preserves visit time", replies[1].visits[recentFile], visited)
            sidebar.readRecent(pane)
            check("Recent cache answers without a parse", sidebar.recentReads, 1)
            check("cached Recent asker answered", replies.length, 3)
            check("cached Recent reply preserves visit time", replies[2].visits[recentFile], visited)
            phase = 8
        } else if (phase === 8) {
            // Sidebar040 specimen 1, driven through the real DragHandler: lift the first favourite and take it two rows down.
            check("idle rows are all at full ink", opacities().every(function(o) { return o === 1 }), true)
            var row = favouriteRow(0)
            dragStartX = row.width / 2
            dragStartY = row.height / 2
            pointer.mousePress(row, dragStartX, dragStartY, Qt.LeftButton, Qt.NoModifier, 1)
            dragTo(dragLead)
            phase = 9
        } else if (phase === 9) {
            if (!dragHandler(favouriteRow(0)).active) return
            var held = opacities()
            var firstFavourite = sidebar.entries.length - 3
            check("the held favourite draws at the ghost value", held[firstFavourite], Flea.Theme.disabledOpacity)
            check("every other rail row stays at 1", held.filter(function(o, i) { return i !== firstFavourite && o !== 1 }).length, 0)
            dragTo(dragTwoRows * Flea.Theme.railRowHeight)
            phase = 10
        } else if (phase === 10) {
            if (sidebar.reorderLine !== 3) return
            checkBar("drag under the last favourite", boundaryOf(3))
            dragTo(dragOneRow * Flea.Theme.railRowHeight)
            phase = 11
        } else if (phase === 11) {
            if (sidebar.reorderLine !== 2) return
            checkBar("drag between two favourites", boundaryOf(2))
            check("the held row is still the ghost", favouriteRow(0).opacity, Flea.Theme.disabledOpacity)
            dragTo(dragUpNudge)
            phase = 12
        } else if (phase === 12) {
            if (sidebar.reorderLine !== 0) return
            checkBar("drag above the first favourite", boundaryOf(0))
            pointer.mouseRelease(favouriteRow(0), dragStartX, dragStartY + dragUpNudge, Qt.LeftButton, Qt.NoModifier, 1)
            phase = 13
        } else if (phase === 13) {
            if (sidebar.reorderLine !== -1) return
            check("release returns every rail row to full ink", opacities().every(function(o) { return o === 1 }), true)
            check("release leaves no visible bar", visibleLines().length, 0)
            console.log("BOOTLOAD DONE " + checks + " checks, " + failures + " failed")
            Qt.quit()
        }
    }
    Timer { interval: 100; running: true; repeat: true; onTriggered: shell.advance() }
    Timer { interval: 10000; running: true; onTriggered: { console.log("BOOTLOAD FAIL stalled"); Qt.quit() } }
}
