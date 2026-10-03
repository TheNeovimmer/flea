//@ pragma ShellId flea-ring-bounds-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Ops.js" as Ops
import "flea/js/Settings.js" as Settings
import "flea/js/TextSize.js" as TextSize
import "ring-bounds.js" as Pins

// A focused field is its own hairline frame in the accent (the error role in the error state) with no ring, and every
// 2 px button ring lies inside the clip that hosts it. Fields: the chrome path field in the real WindowBody's ChromeBar,
// the rename editor in a list row, a column row and a grid tile at each text stop, and every dialog field. Rings: every
// dialog, card and the Settings sections. A dialog's content stays where 13506d08 drew it (ring-bounds.js).
ShellRoot {
    id: root
    readonly property string fixture: Quickshell.env("HOME") + "/fixture"
    readonly property var pane: body.currentPane
    // The least room a ring keeps from a host's edge, a strip's rule and the window's edge.
    readonly property int edgeClear: 1
    // The ring is drawn this wide outside its frame, ui/js/Buttons.js RING; a field draws none of it.
    readonly property int ringWidth: 2
    // A field's own frame is one hairline wide.
    readonly property int hairline: Flea.Theme.spacing.hairline
    // A list row's top and height before the editor opens, so opening it is seen to move nothing.
    property var rowsBefore: []
    property bool renameMeasured: false
    // The fixture's one name with an extension, whose muted run is patched over the field.
    readonly property string extensionName: "a.txt"
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
    function clear(tag, box, w, h, edge) {
        var e = edge === undefined ? root.edgeClear : edge
        root.check(box.y >= e, tag + " top " + box.y + " is not " + e + " clear")
        root.check(box.x >= e, tag + " left " + box.x + " is not " + e + " clear")
        root.check(box.x + box.width <= w - e, tag + " right " + (box.x + box.width) + " of " + w)
        root.check(box.y + box.height <= h - e, tag + " bottom " + (box.y + box.height) + " of " + h)
    }
    // Sample input: covers({x: 8, y: 2, width: 104, height: 24}, {x: 10, y: 4, width: 100, height: 20}) is true.
    function covers(outer, inner) {
        return outer.x <= inner.x && outer.y <= inner.y && outer.x + outer.width >= inner.x + inner.width
            && outer.y + outer.height >= inner.y + inner.height
    }
    // A focused field is one hairline frame in the role colour, and no 2 px foreground ring is drawn around it.
    function checkFieldFrame(tag, frame, role, roleName, scope) {
        root.check(Qt.colorEqual(frame.border.color, role), tag + " frame is " + frame.border.color + ", not the " + roleName)
        root.check(frame.border.width === root.hairline, tag + " frame is " + frame.border.width + " px wide, not one hairline")
        var box = frame.mapToItem(null, 0, 0, frame.width, frame.height)
        var all = root.rings(scope, [])
        for (var i = 0; i < all.length; i++) {
            if (!all[i].visible || root.ownerOf(all[i]) !== null) continue
            root.check(!root.covers(all[i].mapToItem(null, 0, 0, all[i].width, all[i].height), box), tag + " has a ring around its frame")
        }
    }

    function measureChrome(tag) {
        var chrome = root.find(body, "ChromeBar")
        var rule = root.hairline
        var frame = chrome.pathFrame
        root.check(chrome.pathField.activeFocus, tag + " chrome field has no focus")
        root.checkFieldFrame(tag + " chrome", frame, Flea.Theme.color.accent, "accent", chrome)
        var box = frame.mapToItem(chrome, 0, 0, frame.width, frame.height)
        console.log("RINGBOUNDS CHROME " + tag + " frame=" + box.x + "," + box.y + " " + box.width + "x" + box.height + " strip=" + chrome.width + "x" + chrome.height)
        // The frame is whole inside the strip, above the rule row, with no ring to make room for.
        root.clear(tag + " chrome frame", box, chrome.width, chrome.height - rule, 0)
        // Two hairlines above and one below, which centres it and hangs the Jump dropdown flush (13506d08, 0.3.6).
        root.check(frame.y === 2 * rule && frame.parent.height - frame.y - frame.height === rule, tag + " chrome frame margins " + frame.y + " above, " + (frame.parent.height - frame.y - frame.height) + " below")
        // The caret's line box stays inside the frame, which at the two smallest stops is all the strip's room leaves it.
        var caret = chrome.pathField.mapToItem(chrome, 0, chrome.pathField.cursorRectangle.y, 1, chrome.pathField.cursorRectangle.height)
        root.check(caret.y >= box.y && caret.y + caret.height <= box.y + box.height, tag + " chrome caret " + caret.y + "+" + caret.height + " leaves the frame " + box.y + "+" + box.height)
        root.check(Math.abs(caret.y + caret.height / 2 - (box.y + box.height / 2)) <= 1, tag + " chrome caret is off the frame's centre")
        // The dropdown hangs flush under the strip, at the frame's own left edge and width.
        var drop = chrome.jump.mapToItem(chrome, 0, 0)
        root.check(drop.y === chrome.height, tag + " jump top " + drop.y + " is not the strip's bottom " + chrome.height)
        root.check(drop.x === box.x && chrome.jump.width === box.width, tag + " jump spans " + drop.x + "+" + chrome.jump.width + ", the frame " + box.x + "+" + box.width)
    }

    // The row index of the fixture's one name with an extension, whose muted run the editor patches.
    function extensionIndex() {
        for (var i = 0; i < pane.total; i++)
            if (pane.rowFor(i) && String(pane.rowFor(i).n) === root.extensionName) return i
        return 0
    }
    // The first rows' top and height as the list lays them out, or null for a row it has not built.
    function rowGeometry() {
        var out = []
        for (var i = 0; i < pane.total; i++) {
            var it = pane.visibleItemFor(i)
            out.push(it ? { y: it.y, height: it.height } : null)
        }
        return out
    }

    // The rename editor's frame against the cell that hosts it (a row, a column row, a tile) and the viewport that clips it.
    function measureRename(tag) {
        var host = pane.renameEditor()
        if (!host) return false
        // The error toggle below queues the tile's height update, so the editor lives one more tick for it to land.
        if (root.renameMeasured) { root.renameMeasured = false; return true }
        var editor = host.editorField
        if (!editor || !editor.inputItem.activeFocus) return false
        var viewMode = pane.viewMode
        var frame = editor.frame
        // The typed glyphs, ascent plus descent, fit the frame they are drawn in.
        metrics.font = editor.inputItem.font
        var ink = metrics.ascent + metrics.descent
        console.log("RINGBOUNDS INK " + tag + " ink=" + ink + " line=" + editor.inputItem.contentHeight + " frame=" + editor.inputItem.height)
        root.check(ink <= editor.inputItem.height, tag + " rename glyphs " + ink + " are taller than their frame " + editor.inputItem.height)
        root.checkFieldFrame(tag + " rename", frame, Flea.Theme.color.accent, "accent", host)
        // The error role replaces the accent while the pane holds an error, and goes back the moment it is cleared.
        pane.renameError = "A file by that name exists"
        root.checkFieldFrame(tag + " rename error", frame, Flea.Theme.color.error, "error role", host)
        pane.renameError = ""
        root.check(Qt.colorEqual(frame.border.color, Flea.Theme.color.accent), tag + " rename frame keeps the error colour after the error clears")
        // The extension's muted patch lies inside the frame, so all four sides are whole along their length.
        var patch = editor.extensionPatch
        root.check(patch.visible, tag + " rename extension patch is not showing")
        var pb = patch.mapToItem(frame, 0, 0, patch.width, patch.height)
        root.check(pb.x >= root.hairline && pb.y >= root.hairline && pb.x + pb.width <= frame.width - root.hairline && pb.y + pb.height <= frame.height - root.hairline,
                   tag + " rename extension patch " + pb.x + "," + pb.y + " " + pb.width + "x" + pb.height + " covers the frame's hairline in " + frame.width + "x" + frame.height)
        var cell
        var viewport
        if (viewMode === "columns") {
            // The column draws one editor over its row at renameViewIndex, the column itself being the clip.
            var rowTop = host.renameViewIndex * Flea.Theme.fileRowHeight
            cell = frame.mapToItem(host, 0, 0, frame.width, frame.height)
            viewport = cell
            cell = { x: cell.x, y: cell.y - rowTop, width: cell.width, height: cell.height }
            root.clear(tag + " rename frame in its column row", cell, host.width, Flea.Theme.fileRowHeight, 0)
            root.clear(tag + " rename frame in its column", viewport, host.width, host.height, 0)
        } else {
            cell = frame.mapToItem(host, 0, 0, frame.width, frame.height)
            console.log("RINGBOUNDS RENAME " + tag + " frame=" + cell.x + "," + cell.y + " " + cell.width + "x" + cell.height + " host=" + host.width + "x" + host.height)
            root.clear(tag + " rename frame in its " + (viewMode === "grid" ? "tile" : "row"), cell, host.width, host.height, 0)
            viewport = frame.mapToItem(pane.listArea, 0, 0, frame.width, frame.height)
            root.clear(tag + " rename frame in its viewport", viewport, pane.listArea.width, pane.listArea.height, 0)
        }
        if (viewMode === "list") {
            // The editor lives inside the row, so opening it moves no row and grows none, at every density.
            var after = root.rowGeometry()
            for (var i = 0; i < after.length; i++) {
                if (!root.rowsBefore[i] || !after[i]) continue
                root.check(after[i].y === root.rowsBefore[i].y && after[i].height === root.rowsBefore[i].height,
                           tag + " list row " + i + " moved from " + root.rowsBefore[i].y + "+" + root.rowsBefore[i].height + " to " + after[i].y + "+" + after[i].height + " when the editor opened")
            }
        }
        root.renameMeasured = true
        return false
    }

    // Sample input: a TextInput as the dialog draws it, visible and enabled; a hidden or disabled one holds no caret.
    function inputs(item, out) {
        if (item.echoMode !== undefined && typeof item.selectAll === "function" && item.visible && item.enabled) out.push(item)
        var kids = item && item.children ? item.children : []
        for (var i = 0; i < kids.length; i++) root.inputs(kids[i], out)
        return out
    }
    // Sample input: an input whose parent is its frame (a bordered, filled Rectangle), or whose parent holds that frame beside it.
    function frameOf(input) {
        var parent = input.parent
        var isFrame = function (it) { return it.border && it.border.width > 0 && it.color.a > 0 && it.visible }
        if (isFrame(parent)) return parent
        var kids = parent.children
        for (var i = 0; i < kids.length; i++)
            if (kids[i] !== input && isFrame(kids[i])) return kids[i]
        return null
    }
    function ofType(item, type, out) {
        if (String(item).indexOf(type + "_") === 0 && item.visible) out.push(item)
        var kids = item && item.children ? item.children : []
        for (var i = 0; i < kids.length; i++) root.ofType(kids[i], type, out)
        return out
    }
    // Every ancestor that clips must hold the whole ring; the first one that does not is the ring cut by its host.
    // The button or check box a ring belongs to, or null for a ring drawn by anything else.
    function ownerOf(item) {
        for (var it = item; it; it = it.parent) {
            var name = String(it)
            if (name.indexOf("DialogButton_") === 0 || name.indexOf("CheckBox_") === 0) return it
        }
        return null
    }
    // A box (a CheckBox draws inside its own bounds) needs no ring room. A scrolling body holds the item whole in its content, which
    // is where the bleed gives a ring room at the scroll ends, and in its viewport only at the sides; so do the clips outside it.
    function clipChain(tag, ring, isBox) {
        var owner = root.ownerOf(ring)
        if (owner && !owner.visible) return
        var scrolled = false
        var edge = isBox ? 0 : root.edgeClear
        for (var it = ring.parent; it; it = it.parent) {
            if (it.clip !== true) continue
            var name = tag + " ring inside the clip of " + String(it).split("(")[0]
            var box = ring.mapToItem(it, 0, 0, ring.width, ring.height)
            var scrolls = it.contentItem !== undefined && it.contentHeight !== undefined && it.contentHeight > it.height
            if (scrolls) {
                root.clear(name + " content", ring.mapToItem(it.contentItem, 0, 0, ring.width, ring.height), it.contentWidth, it.contentHeight, edge)
                scrolled = true
            }
            if (scrolled) root.check(box.x >= edge && box.x + box.width <= it.width - edge, name + " sides " + box.x + "+" + box.width + " of " + it.width)
            else root.clear(name, box, it.width, it.height, edge)
        }
    }
    // Every foreground 2 px frame with no fill under this item, visible or not: a ring that waits for focus still has its place.
    function rings(item, out) {
        if (item.border && item.border.width === root.ringWidth && item.color.a === 0 && Qt.colorEqual(item.border.color, Flea.Theme.color.foreground)) out.push(item)
        var kids = item && item.children ? item.children : []
        for (var i = 0; i < kids.length; i++) root.rings(kids[i], out)
        return out
    }
    function rectText(item) {
        var b = item.mapToItem(null, 0, 0, item.width, item.height)
        return [b.x, b.y, b.width, b.height].map(function (v) { return v.toFixed(2) }).join(",")
    }
    // Sample input: a dialog with one field and a Cancel and Create button reads "field 301.00,157.00,397.50,30.00", then two "button" lines.
    function pinsOf(dialog) {
        var out = []
        var list = root.inputs(dialog, [])
        for (var i = 0; i < list.length; i++) out.push("field " + root.rectText(root.frameOf(list[i])))
        var kinds = ["DialogButton", "CheckBox"]
        for (var k = 0; k < kinds.length; k++) {
            var found = root.ofType(dialog, kinds[k], [])
            for (var j = 0; j < found.length; j++) out.push(kinds[k] + " " + root.rectText(found[j]))
        }
        return out
    }
    // A dialog's content lies where 13506d08 drew it: the ring room is given back by the caller's margins.
    function checkPins(key, dialog) {
        var got = root.pinsOf(dialog)
        console.log("RINGBOUNDS POS " + key + " " + JSON.stringify(got))
        var want = Pins.PINS[key]
        if (want === undefined) return
        root.check(JSON.stringify(got) === JSON.stringify(want), key + " content moved: " + JSON.stringify(got) + " against " + JSON.stringify(want))
    }
    function measureDialog(tag, key, dialog, wantsField) {
        var all = root.rings(dialog, [])
        console.log("RINGBOUNDS DIALOG " + tag + " rings=" + all.length)
        for (var r = 0; r < all.length; r++) root.clipChain(tag + " ring " + r, all[r])
        // A CheckBox draws inside its own box, and the box is the thing a clip must not cut.
        var boxes = root.ofType(dialog, "CheckBox", [])
        for (var b = 0; b < boxes.length; b++) root.clipChain(tag + " checkbox " + b, boxes[b], true)
        root.checkPins(key, dialog)
        var list = root.inputs(dialog, [])
        root.check(!wantsField || list.length > 0, tag + " dialog shows no field")
        for (var i = 0; i < list.length; i++) {
            list[i].forceActiveFocus()
            var frame = root.frameOf(list[i])
            root.check(frame !== null, tag + " field " + i + " has no frame")
            if (frame === null) continue
            root.checkFieldFrame(tag + " field " + i, frame, Flea.Theme.color.accent, "accent", dialog)
            // The fields that do not hold the caret keep the muted frame 0.3.6 drew.
            for (var j = 0; j < list.length; j++) {
                var other = root.frameOf(list[j])
                if (j !== i && other) root.check(Qt.colorEqual(other.border.color, Flea.Theme.color.muted), tag + " unfocused field " + j + " frame is " + other.border.color + ", not muted")
            }
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
          item: function () { return root.ipcItem().networkDialog }, ready: function (d) { return d.opened }, close: function (d) { d.opened = false } },
        { name: "trash confirm", field: false, open: function () { pane.menuActions.dialogFor = "newFile"; pane.menuActions.active = true; pane.menuActions.item.open("newFile", 1, root.fixture, pane.listArea); root.trashConfirm().open({ all: false, count: 3, bytes: 0, token: 1 }) },
          item: function () { return pane.menuActions.item ? root.trashConfirm() : null }, ready: function (d) { return d.opened }, close: function (d) { d.opened = false; pane.menuActions.item.opened = false } },
        { name: "transfer card", field: false, open: function () { transferCard.transfer = root.runningTransfer },
          item: function () { return transferCard }, ready: function (d) { return d.visible }, close: function (d) { d.transfer = Ops.emptyTransfer() } }
    ].concat(Settings.SECTIONS.map(function (section) { return root.settingsEntry(section.id) }))

    // The trash confirmation card the file menu's dialog hosts for a permanent delete.
    function trashConfirm() { return root.find(pane.menuActions.item, "TrashConfirm") }
    // A transfer in flight, whose card's Cancel is the one button that card draws.
    readonly property var runningTransfer: ({ id: 1, moving: false, n: 2, index: 1, name: "a.txt", running: true,
                                              done: 0, bytes: 1024, total: 4096, moved: 0, writing: false, drive: "" })
    // One Settings section, opened through the chrome bar's own request so the panel loads as it does for the comma key.
    function settingsEntry(id) {
        return { name: "settings " + id, field: false,
                 open: function () { root.find(body, "ChromeBar").settingsRequested(); root.ipcItem().settingsPanel.showSection(id) },
                 item: function () { var d = root.ipcItem().settingsPanel; return d && d.opened && d.section === id ? d : null },
                 ready: function (d) { return d.opened }, close: function (d) { d.close() } }
    }
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
            if (!chrome.pathField.activeFocus) return false
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
            pane.setCursor(root.extensionIndex())
            root.rowsBefore = pane.viewMode === "list" ? root.rowGeometry() : []
            root.stage = 4
            return true
        }
        if (root.stage === 4) {
            // The cursor lands on the named row before F2 asks to rename it.
            if (pane.cursorIndex !== root.extensionIndex()) return false
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
            root.measureDialog(tag + " " + dlg.name, "stop " + combo.stop + " " + dlg.name, item, dlg.field !== false)
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
        // The transfer card, which the status bar hosts in the product, with the status bar's right margin.
        Flea.TransferCard { id: transferCard; x: 600; y: 100; z: 100 }
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
                if (root.stage === 3) {
                    var held = pane.renameEditor()
                    console.log("RINGBOUNDS STUCK rename index=" + pane.renamingIndex + " cursor=" + pane.cursorIndex + " editor=" + held + " focused=" + (held && held.editorField ? held.editorField.inputItem.activeFocus : "none") + " measured=" + root.renameMeasured + " mode=" + pane.viewMode)
                }
                console.log("RINGBOUNDS FAIL stalled on dialog " + waitingOn + " at stage " + before + " combo " + beforeCombo + " view " + beforeView)
                root.report()
            }
        }
    }
}
