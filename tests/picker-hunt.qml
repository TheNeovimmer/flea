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
            if (!win || win.listingState !== "ready" || !win.rows.length) return
            if (stage === 0) {
                if (win.saving && !win.saveReady) return
                win.cursorIndex = win.rows.findIndex(function(row) { return row.n === "a.txt" }) + win.held
                if (win.cursorIndex < 0) return
                win.focusView()
                if (!win.viewItem().activeFocus) return
                root.check("real cursor is a file", win.rowFor(win.cursorIndex).n, "a.txt")
                if (scenario === "cursor-open") {
                    root.check("cursor file enables Open", win.canAccept, true)
                    console.log("PICKER_HUNT INPUT Return action="
                        + Keymap.lookup(Qt.Key_Return, "", Qt.NoModifier, "listing"))
                    root.press(Qt.Key_Return)
                } else if (scenario === "all") {
                    root.check("Ctrl+A maps to selectAll", Keymap.lookup(Qt.Key_A, "a", Qt.ControlModifier, "listing"), "selectAll")
                    root.press(Qt.Key_A, Qt.ControlModifier)
                } else if (scenario === "range") {
                    root.check("Shift+Down maps to extendDown", Keymap.lookup(Qt.Key_Down, "", Qt.ShiftModifier, "listing"), "extendDown")
                    root.press(Qt.Key_Down, Qt.ShiftModifier)
                } else if (scenario === "path") {
                    root.check("Ctrl+L maps to pathBar", Keymap.lookup(Qt.Key_L, "l", Qt.ControlModifier, "listing"), "pathBar")
                    root.press(Qt.Key_L, Qt.ControlModifier)
                } else if (scenario === "save-marks") {
                    root.press(Qt.Key_Space)
                } else if (scenario === "collision") {
                    win.accept()
                } else if (scenario === "remember") {
                    win.setView(win.viewMode === "grid" ? "list" : "grid")
                } else if (scenario === "control" || scenario === "marked-open") {
                    root.press(win.viewMode === "grid" ? Qt.Key_Right : Qt.Key_Down)
                    root.check("arrow moves the real cursor", win.rowFor(win.cursorIndex).n, "b.txt")
                    root.press(Qt.Key_Space)
                }
                root.stage = 1
                root.stamp = Date.now()
                return
            }
            if (stage === 1 && Date.now() - root.stamp > 1000 && !win.markRequest) {
                if (scenario === "cursor-open") {
                    root.check("Return answers cursor file", win.answered, true)
                    console.log("PICKER_HUNT MESSAGE " + win.message)
                } else if (scenario === "all") {
                    root.check("Ctrl+A marks all twelve files", win.marks.length, 12)
                } else if (scenario === "range") {
                    var rangeCount = win.viewMode === "grid" ? win.viewItem().columns + 1 : 2
                    root.check("Shift+Down marks cursor range", win.marks.length, rangeCount)
                } else if (scenario === "path") {
                    var fields = root.descendants(win.contentItem).filter(function(item) {
                        return item.activeFocus && typeof item.selectAll === "function"
                    })
                    root.check("Ctrl+L focuses path input", fields.length, 1)
                } else if (scenario === "save-marks") {
                    root.check("save mode never marks files", win.marks.length, 0)
                } else if (scenario === "collision") {
                    var form = root.descendants(win.contentItem).filter(function(item) {
                        return item.fieldItem !== undefined && item.askedName !== undefined
                    })[0]
                    root.check("collision focuses Filename", form.fieldItem.activeFocus, true)
                    root.check("collision selects filename stem", form.fieldItem.selectedText, "a")
                    var labels = form.controls().filter(function(item) { return item.visible }).map(function(item) { return item.name })
                    root.check("collision offers Replace", labels.indexOf("Replace") >= 0, true)
                } else if (scenario === "remember") {
                    root.check("view switch updates remembered state", Flea.ViewState.pickerView, win.viewMode)
                } else if (scenario === "control" || scenario === "marked-open") {
                    root.check("Space marks one real file", win.marks.length, 1)
                    if (scenario === "marked-open") {
                        root.check("Mac Return still maps to rename", Keymap.lookup(Qt.Key_Return, "", Qt.NoModifier, "listing"), "rename")
                        root.press(Qt.Key_Return)
                        root.stage = 2
                        root.stamp = Date.now()
                        return
                    }
                }
                root.finish()
            }
            if (stage === 2 && Date.now() - root.stamp > 1000) {
                root.check("marked Mac Return writes portal answer", win.answered, true)
                root.finish()
            }
        }
    }
}
