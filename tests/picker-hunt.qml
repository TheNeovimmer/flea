import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Keymap.js" as Keymap

// Drive the real picker and its real backend, with native Qt key events.
ShellRoot {
    id: root
    property var pickerShell: null
    property var win: null
    property var keys: null
    property string scenario: Quickshell.env("FLEA_PICKER_HUNT_CASE")
    property int stage: 0
    property double stamp: Date.now()
    property int failures: 0
    property int checks: 0
    readonly property int burstSteps: 3

    function check(label, got, want) {
        checks++
        var ok = JSON.stringify(got) === JSON.stringify(want)
        if (!ok) failures++
        console.log("PICKER_HUNT " + (ok ? "PASS " : "FAIL ") + label
            + " got=" + JSON.stringify(got) + " expected=" + JSON.stringify(want))
    }
    function finish() {
        console.log("PICKER_HUNT DONE " + checks + " checks, " + failures + " failed")
        Qt.exit(failures ? 1 : 0)
    }
    function descendants(item) {
        var out = [item]
        for (var i = 0; i < out.length; i++) {
            var kids = out[i].children || []
            for (var j = 0; j < kids.length; j++) out.push(kids[j])
        }
        return out
    }
    function pressOpen() {
        var button = descendants(win.contentItem).filter(function(item) {
            return item.primary === true && item.name.indexOf("Open") === 0
        })[0]
        check("real Open button exists", !!button, true)
        if (!button) return
        check("real Open button available", button.available, true)
        keys.mouseClick(button, button.width / 2, button.height / 2, Qt.LeftButton, Qt.NoModifier, -1)
    }
    function press(key, modifiers) { keys.keyClick(key, modifiers || Qt.NoModifier, -1) }

    Component.onCompleted: {
        var comp = Qt.createComponent("flea/PickerWindow.qml")
        if (comp.status !== Component.Ready) {
            console.log("PICKER_HUNT FAIL compile " + comp.errorString())
            Qt.exit(1)
            return
        }
        pickerShell = comp.createObject(root)
        win = pickerShell.pickerWin
        keys = Qt.createQmlObject("import QtTest; TestEvent {}", win.contentItem)
    }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            if (Date.now() - root.stamp > 8000) {
                root.check("probe completes", "timeout stage " + stage, "complete")
                root.finish()
                return
            }
            if (win && scenario === "empty" && win.listingState === "empty") {
                root.check("empty listing disables Open", win.canAccept, false)
                var emptyButton = root.descendants(win.contentItem).filter(function(item) { return item.name === "Open" && item.available !== undefined })[0]
                root.check("empty Open opacity", emptyButton.opacity, 0.55)
                root.finish()
                return
            }
            if (!win || win.listingState !== "ready" || !win.rows.length) return
            if (stage === 0) {
                if (win.saving && !win.saveReady) return
                root.check("requested key preset loaded", Flea.ViewState.keysPreset, Quickshell.env("FLEA_PICKER_HUNT_PRESET"))
                if (scenario === "folder") {
                    win.cursorIndex = 0
                    win.focusView()
                    root.check("folder disables Open", win.canAccept, false)
                    var folderButton = root.descendants(win.contentItem).filter(function(item) { return item.name === "Open" && item.available !== undefined })[0]
                    root.check("folder Open opacity", folderButton.opacity, 0.55)
                    root.press(Qt.Key_Return)
                    root.stage = 1
                    root.stamp = Date.now()
                    return
                }
                win.cursorIndex = win.rows.findIndex(function(row) { return row.n === "a.txt" }) + win.held
                if (win.cursorIndex < 0) return
                win.focusView()
                if (!win.viewItem().activeFocus) return
                root.check("real cursor is a file", win.rowFor(win.cursorIndex).n, "a.txt")
                if (scenario.indexOf("cursor-") === 0) {
                    root.check("cursor file enables Open", win.canAccept, true)
                    console.log("PICKER_HUNT INPUT Return action="
                        + Keymap.lookup(Qt.Key_Return, "", Qt.NoModifier, "listing"))
                    if (scenario === "cursor-button") root.pressOpen()
                    else root.press(scenario === "cursor-enter" ? Qt.Key_Enter : Qt.Key_Return, scenario === "cursor-enter" ? Qt.KeypadModifier : Qt.NoModifier)
                } else if ((scenario === "all" || scenario === "all-wide")) {
                    root.check("Ctrl+A maps to selectAll", Keymap.lookup(Qt.Key_A, "a", Qt.ControlModifier, "listing"), "selectAll")
                    root.press(Qt.Key_A, Qt.ControlModifier)
                } else if (scenario === "range-up" || scenario === "range-click") {
                    var index = win.cursorIndex
                    if (scenario === "range-up") {
                        win.cursorIndex = index + (win.viewMode === "grid" ? win.viewItem().columns : 1)
                        root.press(Qt.Key_Up, Qt.ShiftModifier)
                    } else {
                        var cell = win.viewItem().itemAtIndex(index + 2)
                        keys.mouseClick(cell, cell.width - 5, cell.height / 2, Qt.LeftButton, Qt.ShiftModifier, -1)
                    }
                } else if (scenario === "range-burst") {
                    for (var burst = 0; burst < root.burstSteps; burst++) root.press(Qt.Key_Down, Qt.ShiftModifier)
                } else if (scenario === "range" || scenario === "range-shrink") {
                    root.check("Shift+Down maps to extendDown", Keymap.lookup(Qt.Key_Down, "", Qt.ShiftModifier, "listing"), "extendDown")
                    root.press(Qt.Key_Down, Qt.ShiftModifier)
                } else if (scenario === "save-marks" || scenario === "single-marks") {
                    root.press(Qt.Key_Space)
                    root.press(Qt.Key_Down, Qt.ShiftModifier)
                    root.press(Qt.Key_A, Qt.ControlModifier)
                } else if (scenario === "remember") {
                    win.setView(win.viewMode === "grid" ? "list" : "grid")
                } else if (scenario === "control" || (scenario === "marked-open" || scenario === "marked-enter")) {
                    root.press(win.viewMode === "grid" ? Qt.Key_Right : Qt.Key_Down)
                    root.check("arrow moves the real cursor", win.rowFor(win.cursorIndex).n, "b.txt")
                    root.press(Qt.Key_Space)
                }
                root.stage = 1
                root.stamp = Date.now()
                return
            }
            if (stage === 1 && Date.now() - root.stamp > 1000 && !win.markRequest) {
                if (scenario.indexOf("cursor-") === 0) {
                    root.check("Return answers cursor file", win.answered, true)
                    console.log("PICKER_HUNT MESSAGE " + win.message)
                } else if ((scenario === "all" || scenario === "all-wide")) {
                    root.check("Ctrl+A marks all twelve files", win.marks.length, scenario === "all-wide" ? 212 : 12)
                    if (scenario === "all-wide") root.check("select-all reaches beyond held window", win.rows.length < win.marks.length, true)
                } else if (scenario === "range-up" || scenario === "range-click") {
                    var wanted = scenario === "range-click" ? 3 : win.viewMode === "grid" ? win.viewItem().columns + 1 : 2
                    root.check("Shift+Up or click marks range", win.marks.length, wanted)
                } else if (scenario === "folder") {
                    root.check("Enter walks into cursor folder", win.path.slice(-9), "/z-folder")
                    root.check("folder navigation does not answer", win.answered, false)
                } else if (scenario === "range" || scenario === "range-burst" || scenario === "range-shrink") {
                    var stride = win.viewMode === "grid" ? win.viewItem().columns : 1
                    var rangeCount = scenario === "range-burst" ? root.burstSteps * stride + 1 : stride + 1
                    root.check("Shift+Down marks cursor range", win.marks.length, rangeCount)
                    if (scenario === "range-shrink") {
                        root.press(Qt.Key_Up, Qt.ShiftModifier)
                        root.stage = 2
                        root.stamp = Date.now()
                        return
                    }
                } else if (scenario === "save-marks" || scenario === "single-marks") {
                    root.check("save mode never marks files", win.marks.length, 0)
                    var cells = root.descendants(win.viewItem()).filter(function(item) { return item.listingIndex !== undefined })
                    root.check("box probe sees real delegates", cells.length > 0, true)
                    root.check("save or single-file rows have no boxes", cells.every(function(cell) { return cell.markable === false }), true)
                } else if (scenario === "remember") {
                    root.check("view switch updates remembered state", Flea.ViewState.pickerView, win.viewMode)
                } else if (scenario === "control" || (scenario === "marked-open" || scenario === "marked-enter")) {
                    root.check("Space marks one real file", win.marks.length, 1)
                    if ((scenario === "marked-open" || scenario === "marked-enter")) {
                        root.check("marked file is b.txt", win.marks[0].path.split("/").pop(), "b.txt")
                        root.press(win.viewMode === "grid" ? Qt.Key_Right : Qt.Key_Down)
                        root.check("cursor moves off marked file", win.rowFor(win.cursorIndex).n, "c.txt")
                        var preset = Flea.ViewState.keysPreset
                        root.check("Return follows current preset", Keymap.lookup(Qt.Key_Return, "", Qt.NoModifier, "listing"), preset === "mac" ? "rename" : "open")
                        root.press(scenario === "marked-enter" ? Qt.Key_Enter : Qt.Key_Return, scenario === "marked-enter" ? Qt.KeypadModifier : Qt.NoModifier)
                        root.stage = 2
                        root.stamp = Date.now()
                        return
                    }
                }
                root.finish()
            }
            if (stage === 2 && Date.now() - root.stamp > 1000) {
                if (scenario === "range-shrink") root.check("range shrink keeps only anchor", win.marks.length, 1)
                else root.check("marked Return or Enter writes portal answer", win.answered, true)
                root.finish()
            }
        }
    }
}
