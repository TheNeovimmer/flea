//@ pragma ShellId flea-menu-fit-test
import QtQuick
import Quickshell
import "flea" as Flea

// tests/menu-fit.sh's harness: the real ui/ContextMenu.qml with every row shown and key hints on is as wide as its widest row, so no label elides.
ShellRoot {
    id: shell

    property int checks: 0
    property var failures: []
    property int ticks: 0
    property int scene: -1
    property bool done: false
    // Ticks a fresh menu settles before its scene reads text layout.
    readonly property int settleTicks: 1
    // Ticks a scene waits for its rows to stand before it runs anyway and fails by name.
    readonly property int sceneTickBound: 50
    readonly property int windowWidth: 1100
    readonly property int windowHeight: 700
    // The stops Theme snaps to: the brief's 18 and 24 are 16 and 20 in TextSize.js's seven.
    readonly property var stops: [9, 12, 14, 16, 20]
    readonly property var densities: ["compact", "comfortable"]
    // A narrow work area is this share of Theme.menuWidth, under every widened menu at every stop.
    readonly property real narrowWorkShare: 0.8
    // Applications in the scrolling flyout, enough to outgrow the window at any row height.
    readonly property int overflowApps: 40
    // A fade must cover at least this share of a row beyond the card's padding, and a separator under it must read at least this opaque.
    readonly property real minFadeRows: 0.5
    readonly property real minSeparatorAlpha: 0.5
    // One pixel of rounding between a row's wanted width and the slack its layout measures.
    readonly property int roundingSlack: 1
    // The pointer's distance from the window corner for the edge scenes.
    readonly property int edgeMargin: 2
    // Where a scene that is not at the window edge opens its menu.
    readonly property point openPoint: Qt.point(100, 40)

    function log(line) { console.log("MENUFIT " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, actual, expected) {
        shell.checks++
        if (JSON.stringify(actual) === JSON.stringify(expected)) return
        shell.failures.push(name)
        shell.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }

    function report() {
        ticker.running = false
        shell.done = true
        if (shell.failures.length === 0)
            shell.log("PASS " + shell.checks + " checks")
        shell.log("DONE failures=" + shell.failures.length)
        shell.quit()
    }

    FloatingWindow {
        implicitWidth: shell.windowWidth
        implicitHeight: shell.windowHeight
        color: "#303030"
        Flea.ContextMenu { id: menu; anchors.fill: parent }
    }

    // One scene: {tag, stop, density, hints, all, kind: "file" | "background", flyout: action or "", edge, narrow}.
    function sceneList() {
        var out = []
        var flyouts = { file: ["", "openWith", "copyAs", "pasteAs", "runScript"], background: ["", "sort"] }
        for (var s = 0; s < shell.stops.length; s++) {
            for (var d = 0; d < shell.densities.length; d++)
                for (var kind in flyouts)
                    for (var f = 0; f < flyouts[kind].length; f++)
                        out.push({ stop: shell.stops[s], density: shell.densities[d], hints: true, all: true, kind: kind,
                                   flyout: flyouts[kind][f], edge: false, narrow: false })
            // Every default menu at this stop keeps exactly Theme.menuWidth, hints off.
            out.push({ stop: shell.stops[s], density: "compact", hints: false, all: false, kind: "file", flyout: "", edge: false, narrow: false })
            out.push({ stop: shell.stops[s], density: "compact", hints: false, all: false, kind: "file", flyout: "openWith", edge: false, narrow: false })
            // A widened menu and flyout opened at the window's far corner land inside the work area.
            out.push({ stop: shell.stops[s], density: "compact", hints: true, all: true, kind: "file", flyout: "copyAs", edge: true, narrow: false })
            out.push({ stop: shell.stops[s], density: "compact", hints: true, all: true, kind: "file", flyout: "copyAs", edge: false, narrow: true })
        }
        // A scrolled menu and a scrolled flyout, read at both edges and at every separator beside an edge.
        for (var e = 0; e < shell.stops.length; e++) {
            out.push({ stop: shell.stops[e], density: "compact", hints: true, all: true, kind: "file", flyout: "", edge: false, narrow: false, edges: "frame" })
            out.push({ stop: shell.stops[e], density: "compact", hints: true, all: true, kind: "file", flyout: "openWith", edge: false, narrow: false, edges: "flyout" })
        }
        // The row a flyout hangs from, opened by its key on a scrolled menu, is revealed clear of the fades too.
        out.push({ stop: 14, density: "compact", hints: true, all: true, kind: "file", flyout: "", edge: false, narrow: false, edges: "hang" })
        for (var i = 0; i < out.length; i++)
            out[i].tag = out[i].kind + "/" + out[i].stop + "/" + out[i].density + (out[i].hints ? "/hints" : "/plain")
                       + (out[i].all ? "/all" : "/default") + (out[i].flyout ? "/" + out[i].flyout : "")
                       + (out[i].edge ? "/edge" : "") + (out[i].narrow ? "/narrow" : "") + (out[i].edges ? "/scrolled-" + out[i].edges : "")
        return out
    }
    readonly property var scenes: shell.sceneList()

    function setup(s) {
        var stateDoc = { keyHints: s.hints, density: s.density, display: { textSize: { mode: s.stop } } }
        // Every row shown: no hidden id, and the shelf on, which is a stored boolean of its own.
        if (s.all) { stateDoc.menu = { hidden: [] }; stateDoc.shelf = { enabled: true } }
        Flea.ViewState.state = stateDoc
        Flea.Scripts.entries = s.all ? [{ id: "backup", label: "Backup", path: "/x/backup.sh" }] : []
        menu.workArea = s.narrow ? Qt.rect(0, 0, Math.round(Flea.Theme.menuWidth * shell.narrowWorkShare), shell.windowHeight) : Qt.rect(0, 0, shell.windowWidth, shell.windowHeight)
        menu.rowMode = 0o100644
        menu.selectionCount = 1
        menu.rowIsFile = true
        menu.rowIsImage = s.all
        menu.rowIsArchive = s.all
        menu.rowIsSymlink = s.all
        menu.rowHasShebang = s.all
        menu.cursorIsTarget = s.all
        menu.canConvert = s.all
        menu.canExtract = false
        menu.archiveFormats = s.all ? ["zip", "tar"] : []
        menu.clipboardAvailable = s.all
        menu.taildropInstalled = s.all
        menu.taildropPeers = s.all ? [{ id: "p", label: "Laptop" }] : []
        menu.localSend = { installed: s.all, peers: s.all ? [{ id: "q", label: "Phone" }] : [], checking: false }
        menu.dropboxInstalled = s.all
        menu.dropboxPath = s.all ? "/home/u/Dropbox" : ""
        menu.openWithLoaded = true
        menu.openWithApps = [{ id: "a", label: "App A", default: true }, { id: "b", label: "App B" }]
        // A flyout taller than its frame, so it scrolls.
        if (s.edges === "flyout")
            for (var n = 0; n < shell.overflowApps; n++) menu.openWithApps.push({ id: "x" + n, label: "Application " + n })
        var at = s.edge ? Qt.point(shell.windowWidth - shell.edgeMargin, shell.windowHeight - shell.edgeMargin) : shell.openPoint
        if (s.kind === "file") menu.openAt(at)
        else menu.openBackground(at)
        if (s.flyout) {
            var index = shell.entryIndex(s.flyout)
            shell.check(s.tag + ": the row that opens " + s.flyout + " exists", index >= 0, true)
            if (index >= 0) { menu.cursor = index; menu.openSubmenu(index) }
        }
    }
    function entryIndex(action) {
        for (var i = 0; i < menu.entries.length; i++)
            if (menu.entries[i].action === action) return i
        return -1
    }
    function ready(s) {
        if (menu.entries.length === 0) return false
        var main = menu.itemFor(menu.entries.length - 1)
        if (!main || main.height <= 0) return false
        if (!s.flyout) return true
        var sub = menu.submenuItemFor(menu.submenuEntries.length - 1)
        return !!sub && sub.height > 0
    }

    // The Text a row draws a given string in, whatever else the row holds beside it.
    function textDrawn(row, text) {
        for (var i = 0; i < row.children.length; i++)
            if (row.children[i].text === text) return row.children[i]
        return null
    }

    // Reads one card's rows: the labels that elide, the hints that meet their label, and the widest wanted width.
    function readCard(frameItem, count, itemAt, entriesOf) {
        var out = { truncated: [], touching: [], unmeasured: [], wanted: 0, widest: null }
        for (var i = 0; i < count; i++) {
            var row = itemAt(i)
            if (!row || row.isSeparator) continue
            var label = shell.textDrawn(row, row.entry.label)
            if (label && label.truncated) out.truncated.push(row.entry.label)
            var hint = row.hint.length > 0 ? shell.textDrawn(row, row.hint) : null
            if (label && hint && hint.x < label.x + label.implicitWidth) out.touching.push(row.entry.label)
            if (!(row.wantedWidth > 0)) out.unmeasured.push(row.entry.label)
            if (row.wantedWidth > out.wanted) { out.wanted = row.wantedWidth; out.widest = row }
        }
        return out
    }

    function inside(item, area) {
        return item.x >= area.x && item.x + item.width <= area.x + area.width
            && item.y >= area.y && item.y + item.height <= area.y + area.height
    }

    // The card body under a frame, by type name.
    function cardUnder(frameItem) {
        for (var i = 0; i < frameItem.children.length; i++)
            if (String(frameItem.children[i]).indexOf("CardScroll") >= 0) return frameItem.children[i]
        return null
    }
    // The two edge fades a frame holds: the one that is not rotated is the top edge.
    function fadesOf(frameItem) {
        var out = { top: null, bottom: null }
        for (var i = 0; i < frameItem.children.length; i++) {
            var kid = frameItem.children[i]
            if (!kid.gradient) continue
            if (kid.rotation === 0) out.top = kid; else out.bottom = kid
        }
        return out
    }
    // How opaque a fade draws at a distance from its own outer edge: the gradient's two stops, linear between them.
    function fadeAlpha(fade, distance) {
        var from = fade.gradient.stops[0].color.a, to = fade.gradient.stops[1].color.a
        return from + (to - from) * Math.min(1, Math.max(0, distance / fade.height))
    }
    // A scrolled card read at both edges, at each separator flush with an edge, and past the card's padding into the first cut row.
    function runEdges(s) {
        var frameItem = s.edges === "frame" ? menu.frameItem : menu.submenuFrameItem
        var rowAt = s.edges === "frame" ? menu.itemFor : menu.submenuItemFor
        var count = s.edges === "frame" ? menu.entries.length : menu.submenuEntries.length
        var card = shell.cardUnder(frameItem), fades = shell.fadesOf(frameItem)
        var pad = Flea.Theme.spacing.rowPaddingY, tag = s.tag
        shell.check(tag + ": the card scrolls", card.contentHeight > card.height, true)
        shell.check(tag + ": both fades exist", !!fades.top && !!fades.bottom, true)
        if (!fades.top || !fades.bottom) return
        var depth = fades.top.height - pad
        shell.check(tag + ": the top fade reaches into the first cut row", depth >= Math.round(Flea.Theme.rowHeight * shell.minFadeRows), true)
        shell.check(tag + ": the bottom fade reaches into the first cut row", fades.bottom.height - pad >= Math.round(Flea.Theme.rowHeight * shell.minFadeRows), true)
        shell.check(tag + ": the fade does not wash a whole row", depth < Flea.Theme.rowHeight, true)
        var maxY = card.contentHeight - card.height
        card.contentY = 0
        shell.check(tag + ": at the top no top fade, a bottom fade", [fades.top.visible, fades.bottom.visible], [false, true])
        card.contentY = maxY
        shell.check(tag + ": at the bottom a top fade, no bottom fade", [fades.top.visible, fades.bottom.visible], [true, false])
        card.contentY = Math.round(maxY / 2)
        shell.check(tag + ": between the ends both fades", [fades.top.visible, fades.bottom.visible], [true, true])
        var separators = 0, faint = []
        for (var i = 0; i < count; i++) {
            var row = rowAt(i)
            if (!row || !row.isSeparator) continue
            var mid = row.height / 2
            // Flush under the top padding: the separator's centre sits pad plus half its height below the frame's edge.
            var topY = row.y
            // Only a scrolled card cuts its top and only an unfinished one its bottom, so each fade must be shown where it is read.
            if (topY > 0 && topY <= maxY) {
                card.contentY = topY
                separators++
                if (!fades.top.visible || shell.fadeAlpha(fades.top, pad + mid) < shell.minSeparatorAlpha) faint.push("top " + i)
            }
            var bottomY = row.y + row.height - card.height
            if (bottomY >= 0 && bottomY < maxY) {
                card.contentY = bottomY
                separators++
                if (!fades.bottom.visible || shell.fadeAlpha(fades.bottom, pad + mid) < shell.minSeparatorAlpha) faint.push("bottom " + i)
            }
        }
        shell.check(tag + ": a separator beside an edge is drawn under a fade at least half opaque", faint, [])
        shell.check(tag + ": a separator was placed at an edge", separators > 0, true)
        shell.checkBorderWhole(tag, frameItem, fades)
        card.contentY = 0
        if (s.edges === "frame")
            shell.sweepCursor(tag, frameItem, fades, rowAt, count, function (i) { menu.cursor = i })
        else
            shell.sweepCursor(tag, frameItem, fades, rowAt, count, function (i) { menu.submenuCursor = i })
    }

    // A row's top and bottom in the frame's own coordinates, where the fades live.
    function bandIn(frameItem, row) {
        var top = row.mapToItem(frameItem, 0, 0).y
        return { top: top, bottom: top + row.height }
    }
    // Which edge a drawn fade covers the row at: its whole height is the row's ink band, so any overlap washes it.
    function washedBy(frameItem, fades, row) {
        var band = shell.bandIn(frameItem, row), out = []
        if (fades.top.visible && band.top < fades.top.y + fades.top.height) out.push("top")
        if (fades.bottom.visible && band.bottom > fades.bottom.y) out.push("bottom")
        return out
    }
    // The cursor lands on every row going down and then up, so each reveal runs from both directions, and no revealed row sits under a drawn fade.
    function sweepCursor(tag, frameItem, fades, rowAt, count, setCursor) {
        var washed = []
        var order = []
        for (var i = 0; i < count; i++) order.push(i)
        for (var j = count - 2; j >= 0; j--) order.push(j)
        for (var n = 0; n < order.length; n++) {
            var row = rowAt(order[n])
            if (!row || row.isSeparator) continue
            setCursor(order[n])
            var by = shell.washedBy(frameItem, fades, row)
            if (by.length > 0) washed.push(order[n] + ":" + by.join("+"))
        }
        shell.check(tag + ": a revealed cursor row clears both fades", washed, [])
    }
    // The frame's hairline stays whole: each fade lies inside the border, and its outer corners follow the border's inner curve.
    function checkBorderWhole(tag, frameItem, fades) {
        var edge = frameItem.border.width
        var bad = []
        var all = [{ name: "top", fade: fades.top }, { name: "bottom", fade: fades.bottom }]
        for (var i = 0; i < all.length; i++) {
            var f = all[i].fade
            if (f.x < edge || f.x + f.width > frameItem.width - edge) bad.push(all[i].name + " crosses a side border")
            if (all[i].name === "top" && f.y < edge) bad.push("top crosses the top border")
            if (all[i].name === "bottom" && f.y + f.height > frameItem.height - edge) bad.push("bottom crosses the bottom border")
            if (f.radius !== Math.max(0, frameItem.radius - edge)) bad.push(all[i].name + " corner is not concentric")
        }
        shell.check(tag + ": the edge fades leave the frame's hairline whole", bad, [])
    }

    function runHang(s) {
        var tag = s.tag, frameItem = menu.frameItem
        var card = shell.cardUnder(frameItem), fades = shell.fadesOf(frameItem)
        shell.check(tag + ": the card scrolls", card.contentHeight > card.height, true)
        var actions = ["copyAs", "pasteAs", "copyAs"], washed = []
        for (var i = 0; i < actions.length; i++) {
            menu.cursor = 0
            shell.check(tag + ": " + actions[i] + " opens by its key", menu.openSubmenuFor(actions[i]), true)
            var by = shell.washedBy(frameItem, fades, menu.itemFor(menu.cursor))
            if (by.length > 0) washed.push(actions[i] + ":" + by.join("+"))
        }
        shell.check(tag + ": the row a flyout hangs from clears both fades", washed, [])
    }

    function run(s) {
        if (s.edges === "hang") { shell.runHang(s); return }
        if (s.edges) { shell.runEdges(s); return }
        var tag = s.tag
        var main = shell.readCard(menu.frameItem, menu.entries.length, menu.itemFor)
        var cards = [{ name: "frame", frame: menu.frameItem, read: main }]
        if (s.flyout)
            cards.push({ name: "flyout", frame: menu.submenuFrameItem,
                         read: shell.readCard(menu.submenuFrameItem, menu.submenuEntries.length, menu.submenuItemFor) })
        for (var c = 0; c < cards.length; c++) {
            var card = cards[c]
            var want = Math.min(menu.workArea.width, Math.max(Flea.Theme.menuWidth, card.read.wanted))
            shell.check(tag + ": " + card.name + " is as wide as its widest row, capped by the work area", card.frame.width, want)
            shell.check(tag + ": " + card.name + " stays inside the work area", shell.inside(card.frame, menu.workArea), true)
            shell.check(tag + ": " + card.name + " rows each state a wanted width", card.read.unmeasured, [])
            if (!s.narrow) {
                shell.check(tag + ": " + card.name + " elides no label", card.read.truncated, [])
                shell.check(tag + ": " + card.name + " keeps every hint clear of its label", card.read.touching, [])
            }
            if (!s.all)
                shell.check(tag + ": " + card.name + " of rows that all fit keeps Theme.menuWidth", card.frame.width, Flea.Theme.menuWidth)
            // The widest row of a widened card is flush: its hint sits one gap from its label, no wider than needed.
            var widest = card.read.widest
            if (!s.narrow && widest && card.frame.width > Flea.Theme.menuWidth && widest.hint.length > 0 && widest.entry.hintSquare !== true) {
                var label = shell.textDrawn(widest, widest.entry.label), hint = shell.textDrawn(widest, widest.hint)
                var slack = hint.x - (label.x + label.implicitWidth) - Flea.Theme.spacing.gap
                shell.check(tag + ": " + card.name + " is no wider than its widest row needs", Math.abs(slack) <= shell.roundingSlack, true)
            }
        }
    }

    Timer {
        id: ticker
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function advance() {
        if (shell.done) return
        shell.ticks++
        if (shell.scene < 0) {
            if (shell.ticks < shell.settleTicks) return
            shell.scene = 0
            shell.setup(shell.scenes[0])
            shell.ticks = 0
            return
        }
        var s = shell.scenes[shell.scene]
        if ((!shell.ready(s) || shell.ticks <= shell.settleTicks) && shell.ticks <= shell.sceneTickBound) return
        shell.run(s)
        menu.close()
        shell.scene++
        shell.ticks = 0
        if (shell.scene >= shell.scenes.length) { shell.report(); return }
        shell.setup(shell.scenes[shell.scene])
    }
}
