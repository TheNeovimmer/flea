import QtQuick
import "js/Drag.js" as DragOps
import "js/DragOut.js" as DragOut
import "js/Tabs.js" as Tabs

// Delegate input and drop eligibility share a view-owned FileDrag; no platform object lives in this row.
Item {
    id: root

    required property var session
    required property int listingIndex
    required property var row
    readonly property var pane: root.session.pane

    anchors.fill: parent
    enabled: root.pane !== null && !root.pane.listInFlight && root.listingIndex >= 0 && !!root.row

    DragHandler {
        id: lift
        enabled: root.pane !== null && !root.pane.renamePending && root.pane.renamingIndex !== root.listingIndex
        target: null
        // Preserve List's grab contract: the Flickable must not take the row drag after its threshold.
        grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByHandlersOfSameType
        onActiveChanged: {
            if (active) root.session.liftBegan(root.listingIndex, lift.centroid)
            else root.session.liftReleased()
        }
        onCentroidChanged: if (active) root.session.liftMoved(lift.centroid)
    }

    DropArea {
        anchors.fill: parent
        keys: [DragOps.ROWS_MIME, "text/uri-list", "text/plain"]
        onEntered: function (drag) {
            // xw6: a tab drag carries only the private tab type and is never a file drop.
            if (drag.getDataAsString(Tabs.TAB_MIME) !== "") {
                drag.accepted = false
                return
            }
            drag.accepted = root.enter(drag.getDataAsString(DragOps.ROWS_MIME), drag.urls,
                                       drag.getDataAsString(DragOps.SHELF_MIME),
                                       drag.getDataAsString("text/plain"), drag.proposedAction)
        }
        onPositionChanged: function (drag) {
            if (root.session.dropIndex === root.listingIndex)
                root.session.showTarget(root.row.n, root.row.v)
        }
        onExited: {
            if (root.session.dropIndex === root.listingIndex) {
                root.session.dropIndex = -1
                root.session.leaveTarget()
            }
            if (root.session.dragRows.length === 0) {
                root.session.dragCopy = false
                root.session.dragLink = false
            }
        }
        onDropped: function (drop) {
            if (drop.getDataAsString(Tabs.TAB_MIME) !== "")
                return
            var marker = drop.getDataAsString(DragOps.ROWS_MIME)
            var shelf = drop.getDataAsString(DragOps.SHELF_MIME)
            var plain = drop.getDataAsString("text/plain")
            if (root.refuseDrop(marker, drop.urls, shelf, plain)) return
            if (root.dropped(marker, drop.urls, shelf, plain, drop.proposedAction)) {
                drop.accept(Qt.CopyAction)
            }
        }
    }

    // Testable entrance: a refused folder row stays dark and names its refusal, never lighting "move here" for a drop that cannot land.
    function enter(marker, urls, shelf, plain, proposed) {
        if (!(root.row && root.row.d === true)) return false
        var dest = root.pane.join(root.pane.path, root.row.n)
        var line = ""
        var ok = false
        if (DragOps.hasPaths(urls) || (plain && !marker)) {
            line = DragOut.refusal(DragOut.sources(urls, plain, marker, ""), dest, marker, "")
            ok = line === "" && DragOps.canDropInto(marker, urls, dest, plain)
        } else {
            ok = DragOps.canDropByIndex(marker, root.pane.path, root.session.dragRows, root.listingIndex)
        }
        if (!ok) {
            if (line) root.pane.message(line, false)
            return false
        }
        root.session.dropIndex = root.listingIndex
        root.session.enterTarget(marker, urls, root.row.n, root.row.v, shelf, proposed)
        return true
    }

    // Testable refusal: says the sentence and darkens exactly like dropped(), so a refused
    // drop never leaves the row lit (Qt sends dropped, not exited, after the drop).
    function refuseDrop(marker, urls, shelf, plain) {
        if (!(root.row && root.row.d === true)) return ""
        var dest = root.pane.join(root.pane.path, root.row.n)
        var line = DragOut.refusal(DragOut.sources(urls, plain, marker, shelf), dest, marker, shelf)
        if (!line) return ""
        root.pane.message(line, false)
        root.session.dropIndex = -1
        root.session.dragCopy = false
        root.session.dragLink = false
        root.session.leaveTarget()
        return line
    }

    // The drop apart from its platform event, which tests/js/collide.js cannot build: answers whether it was taken.
    function dropped(marker, urls, shelf, plain, proposed) {
        var accepted = false
        if (root.row && root.row.d === true) {
            if (DragOps.hasPaths(urls) || (plain && !marker && !shelf))
                accepted = DragOps.dropInto(root.pane, marker, urls, root.pane.join(root.pane.path, root.row.n), root.row.v, shelf, plain, proposed)
            else if (DragOps.canDropByIndex(marker, root.pane.path, root.session.dragRows, root.listingIndex))
                accepted = DragOps.dropByIndex(root.pane, root.session.dragRows, root.listingIndex,
                    root.session.verbAt(marker, root.row), root.session.dragListing)
        }
        root.session.dropIndex = -1
        root.session.dragCopy = false
        root.session.dragLink = false
        root.session.leaveTarget()
        return accepted
    }
}
