//@ pragma ShellId flea-button-members-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Protocols.js" as Protocols
import "flea/js/TextSize.js" as TextSize
import "button-probe.js" as Probe

// tests/button-system.sh's second harness: the controls that took ButtonSystem040 A late, the protocol members, the picker's answers and marks, and the Copy to field, held to A's numbers.
ShellRoot {
    id: shell

    readonly property real rulingHover: 0.08
    readonly property real rulingPress: 0.14
    readonly property real rulingPressScale: 0.96
    readonly property real rulingDisabled: 0.55
    readonly property int rulingRing: 2
    readonly property int rulingHeight: 30
    readonly property int rulingSetGap: 4
    readonly property real alphaEpsilon: 0.002
    readonly property int parkX: 760
    readonly property int parkY: 1100
    readonly property int releaseOutside: -40
    readonly property int noDelay: 0
    readonly property int settleTicks: 4
    readonly property int tickMs: 16
    readonly property int outerTimeoutS: Number(Quickshell.env("BUTTONSYS_TIMEOUT_S")) || 60
    readonly property int capShare: 2
    readonly property int msPerSecond: 1000
    readonly property double startedAt: Date.now()
    readonly property int capMs: shell.outerTimeoutS * shell.msPerSecond / shell.capShare
    // GM's text size, where body is 14 and the control 30 (ButtonSystem040).
    readonly property int pinnedSize: 14
    readonly property string rootDir: Quickshell.env("BUTTONSYS_ROOT") || ""
    readonly property var states: ["rest", "hover", "focus", "pressed", "disabled"]

    property int checks: 0
    property var failures: []
    property var readings: ({})
    property int step: 0
    property int quiet: 0
    property real lastScale: -1
    property bool acted: false
    property var script: []
    property int cancels: 0
    property int accepts: 0
    property var stepped: []

    function log(line) { console.log("MEMBERS " + line) }
    function check(name, actual, expected) {
        shell.checks += 1
        if (JSON.stringify(actual) === JSON.stringify(expected)) { shell.log("ok " + name); return }
        shell.failures.push(name)
        shell.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function finish() {
        shell.log("DONE checks=" + shell.checks + " failed=" + shell.failures.length)
        shell.step = shell.script.length + 1
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    function near(a, b) { return Math.abs(a - b) < shell.alphaEpsilon }
    function underRoot(path) {
        return shell.rootDir.length > 0 && path.indexOf(shell.rootDir + "/") === 0 && path.split("/").indexOf("..") < 0
    }

    // The five states of one control; each act leaves the pointer and keyboard as the state needs them.
    function seriesFor(key, item, avail, activations) {
        shell.readings[key] = {}
        function record(state) { return function () { shell.readings[key][state] = Probe.read(item) } }
        return [
            { item: item, name: key + ":rest", act: function () { parking.forceActiveFocus(); shell.park() }, record: record("rest") },
            { item: item, name: key + ":hover", act: function () { shell.hoverOn(item) }, record: record("hover") },
            { item: item, name: key + ":focus", act: function () { shell.park(); item.forceActiveFocus() }, record: record("focus") },
            { item: item, name: key + ":pressed", act: function () { parking.forceActiveFocus(); shell.hoverOn(item); shell.pressOn(item) }, record: record("pressed") },
            { item: item, name: key + ":released", act: function () { shell.releaseOff(item); shell.park() }, record: function () {
                shell.check(key + ": a press released outside does not activate", activations(), 0)
            } },
            { item: item, name: key + ":disabled", act: function () { avail(false) }, record: record("disabled") },
            { item: item, name: key + ":disabled-input", act: function () {
                item.forceActiveFocus(); shell.hoverOn(item); shell.pressOn(item); shell.releaseOff(item)
                driver.keyClick(Qt.Key_Return, Qt.NoModifier, shell.noDelay)
            }, record: function () {
                shell.check(key + ": a disabled control activates on neither pointer nor Return", activations(), 0)
                avail(true)
            } }
        ]
    }

    // A is one ladder: the frame never changes, hover is 8% and press 14% of the ink laid inside the frame, press scales, focus is the ring, disabled dims.
    function ladder(key, ink, frame) {
        var r = shell.readings[key]
        for (var i = 0; i < shell.states.length; i++) {
            var state = shell.states[i]
            shell.check(key + " " + state + ": a 30 px control with a 30 px frame at body size", [r[state].outerHeight, r[state].frameHeight, r[state].labelSize], [shell.rulingHeight, shell.rulingHeight, Flea.Theme.font.body])
            var off = state === "disabled"
            shell.check(key + " " + state + ": the frame is one hairline in " + (off ? "muted" : frame), [r[state].frameColor, r[state].frameWidth], [off ? Probe.rgba(Flea.Theme.color.muted) : frame, Flea.Theme.spacing.hairline])
            shell.check(key + " " + state + ": the label inks " + (off ? "muted" : ink), r[state].ink, off ? Probe.rgba(Flea.Theme.color.muted) : ink)
            shell.check(key + " " + state + ": the wash lies one hairline inside the frame, so the frame never changes",
                        [r[state].washInsetX, r[state].washInsetY, r[state].washShrink], [Flea.Theme.spacing.hairline, Flea.Theme.spacing.hairline, 2 * Flea.Theme.spacing.hairline])
        }
        shell.check(key + ": hover lays 8% of the ink and press 14% with the 0.96 scale",
                    [shell.near(r.hover.washAlpha, shell.rulingHover), shell.near(r.pressed.washAlpha, shell.rulingPress), r.pressed.scale], [true, true, shell.rulingPressScale])
        shell.check(key + ": the ring is the 2 px foreground ring outside, on focus alone",
                    [r.rest.ringShown, r.hover.ringShown, r.pressed.ringShown, r.focus.ringShown, r.focus.ringWidth, r.focus.ringColor, r.focus.ringOutset],
                    [false, false, false, true, shell.rulingRing, Probe.rgba(Flea.Theme.color.foreground), shell.rulingRing])
        shell.check(key + ": disabled is 0.55 with no ring", [r.disabled.opacity, r.disabled.ringShown], [shell.rulingDisabled, false])
    }

    FloatingWindow {
        id: window
        implicitWidth: 800
        implicitHeight: 1200
        color: "#303030"

        Item {
            id: formHost
            width: 460
            height: 700
            Flea.NetworkForm { id: form; width: parent.width }
        }

        Item {
            id: fieldHost
            y: 720
            width: 460
            height: 80
            Flea.DialogField { id: referenceField; width: parent.width; label: "Reference" }
        }

        Item {
            id: pickerHost
            y: 820
            width: 800
            height: 160
            Flea.PickerChrome {
                id: chrome
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                picker: picker
                onCancelRequested: shell.cancels += 1
                onAcceptRequested: shell.accepts += 1
            }
        }

        // A plain primary dialog button, whose wash is held inside its frame in every state (the frame never lightens under it).
        Item {
            id: plainHost
            y: 1000
            width: 460
            height: 60
            Flea.DialogButton { id: plain; x: 20; y: 10; label: "Plain"; primary: true }
        }

        // The Copy to dialog fills this host while it is open, and is shut when the pointer series run.
        Item {
            id: dialogHost
            width: 800
            height: 700
            Flea.MenuActionDialog { id: copyTo }
        }

        Item { id: parking; y: 1190; width: 10; height: 10; focus: true }

        TestEvent { id: driver }
    }

    // The picker's own face as PickerChrome reads it; a Tab reports through stepFocus and moves nothing.
    QtObject {
        id: picker
        property var req: ({ mode: "open", title: "Choose file", app: "", accept: "", multiple: false, filters: [{ label: "Images" }] })
        property color edge: "#444444"
        property var marks: []
        property bool canAccept: true
        property var history: ["/a"]
        property bool backendUnavailable: false
        property bool submitting: false
        property bool recent: false
        property bool answered: false
        property string path: "/home/x/y"
        property string home: "/home/x"
        property int filterIndex: 0
        property string viewMode: "list"
        function stepFocus(from, back) { shell.stepped.push([from.name, back]) }
        function control(name, item, available) { return { name: name } }
    }

    function centre(item) { return { x: item.width / 2, y: item.height / 2 } }
    function park() { driver.mouseMove(formHost, shell.parkX, shell.parkY, shell.noDelay, Qt.NoButton, Qt.NoModifier) }
    function hoverOn(item) { var c = shell.centre(item); driver.mouseMove(item, c.x, c.y, shell.noDelay, Qt.NoButton, Qt.NoModifier) }
    function pressOn(item) { var c = shell.centre(item); driver.mousePress(item, c.x, c.y, Qt.LeftButton, Qt.NoModifier, shell.noDelay) }
    function releaseOff(item) { driver.mouseRelease(item, shell.releaseOutside, shell.releaseOutside, Qt.LeftButton, Qt.NoModifier, shell.noDelay) }
    function settled(item) {
        var same = item.scale === shell.lastScale
        shell.lastScale = item.scale
        shell.quiet = same ? shell.quiet + 1 : 0
        return shell.quiet >= shell.settleTicks
    }
    // The strip the answers sit in is the Row's parent's parent: Row, then the title strip.
    function askOf(button) { return button.parent.parent }

    // The set: five members 30 tall at body 14, 4 apart, the current one framed and inked in foreground.
    function members() {
        var names = Protocols.PROTOCOLS
        var items = names.map(function (n) { return form.chipFor(n) })
        shell.check("the form draws every protocol as a member", items.every(function (i) { return i !== null }), true)
        shell.check("every member is 30 tall at body 14",
                    items.map(function (i) { var r = Probe.read(i); return [r.outerHeight, r.frameHeight, r.labelSize] }),
                    names.map(function () { return [shell.rulingHeight, shell.rulingHeight, Flea.Theme.font.body] }))
        var gaps = []
        for (var i = 1; i < items.length; i++) gaps.push(items[i].x - (items[i - 1].x + items[i - 1].width))
        shell.check("members sit 4 apart", gaps, gaps.map(function () { return shell.rulingSetGap }))
        var picked = Probe.read(items[0])
        var foreground = Probe.rgba(Flea.Theme.color.foreground)
        shell.check("the picked member keeps a foreground frame and label", [picked.frameColor, picked.ink, picked.washAlpha], [foreground, foreground, 0])
        shell.check("an unpicked member rests in a muted frame and label", [Probe.read(items[1]).frameColor, Probe.read(items[1]).ink],
                    [Probe.rgba(Flea.Theme.color.muted), Probe.rgba(Flea.Theme.color.muted)])
        items[1].takeFocus()
        driver.keyClick(Qt.Key_Return, Qt.NoModifier, shell.noDelay)
        shell.check("Return on a focused member picks it", [form.protocol, items[1].picked, items[0].picked], ["SFTP", true, false])
        form.pick("SMB")
        shell.check("a member is no Tab stop of Qt's own", items[1].activeFocusOnTab, false)
    }

    // The picker's answers are A's control; its marks wear no frame.
    function answers() {
        var cancel = chrome.focusItems()[0]
        var accept = chrome.focusItems()[1]
        var ask = shell.askOf(accept)
        var accentFrame = Probe.rgba(Flea.Theme.color.accentFrame)
        var muted = Probe.rgba(Flea.Theme.color.muted)
        var foreground = Probe.rgba(Flea.Theme.color.foreground)
        shell.check("Cancel and Open are the one control", [cancel.label, accept.label, cancel.primary, accept.primary], ["Cancel", "Open", false, true])
        shell.check("the answers sit inside the title strip", [cancel.height <= ask.height, accept.height <= ask.height], [true, true])
        var focused = shell.readings.accept.focus
        var ring = Probe.find(accept, "buttonRing")
        var box = ring ? ring.mapToItem(ask, 0, 0) : null
        if (box) shell.log("info title strip " + ask.height + " tall, ring from " + box.y + " to " + (box.y + ring.height) + ", the strip's rule at " + (ask.height - Flea.Theme.spacing.hairline))
        shell.check("the focus ring stays inside the title strip", box !== null && box.y >= 0 && box.y + ring.height <= ask.height, true)
        shell.check("the enabled primary is the accent frame, the secondary the muted one", [shell.readings.accept.rest.frameColor, shell.readings.cancel.rest.frameColor], [accentFrame, muted])
        var off = shell.readings.accept.disabled
        shell.check("a disabled Open is the muted frame and label at 0.55, with no wash", [off.frameColor, off.ink, off.opacity, off.frameFill], [muted, muted, shell.rulingDisabled, 0])
        shell.check("keyboard focus on Open is the ring over the unchanged accent frame", [focused.ringShown, focused.frameColor], [true, accentFrame])
        shell.check("the primary's resting wash is the 14% accent", shell.near(shell.readings.accept.rest.frameFill, shell.rulingPress), true)
        parking.forceActiveFocus()
        driver.mouseClick(cancel, cancel.width / 2, cancel.height / 2, Qt.LeftButton, Qt.NoModifier, shell.noDelay)
        shell.check("a click answers and takes no keyboard focus, so no ring", [shell.cancels, cancel.activeFocus, Probe.read(cancel).ringShown], [1, false, false])
        cancel.forceActiveFocus()
        driver.keyClick(Qt.Key_Tab, Qt.NoModifier, shell.noDelay)
        driver.keyClick(Qt.Key_Backtab, Qt.ShiftModifier, shell.noDelay)
        shell.check("Tab and Shift Tab on an answer report to the picker's own order", shell.stepped, [["Cancel", false], ["Cancel", true]])
        shell.marks(muted, foreground)
    }
    // Back, Up and both view marks are frameless chrome marks: muted at rest, lifted by the keyboard, never boxed.
    function marks(muted, foreground) {
        var all = shell.markItems()
        shell.check("Back, Up and both view marks are chrome marks", all.every(function (m) { return !!m }), true)
        if (!all.every(function (m) { return !!m })) return
        shell.check("Back, Up and both view marks draw no frame", all.map(Probe.bordered), all.map(function () { return 0 }))
        shell.check("a mark's hit box is the strip's height and never under 24", all.map(function (m) { return m.height >= Flea.Theme.hitMin && m.height === Flea.Theme.chromeHeight }), all.map(function () { return true }))
        var back = chrome.focusItems()[2]
        shell.check("Back and Up rest muted and name themselves", [shell.markInk(back), back.name, chrome.focusItems()[3].name], [muted, "Back", "Parent folder"])
        back.forceActiveFocus()
        shell.check("the keyboard lifts a mark to the foreground, drawing no ring", [shell.markInk(back), Probe.bordered(back)], [foreground, 0])
        parking.forceActiveFocus()
        picker.history = []
        shell.check("a mark with nowhere to go is disabled and out of the Tab walk", [back.enabled, back.available, back.activeFocusOnTab], [false, false, false])
        picker.history = ["/a"]
        var list = all[2]
        var grid = all[3]
        shell.check("the shown view's mark is lit in the foreground and the other muted", [shell.markInk(list), shell.markInk(grid)], [foreground, muted])
        shell.check("the view marks stay out of the Tab walk", [list.activeFocusOnTab, grid.activeFocusOnTab], [false, false])
        shell.check("a filter chip is left as it was: 24 tall in its own frame", [chrome.focusItems()[4].height, Probe.bordered(chrome.focusItems()[4]) > 0], [Flea.Theme.hitMin, true])
    }
    // Back, Up, List view, Grid view.
    function markItems() {
        var out = []
        var stack = [chrome]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o.glyph !== undefined && o.accessName !== undefined && o.keyboardFocused !== undefined) out.push(o)
            var kids = o.children !== undefined ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        var order = ["arrow-left", "arrow-up", "list", "grid"]
        return order.map(function (g) { return out.filter(function (m) { return m.glyph === g })[0] })
    }
    function markInk(mark) {
        var stack = [mark]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o.name === mark.glyph && o.color !== undefined) return Probe.rgba(o.color)
            for (var i = 0; i < o.children.length; i++) stack.push(o.children[i])
        }
        return ""
    }

    // The Copy to, Move to and New file field is the height of the buttons beside it and of DialogField's own box.
    function field() {
        var out = []
        var actions = ["copyTo", "moveTo", "newFile"]
        for (var i = 0; i < actions.length; i++) {
            copyTo.open(actions[i], 1, "/box", null)
            var box = copyTo.fieldItem.parent
            var mid = copyTo.fieldItem.y + copyTo.fieldItem.height / 2
            out.push([box.height, copyTo.closeItem.height, copyTo.submitItem.height, Math.abs(mid - box.height / 2) < 1])
            copyTo.close()
        }
        var reference = referenceField.input.parent.height
        shell.check("the field is DialogField's own 30 beside 30 px buttons, its text centred", [reference, out],
                    [shell.rulingHeight, out.map(function () { return [shell.rulingHeight, shell.rulingHeight, shell.rulingHeight, true] })])
    }

    Timer {
        interval: shell.tickMs
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function buildScript() {
        var chip = form.chipFor("SFTP")
        var steps = []
        steps = steps.concat(shell.seriesFor("member", chip, function (on) { if (chip.available !== undefined) chip.available = on }, function () { return form.protocol === "SMB" ? 0 : 1 }))
        var cancel = chrome.focusItems()[0]
        var accept = chrome.focusItems()[1]
        steps = steps.concat(shell.seriesFor("cancel", cancel, function (on) { if (cancel.available !== undefined) cancel.available = on }, function () { return shell.cancels }))
        steps = steps.concat(shell.seriesFor("accept", accept, function (on) { picker.canAccept = on }, function () { return shell.accepts }))
        steps = steps.concat(shell.seriesFor("plain", plain, function (on) { plain.available = on }, function () { return 0 }))
        steps.push({ item: parking, name: "check", act: function () {}, record: function () {
            shell.check("the harness draws at GM's text size", Flea.Theme.baseSize, shell.pinnedSize)
            shell.check("the harness runs with motion on, so the press scale is drawn", Flea.Theme.reducedMotion, false)
            var muted = Probe.rgba(Flea.Theme.color.muted)
            shell.ladder("member", muted, muted)
            shell.check("member: an unpicked member keeps its muted frame on focus, so it never reads as picked", shell.readings.member.focus.frameColor, muted)
            shell.ladder("cancel", Probe.rgba(Flea.Theme.color.foreground), muted)
            shell.ladder("plain", Probe.rgba(Flea.Theme.color.foreground), Probe.rgba(Flea.Theme.color.accentFrame))
            shell.ladder("accept", Probe.rgba(Flea.Theme.color.foreground), Probe.rgba(Flea.Theme.color.accentFrame))
            shell.members()
            shell.answers()
            shell.field()
        } })
        shell.script = steps
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
            // Assigned only once the store lies under the root, because it may write on assignment.
            var inside = shell.underRoot(Flea.ViewState.store.path) && shell.underRoot(Quickshell.env("HOME") || "")
            shell.check("sandbox: the state file and HOME lie under the harness root", inside, true)
            if (!inside) { shell.finish(); return }
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
            return
        }
        if (!shell.settled(current.item)) return
        current.record()
        shell.acted = false
        shell.step += 1
    }
}
