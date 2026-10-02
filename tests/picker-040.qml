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
                if (scenario === "path") {
                    root.check("Ctrl+L maps to pathBar", Keymap.lookup(Qt.Key_L, "l", Qt.ControlModifier, "listing"), "pathBar")
                    root.press(Qt.Key_L, Qt.ControlModifier)
                } else if (scenario === "collision") {
                    win.accept()
                }
                root.stage = 1
                root.stamp = Date.now()
                return
            }
            if (stage === 1 && Date.now() - root.stamp > 1000 && !win.markRequest) {
                if (scenario === "path") {
                    var fields = root.descendants(win.contentItem).filter(function(item) {
                        return item.activeFocus && typeof item.selectAll === "function"
                    })
                    root.check("Ctrl+L focuses path input", fields.length, 1)
                } else if (scenario === "collision") {
                    var form = root.descendants(win.contentItem).filter(function(item) {
                        return item.fieldItem !== undefined && item.askedName !== undefined
                    })[0]
                    root.check("collision focuses Filename", form.fieldItem.activeFocus, true)
                    root.check("collision selects filename stem", form.fieldItem.selectedText, "a")
                    var labels = form.controls().filter(function(item) { return item.visible }).map(function(item) { return item.name })
                    root.check("collision offers Replace", labels.indexOf("Replace") >= 0, true)
                }
                root.finish()
            }
        }
    }
}
