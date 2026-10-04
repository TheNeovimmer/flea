//@ pragma ShellId flea-dialog-board-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/TextSize.js" as TextSize

// tests/dialog-board.sh's harness, DialogButtons040's critic findings on the shipped files: the check boxes draw no stray ground, the Trash strip's Back and Up are ChromeButtons, and OpenWith's search field sits where the board puts it.
ShellRoot {
    id: shell

    // GM's text size, where the board's numbers are measured (DialogButtons040 at x 1250: rule 818, field 837 to 866, eyebrow ink 898).
    readonly property int pinnedSize: 14
    readonly property int boardRuleToField: 18
    readonly property int boardFieldToEyebrowInk: 31
    readonly property real pressScale: 0.96
    // Quiet ticks (the watched values unchanged) before a step is read; a count of frames, never time.
    readonly property int settleTicks: 4
    readonly property int tickMs: 16
    readonly property int outerTimeoutS: Number(Quickshell.env("DIALOGBOARD_TIMEOUT_S")) || 60
    readonly property int capShare: 2
    readonly property int msPerSecond: 1000
    readonly property double startedAt: Date.now()
    readonly property int capMs: shell.outerTimeoutS * shell.msPerSecond / shell.capShare
    readonly property int noDelay: 0
    // The pointer parks here, clear of both strip controls, and presses are released far outside so no tap fires.
    readonly property int parkX: 700
    readonly property int parkY: 150
    readonly property int releaseOutside: -40
    readonly property int trashRows: 3
    readonly property int milli: 1000
    readonly property string sandboxRoot: Quickshell.env("DIALOGBOARD_ROOT") || ""

    property int checks: 0
    property var failures: []
    property int step: 0
    property int quiet: 0
    property string lastWatch: ""
    property bool acted: false
    property var script: []
    property int backRequests: 0
    property int upActivations: 0
    property var read: ({})

    // Up's own signal, counted where it fires: a dead Up wires no handler, so the view's Back count alone could never see it.
    Connections {
        target: view.upItem
        function onActivated() { shell.upActivations += 1 }
    }

    function log(line) { console.log("DIALOGBOARD " + line) }
    function check(name, actual, expected) {
        shell.checks += 1
        if (JSON.stringify(actual) === JSON.stringify(expected)) {
            shell.log("ok " + name)
            return
        }
        shell.failures.push(name)
        shell.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function finish() {
        shell.log("DONE checks=" + shell.checks + " failed=" + shell.failures.length)
        shell.step = shell.script.length + 1
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    function rgba(c) {
        return [c.r, c.g, c.b, c.a].map(function (v) { return Math.round(v * shell.milli) / shell.milli }).join(",")
    }
    function round3(v) { return Math.round(v * shell.milli) / shell.milli }
    function isType(o, name) {
        var s = String(o)
        return s.indexOf(name) === 0 || s.indexOf("QQuick" + name) === 0
    }
    // Every item under (and including) root the predicate accepts, depth first.
    function findAll(root, accept) {
        var out = []
        var stack = [root]
        while (stack.length > 0) {
            var o = stack.pop()
            if (accept(o)) out.push(o)
            var kids = (o && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return out
    }
    function underRoot(path) {
        return shell.sandboxRoot.length > 0 && path.indexOf(shell.sandboxRoot + "/") === 0 && path.split("/").indexOf("..") < 0
    }

    // The colours a surface may paint: every role the theme owns, so a ground the product chose is never mistaken for Qt's default.
    function themedColours() {
        var roles = {}
        for (var key in Flea.Theme.color) {
            var value = Flea.Theme.color[key]
            if (value !== null && typeof value === "object" && value.r !== undefined) roles[shell.rgba(value)] = key
        }
        return roles
    }
    // The rectangles between a check box and its card that paint something the theme does not own, or Qt's own default fill.
    function strayGrounds(box, card) {
        var roles = shell.themedColours()
        var stray = []
        for (var o = box.parent; o; o = o.parent) {
            var painted = shell.isType(o, "Rectangle") && o.visible && o.width > 0 && o.height > 0 && o.color.a > 0
            if (painted && (shell.rgba(o.color) === shell.rgba(defaultFill.color) || roles[shell.rgba(o.color)] === undefined))
                stray.push(String(o).split("(")[0] + " " + shell.rgba(o.color))
            if (o === card) break
        }
        return stray
    }
    function checkBoxes(card) {
        return shell.findAll(card, function (o) { return shell.isType(o, "CheckBox") && o.value !== undefined })
    }
    // The off box draws its frame only: its own rectangle is transparent, so the dialog's ground is the interior.
    function offInterior(box) {
        var inner = box.children[0]
        return { value: box.value, filled: inner.color.a }
    }

    function measureCheckBoxes(label, card, expected) {
        var boxes = shell.checkBoxes(card)
        shell.check(label + ": the card hosts " + expected + " check box", boxes.length, expected)
        for (var i = 0; i < boxes.length; i++) {
            shell.check(label + ": the off box's interior is the dialog's ground, no stray fill above it",
                        shell.strayGrounds(boxes[i], card), [])
            shell.check(label + ": the off box draws its frame only", shell.offInterior(boxes[i]), { value: "off", filled: 0 })
        }
    }

    // Where OpenWith's search field sits against its title rule and its first eyebrow's ink, in the card's own coordinates.
    function searchGeometry() {
        var card = openWith.cardItem
        var field = openWith.fieldItem.parent
        var title = shell.findAll(card, function (o) { return shell.isType(o, "Text") && o.text === "Open notes.txt with" })[0]
        var rule = shell.findAll(title, function (o) { return o !== title && shell.isType(o, "Rectangle") })[0]
        var row = openWith.applicationsItem.itemAtIndex(0)
        var eyebrow = shell.findAll(row, function (o) { return shell.isType(o, "Text") && o.text === openWith.rows[0].eyebrow })[0]
        var ruleBottom = rule.mapToItem(card, 0, rule.height).y
        var fieldTop = field.mapToItem(card, 0, 0).y
        var fieldBottom = field.mapToItem(card, 0, field.height).y
        var inkTop = eyebrow.mapToItem(card, 0, 0).y + eyebrow.baselineOffset + capInk.tightBoundingRect.y
        return { ruleToField: shell.round3(fieldTop - ruleBottom), fieldToInk: Math.round(inkTop - fieldBottom) }
    }

    // The mark a strip control draws, in the strip's coordinates, with the opacity and ink it reaches the screen with.
    function mark(item) {
        var glyph = shell.findAll(item, function (o) { return shell.isType(o, "Glyph") })[0]
        var centre = glyph.mapToItem(view.stripItem, glyph.width / 2, glyph.height / 2)
        var opacity = 1
        for (var o = glyph; o && o !== view.stripItem; o = o.parent) opacity *= o.opacity
        return { size: shell.round3(glyph.markSize), x: shell.round3(centre.x), y: shell.round3(centre.y),
                 ink: shell.rgba(glyph.color), opacity: shell.round3(opacity) }
    }
    function hasHand(item) { return item.data.some(function (o) { return o.cursorShape === Qt.PointingHandCursor }) }

    function centre(item) { return { x: item.width / 2, y: item.height / 2 } }
    function park() { driver.mouseMove(stripHost, shell.parkX, shell.parkY, shell.noDelay, Qt.NoButton, Qt.NoModifier) }
    function hoverOn(item) { var c = shell.centre(item); driver.mouseMove(item, c.x, c.y, shell.noDelay, Qt.NoButton, Qt.NoModifier) }
    function pressOn(item) { var c = shell.centre(item); driver.mousePress(item, c.x, c.y, Qt.LeftButton, Qt.NoModifier, shell.noDelay) }
    function releaseOff(item) { driver.mouseRelease(item, shell.releaseOutside, shell.releaseOutside, Qt.LeftButton, Qt.NoModifier, shell.noDelay) }

    FloatingWindow {
        id: window
        implicitWidth: 900
        implicitHeight: 720
        color: "#303030"

        Item {
            id: stripHost
            width: 800
            height: 300
            Flea.TrashView {
                id: view
                opened: true
                total: shell.trashRows
                onBackRequested: shell.backRequests += 1
            }
        }

        Item {
            id: dialogHost
            y: 0
            width: parent.width
            height: parent.height
            Flea.OpenWithDialog { id: openWith }
            Flea.ConvertDialog { id: convert }
        }

        // Qt's own default fill, read off a bare rectangle so no ancestor may wear it.
        Rectangle { id: defaultFill; visible: false; width: 1; height: 1 }
        TextMetrics {
            id: capInk
            font.family: Flea.Theme.font.family
            font.pixelSize: Flea.Theme.font.caption
            font.bold: true
            text: "R"
        }
        // The holder ConvertDialog.open reads: a source, a list area to hand focus back to, and a backend that answers nothing.
        Item {
            id: holder
            property var convertSource: ({ name: "photo.png", path: "/dialog-board/photo.png", menuId: "dialog-board" })
            property Item listArea: Item {}
            property QtObject backend: QtObject {
                signal convertChecked(var message)
                signal convertStarted(int id, int requestId, var source)
                signal convertDone(int id, bool ok, string path, string err, int requestId, var source, bool collision)
                signal failed(string where, var input, string message, string mode)
                function convertImage() {}
            }
        }
        Item { id: parking; y: 700; width: 10; height: 10; focus: true }

        TestEvent { id: driver }
    }

    // The watched values, so a step is read once layout, the delegates and the press scale have stopped moving.
    function watch() {
        var row = openWith.applicationsItem.itemAtIndex(0)
        return JSON.stringify([view.backItem.scale, view.upItem.scale, openWith.cardItem.height, openWith.listHeight,
                               row ? row.y : -1, convert.cardItem.height])
    }

    function buildScript() {
        shell.script = [
            { name: "open-openwith", act: function () {
                openWith.open("openWith", 1, "", parking)
                openWith.receive({ op: "applications", id: 1, ok: true, path: "/dialog-board/notes.txt", kind: "Plain text document",
                                   mime: "text/plain",
                                   applications: [{ id: "a.desktop", label: "Alpha", icon: "a", default: true }],
                                   installed: [{ id: "a.desktop", label: "Alpha", icon: "a" }, { id: "b.desktop", label: "Beta", icon: "b" }] })
            }, record: function () {
                shell.check("the harness draws at GM's text size", Flea.Theme.baseSize, shell.pinnedSize)
                shell.measureCheckBoxes("openwith", openWith.cardItem, 1)
                var geometry = shell.searchGeometry()
                shell.check("openwith: the search field sits 18 px under the title rule (board)", geometry.ruleToField, shell.boardRuleToField)
                shell.check("openwith: the first eyebrow's ink sits 31 px under the field (board)", geometry.fieldToInk, shell.boardFieldToEyebrowInk)
                openWith.close()
            } },
            { name: "open-convert", act: function () { convert.open("photo.png", holder) }, record: function () {
                shell.measureCheckBoxes("convert", convert.cardItem, 1)
                convert.opened = false
            } },
            { name: "strip-rest", act: function () { parking.forceActiveFocus(); shell.park() }, record: function () {
                var back = view.backItem
                var up = view.upItem
                var hit = Flea.Theme.hitMin
                var size = shell.round3(Math.min(Flea.Theme.chromeMarkSize, hit, view.stripItem.height))
                // ChromeButton centres its mark on whole pixels, as the bar's own Back and Up do, so the hand-built mark's half pixel rounds.
                var middle = shell.round3(Math.round((view.stripItem.height - size) / 2) + size / 2)
                var left = Flea.Theme.spacing.rowPaddingX
                var onePlusGap = hit + Flea.Theme.spacing.gap
                shell.check("strip: Back is the one chrome control", shell.isType(back, "ChromeButton"), true)
                shell.check("strip: Up is the one chrome control", shell.isType(up, "ChromeButton"), true)
                shell.check("strip: Back's mark is where the hand-built one drew it, foreground and opaque",
                            shell.mark(back), { size: size, x: shell.round3(left + hit / 2), y: middle, ink: shell.rgba(Flea.Theme.color.foreground), opacity: 1 })
                shell.check("strip: Up's mark is where the hand-built one drew it, muted and at the disabled opacity",
                            shell.mark(up), { size: size, x: shell.round3(left + onePlusGap + hit / 2), y: middle, ink: shell.rgba(Flea.Theme.color.muted),
                                              opacity: Flea.Theme.disabledOpacity })
                shell.check("strip: Back is the pointing hand over its hit box", shell.hasHand(back), true)
                shell.check("strip: Back is live and Up is dead by design", [back.enabled, up.enabled], [true, false])
                shell.check("strip: the keyboard reaches neither mark, so no ring is ever drawn", [!!back.activeFocusOnTab, !!up.activeFocusOnTab], [false, false])
                shell.check("strip: accessible names and the button role are kept",
                            [back.Accessible.name, up.Accessible.name, back.Accessible.role === Accessible.Button, up.Accessible.role === Accessible.Button, up.Accessible.ignored],
                            ["Back", "Up unavailable in Trash", true, true, false])
                shell.check("strip: the mark rows keep their hit width, so the title and count do not move",
                            [back.width, up.width, back.height], [hit, hit, view.stripItem.height])
            } },
            { name: "up-inert", act: function () { shell.hoverOn(view.upItem); driver.mouseClick(view.upItem, view.upItem.width / 2, view.upItem.height / 2, Qt.LeftButton, Qt.NoModifier, shell.noDelay) },
              record: function () { shell.check("strip: a click on the dead Up never activates it", [shell.upActivations, shell.backRequests], [0, 0]) } },
            { name: "back-pressed", act: function () { shell.hoverOn(view.backItem); shell.pressOn(view.backItem) }, record: function () {
                shell.check("strip: Back takes the 0.96 press", view.backItem.scale, shell.pressScale)
            } },
            { name: "back-released-outside", act: function () { shell.releaseOff(view.backItem); shell.park() }, record: function () {
                shell.check("strip: a press released outside does not go Back, and the scale comes home", [shell.backRequests, view.backItem.scale], [0, 1])
            } },
            { name: "back-click", act: function () { driver.mouseClick(view.backItem, view.backItem.width / 2, view.backItem.height / 2, Qt.LeftButton, Qt.NoModifier, shell.noDelay) },
              record: function () { shell.check("strip: a click on Back goes back", shell.backRequests, 1) } }
        ]
    }

    // The sandbox proof first: every path the product resolves lies under the marked root before anything is assigned.
    function pinned() {
        var home = Quickshell.env("HOME") || ""
        var paths = [["HOME", home], ["the state file ViewState reads", Flea.ViewState.store.path], ["the view's home", view.home]]
        var ok = true
        for (var i = 0; i < paths.length; i++) {
            var inside = shell.underRoot(paths[i][1])
            shell.check("sandbox: " + paths[i][0] + " lies under the harness root", inside, true)
            if (!inside) ok = false
        }
        return ok
    }

    Timer {
        interval: shell.tickMs
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function advance() {
        if (Date.now() - shell.startedAt > shell.capMs) {
            shell.failures.push("the harness did not finish")
            shell.log("FAIL the harness did not finish at step " + shell.step)
            shell.finish()
            return
        }
        if (shell.step > shell.script.length) return
        if (shell.script.length === 0) {
            if (!shell.pinned()) { shell.finish(); return }
            // Assigned only once every path is proved under the root, because the store may write on assignment.
            Flea.ViewState.state = { display: { textSize: { mode: TextSize.nearest(shell.pinnedSize) } } }
            shell.buildScript()
            return
        }
        if (shell.step === shell.script.length) { shell.finish(); return }
        var current = shell.script[shell.step]
        if (!shell.acted) {
            current.act()
            shell.acted = true
            shell.quiet = 0
            shell.lastWatch = ""
            return
        }
        var now = shell.watch()
        shell.quiet = now === shell.lastWatch ? shell.quiet + 1 : 0
        shell.lastWatch = now
        if (shell.quiet < shell.settleTicks) return
        current.record()
        shell.acted = false
        shell.step += 1
    }
}
