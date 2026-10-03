//@ pragma ShellId flea-ring-bounds-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/TextSize.js" as TextSize

// Every 2 px focus ring that can reach an edge, against the room its real host leaves: the chrome path field in the
// real WindowBody's ChromeBar, and the rename editor in a list row, a column row and a grid tile, at each text stop.
ShellRoot {
    id: root
    readonly property string fixture: Quickshell.env("HOME") + "/fixture"
    readonly property var pane: body.currentPane
    // The least room a ring keeps from a host's edge, a strip's rule and the window's edge.
    readonly property int edgeClear: 1
    // The ring is drawn this wide outside its frame, ui/js/Buttons.js RING.
    readonly property int ringWidth: 2
    // A step that waits gives up after this many ticks of the stepper, so a stuck probe fails instead of hanging.
    readonly property int stallTicks: 200
    // The text stops the default density is swept at, and the stops the other densities are swept at.
    readonly property var allStops: TextSize.STOPS
    readonly property var pairStops: [12, 14]
    readonly property var otherDensities: ["tight", "normal", "comfortable"]
    property var combos: []
    property int comboIndex: 0
    property int stage: 0
    property int stageTicks: 0
    property int checks: 0
    property var failures: []

    function check(cond, label) {
        root.checks++
        if (!cond) {
            root.failures.push(label)
            console.log("RINGBOUNDS FAIL " + label)
        }
    }
    function ready() { return !pane.listInFlight && pane.path === fixture && pane.listingState === "ready" }
    function ipcItem() {
        for (var i = 0; i < body.data.length; i++)
            if (String(body.data[i]).indexOf("Ipc_") === 0) return body.data[i]
        throw new Error("WindowBody has no IPC item")
    }
    function find(item, type) {
        if (String(item).indexOf(type + "_") === 0) return item
        var kids = item && item.children ? item.children : []
        for (var i = 0; i < kids.length; i++) {
            var found = root.find(kids[i], type)
            if (found) return found
        }
        return null
    }

    // Sample input: {x: 3, y: 1, width: 40, height: 20} inside {w: 100, h: 30} keeps one pixel clear on every side.
    function clear(tag, box, w, h) {
        root.check(box.y >= root.edgeClear, tag + " top " + box.y + " is not " + root.edgeClear + " clear")
        root.check(box.x >= root.edgeClear, tag + " left " + box.x + " is not " + root.edgeClear + " clear")
        root.check(box.x + box.width <= w - root.edgeClear, tag + " right " + (box.x + box.width) + " of " + w)
        root.check(box.y + box.height <= h - root.edgeClear, tag + " bottom " + (box.y + box.height) + " of " + h)
    }

    function measureChrome(tag) {
        var chrome = root.find(body, "ChromeBar")
        var rule = Flea.Theme.spacing.hairline
        var r = chrome.pathRing
        var box = r.mapToItem(chrome, 0, 0, r.width, r.height)
        root.check(r.visible, tag + " chrome ring is not showing")
        console.log("RINGBOUNDS CHROME " + tag + " ring=" + box.x + "," + box.y + " " + box.width + "x" + box.height + " strip=" + chrome.width + "x" + chrome.height)
        // The rule is the strip's last row, so the ring ends a row above it.
        root.clear(tag + " chrome ring", box, chrome.width, chrome.height - rule)
        var frame = chrome.pathFrame.mapToItem(chrome, 0, 0, chrome.pathFrame.width, chrome.pathFrame.height)
        root.check(frame.height === Flea.Theme.chromeHeight - rule - 2 * Flea.Theme.chromeFieldInset, tag + " chrome frame " + frame.height + " is not the strip's control height")
        // The caret's line box stays inside the frame, which at the two smallest stops is all the strip's room leaves it.
        var caret = chrome.pathField.mapToItem(chrome, 0, chrome.pathField.cursorRectangle.y, 1, chrome.pathField.cursorRectangle.height)
        root.check(caret.y >= frame.y && caret.y + caret.height <= frame.y + frame.height, tag + " chrome caret " + caret.y + "+" + caret.height + " leaves the frame " + frame.y + "+" + frame.height)
        root.check(Math.abs(caret.y + caret.height / 2 - (frame.y + frame.height / 2)) <= 1, tag + " chrome caret is off the frame's centre")
        // The dropdown hangs flush under the strip, at the frame's own left edge and width.
        var drop = chrome.jump.mapToItem(chrome, 0, 0)
        root.check(drop.y === chrome.height, tag + " jump top " + drop.y + " is not the strip's bottom " + chrome.height)
        root.check(drop.x === frame.x && chrome.jump.width === frame.width, tag + " jump spans " + drop.x + "+" + chrome.jump.width + ", the frame " + frame.x + "+" + frame.width)
    }

    // The rename editor's ring against the cell that hosts it (a row, a column row, a tile) and the viewport that clips it.
    function measureRename(tag) {
        var host = pane.renameEditor()
        if (!host) return false
        var editor = host.editorField
        if (!editor || !editor.ring.visible) return false
        var viewMode = pane.viewMode
        // The typed glyphs, ascent plus descent, fit the frame they are drawn in, which the columns' ring room must not squeeze.
        metrics.font = editor.inputItem.font
        var ink = metrics.ascent + metrics.descent
        console.log("RINGBOUNDS INK " + tag + " ink=" + ink + " line=" + editor.inputItem.contentHeight + " frame=" + editor.inputItem.height)
        // Tight columns are exempt: a 20 px row holds the ring's 6 px of room or the 16 px glyph line, not both (see AGENTS.md).
        root.check(Flea.ViewState.density === "tight" && viewMode === "columns" || ink <= editor.inputItem.height, tag + " rename glyphs " + ink + " are taller than their frame " + editor.inputItem.height)
        var ring = editor.ring
        var cell
        var viewport
        if (viewMode === "columns") {
            // The column draws one editor over its row at renameViewIndex, the column itself being the clip.
            var rowTop = host.renameViewIndex * Flea.Theme.fileRowHeight
            cell = ring.mapToItem(host, 0, 0, ring.width, ring.height)
            cell = { x: cell.x, y: cell.y - rowTop, width: cell.width, height: cell.height }
            root.clear(tag + " rename ring in its column row", cell, host.width, Flea.Theme.fileRowHeight)
            viewport = ring.mapToItem(host, 0, 0, ring.width, ring.height)
            root.clear(tag + " rename ring in its column", viewport, host.width, host.height)
        } else {
            cell = ring.mapToItem(host, 0, 0, ring.width, ring.height)
            console.log("RINGBOUNDS RENAME " + tag + " ring=" + cell.x + "," + cell.y + " " + cell.width + "x" + cell.height + " host=" + host.width + "x" + host.height)
            root.clear(tag + " rename ring in its " + (viewMode === "grid" ? "tile" : "row"), cell, host.width, host.height)
            viewport = ring.mapToItem(pane.listArea, 0, 0, ring.width, ring.height)
            root.clear(tag + " rename ring in its viewport", viewport, pane.listArea.width, pane.listArea.height)
        }
        return true
    }


    // Sample input: a TextInput whose parent frame also holds a 2 px bordered child, the ring ui/ draws beside a field.
    function ringOf(input) {
        var kids = input.parent ? input.parent.children : []
        for (var i = 0; i < kids.length; i++)
            if (kids[i] !== input && kids[i].border && kids[i].border.width === root.ringWidth) return kids[i]
        return null
    }
    function inputs(item, out) {
        if (item.echoMode !== undefined && typeof item.selectAll === "function" && item.visible && item.enabled && root.ringOf(item) !== null) out.push(item)
        var kids = item && item.children ? item.children : []
        for (var i = 0; i < kids.length; i++) root.inputs(kids[i], out)
        return out
    }
    // Every ancestor that clips must hold the whole ring; the first one that does not is the ring cut by its host.
    function clipChain(tag, ring) {
        for (var it = ring.parent; it; it = it.parent) {
            if (it.clip !== true) continue
            var box = ring.mapToItem(it, 0, 0, ring.width, ring.height)
            root.clear(tag + " ring inside the clip of " + String(it).split("(")[0], box, it.width, it.height)
        }
    }
    // Every foreground 2 px frame with no fill under this item, visible or not: a ring that waits for focus still has its place.
    function rings(item, out) {
        if (item.border && item.border.width === root.ringWidth && item.color.a === 0 && Qt.colorEqual(item.border.color, Flea.Theme.color.foreground)) out.push(item)
        var kids = item && item.children ? item.children : []
        for (var i = 0; i < kids.length; i++) root.rings(kids[i], out)
        return out
    }
    // TrashConfirm's own card is another worker's file; its rings are listed in the report, not pinned here yet.
    function insideOwnedElsewhere(ring) {
        for (var it = ring.parent; it; it = it.parent)
            if (String(it).indexOf("TrashConfirm_") === 0) return true
        return false
    }
    function measureDialog(tag, dialog, wantsField) {
        var all = root.rings(dialog, [])
        console.log("RINGBOUNDS DIALOG " + tag + " rings=" + all.length)
        for (var r = 0; r < all.length; r++) {
            if (root.insideOwnedElsewhere(all[r])) {
                console.log("RINGBOUNDS KNOWN " + tag + " ring " + r + " sits in ui/TrashConfirm.qml, owned by another worker, not measured here")
                continue
            }
            root.clipChain(tag + " ring " + r, all[r])
        }
        var list = root.inputs(dialog, [])
        root.check(!wantsField || list.length > 0, tag + " dialog shows no ringed field")
        for (var i = 0; i < list.length; i++) {
            list[i].forceActiveFocus()
            var ring = root.ringOf(list[i])
            root.check(ring.visible, tag + " field " + i + " ring is not showing")
            var box = ring.mapToItem(null, 0, 0, ring.width, ring.height)
            console.log("RINGBOUNDS DIALOG " + tag + " field " + i + " ring=" + box.x + "," + box.y + " " + box.width + "x" + box.height)
            root.clipChain(tag + " field " + i, ring)
        }
    }

    function buildCombos() {
        var out = []
        for (var i = 0; i < root.allStops.length; i++)
            out.push({ stop: root.allStops[i], density: "compact", dialogs: root.pairStops.indexOf(root.allStops[i]) >= 0 })
        for (var d = 0; d < root.otherDensities.length; d++)
            for (var s = 0; s < root.pairStops.length; s++)
                out.push({ stop: root.pairStops[s], density: root.otherDensities[d], dialogs: false })
        root.combos = out
    }

    // Each card, opened through its real owner; ready says its field can take the caret.
    readonly property var dialogs: [
        { name: "new file", open: function () { pane.menuActions.dialogFor = "newFile"; pane.menuActions.active = true; pane.menuActions.item.open("newFile", 1, root.fixture, pane.listArea) },
          item: function () { return pane.menuActions.item }, ready: function (d) { return d.opened }, close: function (d) { d.opened = false } },
        { name: "open with", open: function () { pane.menuActions.dialogFor = "openWith"; pane.menuActions.active = true; pane.menuActions.item.open("openWith", 2, root.fixture, pane.listArea) },
          item: function () { return pane.menuActions.item }, ready: function (d) { return d.opened }, close: function (d) { d.opened = false } },
        { name: "permissions", open: function () { pane.permissionsRequested(root.fixture + "/a.txt") },
          item: function () { return root.ipcItem().permissionsDialog }, ready: function (d) { return d.opened && d.facts.ok === true && !d.busy }, close: function (d) { d.opened = false } },
        { name: "save picker", open: function () { fakePicker.saving = true },
          item: function () { return saveCard }, ready: function (d) { return d.visible }, close: function (d) { fakePicker.saving = false } },
        { name: "convert", field: false, open: function () { pane.convertSource = { path: root.fixture + "/a.txt", name: "a.png", menuId: 0 }; pane.convertRequested("a.png") },
          item: function () { return root.ipcItem().convertDialog }, ready: function (d) { return d.opened }, close: function (d) { d.opened = false } },
        { name: "window", field: false, open: function () {},
          item: function () { return body }, ready: function (d) { return true }, close: function (d) {} },
        { name: "network", open: function () { pane.sidebar.addRequested() },
          item: function () { return root.ipcItem().networkDialog }, ready: function (d) { return d.opened }, close: function (d) { d.opened = false } }
    ]
    property int dialogIndex: 0
    property bool dialogOpened: false

    readonly property var views: ["list", "columns", "grid"]
    property int viewIndex: 0
    property bool waiting: false

    // Each stage returns true when done and false to be asked again on the next tick.
    function advance() {
        var combo = root.combos[root.comboIndex]
        var tag = "stop " + combo.stop + " " + combo.density
        if (root.stage === 0) {
            if (!root.ready()) return false
            Flea.ViewState.setTextSize({ mode: combo.stop })
            Flea.ViewState.changeKey("density", combo.density)
            root.viewIndex = 0
            root.stage = 1
            return true
        }
        if (root.stage === 1) {
            // The path field opens over the settled geometry of this stop and closes before the rows are measured.
            var chrome = root.find(body, "ChromeBar")
            if (!chrome.editing) { chrome.startEdit(); return false }
            if (!chrome.pathRing.visible) return false
            root.measureChrome(tag)
            chrome.closeEdit()
            root.stage = 2
            return true
        }
        if (root.stage === 2) {
            if (root.viewIndex >= root.views.length) {
                root.dialogIndex = 0
                root.dialogOpened = false
                root.stage = combo.dialogs ? 5 : 6
                return true
            }
            var mode = root.views[root.viewIndex]
            if (pane.viewMode !== mode) { pane.chooseView(mode); return false }
            if (!root.ready()) return false
            pane.listArea.forceActiveFocus()
            pane.clearSelection()
            pane.setCursor(0)
            driver.keyClick(Qt.Key_F2, Qt.NoModifier, -1)
            root.stage = 3
            return true
        }
        if (root.stage === 3) {
            if (!root.measureRename(tag + " " + root.views[root.viewIndex])) return false
            pane.renamingIndex = -1
            root.viewIndex++
            root.stage = 2
            return true
        }
        if (root.stage === 5) {
            if (root.dialogIndex >= root.dialogs.length) { root.stage = 6; return true }
            var dlg = root.dialogs[root.dialogIndex]
            if (!root.dialogOpened) { dlg.open(); root.dialogOpened = true; return false }
            var item = dlg.item()
            if (!item || !dlg.ready(item)) return false
            root.measureDialog(tag + " " + dlg.name, item, dlg.field !== false)
            dlg.close(item)
            root.dialogOpened = false
            root.dialogIndex++
            return true
        }
        if (root.stage === 6) {
            root.stage = 0
            root.comboIndex++
            return true
        }
        return true
    }

    function report() {
        stepper.running = false
        console.log("RINGBOUNDS DONE checks=" + root.checks + " failed=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Component.onCompleted: root.buildCombos()

    FontMetrics { id: metrics }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 650
        Flea.WindowBody { id: body; host: window }
        Item { anchors.fill: parent; TestEvent { id: driver } }
        // The save picker's answer area, which lives in its own window in the product, at the picker's 840 px.
        Flea.PickerSave { id: saveCard; picker: fakePicker; width: 840; z: 100 }
    }

    QtObject {
        id: fakePicker
        property bool saving: false
        property bool submitting: false
        property string path: Quickshell.env("HOME")
        property string saveName: "export.txt"
        property string saveError: ""
        property bool saveCollision: false
        property var req: ({ name: "export.txt" })
        function stepFocus() {}
        function control() { return null }
        function cancel() {}
        function accept() {}
    }

    Timer {
        id: stepper
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (root.comboIndex >= root.combos.length) {
                root.report()
                return
            }
            var before = root.stage
            var beforeView = root.viewIndex
            var beforeCombo = root.comboIndex
            if (root.advance() === true) {
                root.stageTicks = 0
                return
            }
            root.stageTicks++
            if (root.stageTicks > root.stallTicks) {
                root.failures.push("stage " + before + " of combo " + beforeCombo + " view " + beforeView + " never completed")
                var waitingOn = root.stage === 5 && root.dialogIndex < root.dialogs.length ? root.dialogs[root.dialogIndex].name : "none"
                var stuck = root.stage === 5 && root.dialogIndex < root.dialogs.length ? root.dialogs[root.dialogIndex].item() : null
                if (stuck) console.log("RINGBOUNDS STUCK opened=" + stuck.opened + " busy=" + stuck.busy + " error=" + stuck.errorText + " facts=" + JSON.stringify(stuck.facts))
                console.log("RINGBOUNDS FAIL stalled on dialog " + waitingOn + " at stage " + before + " combo " + beforeCombo + " view " + beforeView)
                root.report()
            }
        }
    }
}
