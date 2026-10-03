//@ pragma ShellId flea-menu-card-sink-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea

// tests/menu-card-sink.sh's harness: real pointer events on the real ui/ContextMenu.qml. A press no row takes
// (a disabled row, a separator, the card's padding) stays in the card, on the main frame and the flyout alike.
ShellRoot {
    id: shell

    property int checks: 0
    property var failures: []
    property int ticks: 0
    property int scene: -1
    property var chosenLog: []
    property var refusedLog: []
    // Where the scene's far corner is, clear of both frames, for the click that must close.
    readonly property point outside: Qt.point(630, 470)

    function log(line) { console.log("MENUSINK " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, actual, expected) {
        shell.checks++
        if (JSON.stringify(actual) === JSON.stringify(expected)) return
        shell.failures.push(name)
        shell.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function press(item, x, y, button) { driver.mousePress(item, x, y, button, Qt.NoModifier, 1) }
    function release(item, x, y, button) { driver.mouseRelease(item, x, y, button, Qt.NoModifier, 1) }
    function click(item, x, y, button) { shell.press(item, x, y, button); shell.release(item, x, y, button) }
    function clickCentre(item, button) { shell.click(item, item.width / 2, item.height / 2, button) }

    // A row, a separator and the card's top padding, as {name, item, x, y} for one card.
    function dead(card, rowAt, sepAt, padItem, padY) {
        var row = card === "main" ? menu.itemFor(rowAt) : menu.submenuItemFor(rowAt)
        var sep = card === "main" ? menu.itemFor(sepAt) : menu.submenuItemFor(sepAt)
        return [{ name: "disabled", item: row, x: row.width / 2, y: row.height / 2 },
                { name: "separator", item: sep, x: sep.width / 2, y: sep.height / 2 },
                { name: "padding", item: padItem, x: padItem.width / 2, y: padY }]
    }

    // One press and release on a dead point leaves the menu, the cursors and the chosen log as they were.
    function sink(card, which, button) {
        var pad = Flea.Theme.spacing.rowPaddingY / 2
        var points = card === "main" ? shell.dead("main", 5, 2, menu.frameItem, pad)
                                     : shell.dead("flyout", 1, 2, menu.submenuFrameItem, pad)
        var point = points.filter(function (p) { return p.name === which })[0]
        var tag = card + ":" + which + ":" + (button === Qt.LeftButton ? "left" : "right")
        var cursor = menu.cursor, sub = menu.submenuCursor, open = menu.openSubmenuRow
        var chosen = shell.chosenLog.length, refused = shell.refusedLog.length
        shell.press(point.item, point.x, point.y, button)
        shell.check(tag + ":press-open", menu.opened, true)
        shell.release(point.item, point.x, point.y, button)
        shell.check(tag + ":release-open", menu.opened, true)
        shell.check(tag + ":cursor", menu.cursor, cursor)
        shell.check(tag + ":sub-cursor", menu.submenuCursor, sub)
        shell.check(tag + ":flyout-row", menu.openSubmenuRow, open)
        shell.check(tag + ":nothing-chosen", shell.chosenLog.length, chosen)
        shell.check(tag + ":nothing-refused", shell.refusedLog.length, refused)
    }

    function report() {
        if (shell.failures.length === 0)
            shell.log("PASS " + shell.checks + " checks")
        shell.log("DONE failures=" + shell.failures.length)
        shell.quit()
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"
        Flea.ContextMenu { id: menu; anchors.fill: parent }
        Item { anchors.fill: parent; TestEvent { id: driver } }
    }

    Connections {
        target: menu
        function onChosen(action) { shell.chosenLog.push(action) }
        function onRefused(reason) { shell.refusedLog.push(reason) }
    }

    // A file row's menu: open, openWith (flyout), separator, cut, copy, paste (disabled: nothing on the clipboard), ...
    function openMain() {
        menu.rowMode = 0o100644
        menu.selectionCount = 1
        menu.rowIsFile = true
        menu.openWithLoaded = true
        menu.openWithApps = [{ id: "a", label: "App A" }, { id: "b", label: "App B" }]
        menu.openAt(Qt.point(100, 60))
        menu.cursor = 3
    }
    function ready(item) { return item && item.height > 0 }
    // The card body under a frame, by type name, whatever else the frame holds beside it.
    function cardUnder(frame) {
        for (var i = 0; i < frame.children.length; i++)
            if (String(frame.children[i]).indexOf("CardScroll") >= 0) return frame.children[i]
        return null
    }
    function outsideClose(tag) {
        var out = menu.mapFromItem(null, shell.outside.x, shell.outside.y)
        shell.press(menu, out.x, out.y, Qt.LeftButton)
        shell.check(tag + ":outside-press-open", menu.opened, true)
        shell.release(menu, out.x, out.y, Qt.LeftButton)
        shell.check(tag + ":outside-release-closes", menu.opened, false)
    }

    // The Open with flyout carries a disabled row of its own, which the real inventory never does.
    function openFlyoutWithDisabled() {
        shell.openMain()
        var entries = menu.entries.slice()
        var flyoutRow = Object.assign({}, entries[1])
        flyoutRow.submenu = [{ id: "a", label: "App A" }, { id: "off", label: "Unavailable", disabled: true },
                             { separator: true }, { id: "b", label: "App B" }]
        entries[1] = flyoutRow
        menu.entries = entries
        menu.cursor = 1
        menu.openSubmenu(1)
    }
    // The live Open with flyout: App A, App B, a separator, Another application.
    function openLiveFlyout() {
        shell.openMain()
        menu.cursor = 1
        menu.openSubmenu(1)
    }

    // Each scene opens a fresh menu, waits for its rows to stand, then runs once, so one failure never hides the next.
    function sinkScenes() {
        var out = []
        var cards = ["main", "flyout"], points = ["disabled", "separator", "padding"]
        var buttons = [Qt.LeftButton, Qt.RightButton]
        for (var c = 0; c < cards.length; c++)
            for (var p = 0; p < points.length; p++)
                for (var b = 0; b < buttons.length; b++)
                    out.push(shell.sinkScene(cards[c], points[p], buttons[b]))
        return out
    }
    function sinkScene(card, which, button) {
        var main = card === "main"
        return { setup: main ? shell.openMain : shell.openFlyoutWithDisabled,
                 ready: function () { return main ? menu.itemFor(5) : menu.submenuItemFor(3) },
                 run: function () { shell.sink(card, which, button) } }
    }
    readonly property var scenes: shell.sinkScenes().concat([
        { setup: shell.openMain, ready: function () { return menu.itemFor(6) }, run: shell.mainWheelHover },
        { setup: shell.openMain, ready: function () { return menu.itemFor(4) }, run: shell.mainEnabled },
        { setup: shell.openMain, ready: function () { return menu.itemFor(4) }, run: shell.mainOutside },
        { setup: shell.openFlyoutWithDisabled, ready: function () { return menu.submenuItemFor(3) }, run: shell.flyoutWheelHover },
        { setup: shell.openFlyoutWithDisabled, ready: function () { return menu.submenuItemFor(3) }, run: shell.flyoutOutside },
        { setup: shell.openLiveFlyout, ready: function () { return menu.submenuItemFor(0) }, run: shell.flyoutEnabled }
    ])

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function advance() {
        shell.ticks++
        if (shell.scene < 0) {
            if (shell.ticks < 3) return
            shell.scene = 0
            shell.chosenLog = []
            shell.scenes[0].setup()
            shell.ticks = 0
            return
        }
        var current = shell.scenes[shell.scene]
        if (!shell.ready(current.ready()) && shell.ticks <= 50) return
        current.run()
        shell.scene++
        shell.ticks = 0
        if (shell.scene >= shell.scenes.length) {
            shell.report()
            shell.scene = 1000
            return
        }
        shell.chosenLog = []
        shell.scenes[shell.scene].setup()
    }

    function mainWheelHover() {
        var frame = menu.frameItem
        // The wheel over a disabled row steps the highlight one row and never pixel scrolls.
        var disabled = menu.itemFor(5)
        driver.mouseWheel(disabled, disabled.width / 2, disabled.height / 2, Qt.NoButton, Qt.NoModifier, 0, -120, 1)
        shell.check("main:wheel-steps-one", menu.cursor, 4)
        shell.check("main:wheel-no-pixel-scroll", shell.cardUnder(frame).contentY, 0)
        shell.check("main:card-not-interactive", shell.cardUnder(frame).interactive, false)
        // The highlight still follows the pointer: two moves across an enabled row, the first one arms it.
        var row = menu.itemFor(6)
        driver.mouseMove(row, 10, row.height / 2, 1, Qt.NoButton, Qt.NoModifier)
        driver.mouseMove(row, 20, row.height / 2, 1, Qt.NoButton, Qt.NoModifier)
        shell.check("main:hover-follows", menu.cursor, 6)
        // A submenu row opens its flyout and the menu stays open.
        shell.clickCentre(menu.itemFor(1), Qt.LeftButton)
        shell.check("main:submenu-click-opens", menu.openSubmenuRow, 1)
        shell.check("main:submenu-click-open", menu.opened, true)
    }
    function mainEnabled() {
        shell.clickCentre(menu.itemFor(4), Qt.LeftButton)
        shell.check("main:enabled-once", shell.chosenLog, ["copy"])
        shell.check("main:enabled-closes", menu.opened, false)
    }
    function mainOutside() { shell.outsideClose("main") }

    function flyoutWheelHover() {
        var sub = menu.submenuFrameItem
        var disabled = menu.submenuItemFor(1)
        driver.mouseWheel(disabled, disabled.width / 2, disabled.height / 2, Qt.NoButton, Qt.NoModifier, 0, -120, 1)
        shell.check("flyout:wheel-steps-one", menu.submenuCursor, 3)
        shell.check("flyout:wheel-no-pixel-scroll", shell.cardUnder(sub).contentY, 0)
        var row = menu.submenuItemFor(0)
        driver.mouseMove(row, 10, row.height / 2, 1, Qt.NoButton, Qt.NoModifier)
        driver.mouseMove(row, 20, row.height / 2, 1, Qt.NoButton, Qt.NoModifier)
        shell.check("flyout:hover-follows", menu.submenuCursor, 0)
    }
    function flyoutOutside() { shell.outsideClose("flyout") }
    function flyoutEnabled() {
        shell.clickCentre(menu.submenuItemFor(0), Qt.LeftButton)
        shell.check("flyout:enabled-once", shell.chosenLog, ["openWith:a"])
        shell.check("flyout:enabled-closes", menu.opened, false)
    }
}
