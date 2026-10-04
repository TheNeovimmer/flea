//@ pragma ShellId flea-permissions-skips-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/permissions-skips.sh's harness: the several-items card counts only the files it will change, names the rest in one sentence, and draws its title strip on the board's rows.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0
    property var sent: []
    readonly property int boardStop: 14
    // Owner R W X, Group R W X, Everyone R W X, as the grid reads them.
    readonly property var gridBits: [256, 128, 64, 32, 16, 8, 4, 2, 1]
    readonly property int ownerExecute: 64
    // Permissions040 draws the title glyphs on rows 7-16 from the card top, esc on 10-16 and the lock on 7-20; at base 14 the 17 px line boxes and the 16 px lock sit at these tops.
    // Text size 14 in a window 800 px wide, the narrowest the post-Apply line must fit whole in, with a 20-character name.
    readonly property int statusWindowWidth: 800
    readonly property string longestName: "twenty-char-name.txt"
    readonly property var boardStripTops: ({ lock: 5, title: 4, esc: 4 })

    function log(line) { console.log("PERMSKIP " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        if (cond) shell.log("PASS " + name)
        else shell.failures.push(name + " got " + detail)
    }
    // Sample backend: {"c":"permissions","op":"inspect","id":1000,"path":"/a"} answers its mode and reason in arrival order.
    function answer(marked, answers) {
        var order = 0
        for (var i = marked; i < shell.sent.length; i++) {
            if (shell.sent[i].op !== "inspect") continue
            dialog.receiveMany({op: "inspect", id: shell.sent[i].id, ok: true, mode: answers[order][0], reason: answers[order][1]})
            order += 1
        }
    }
    function open(paths, answers) {
        var marked = shell.sent.length
        dialog.openMany(paths, holder)
        shell.answer(marked, answers)
    }
    function reads() {
        var out = []
        for (var i = 0; i < shell.gridBits.length; i++) out.push(dialog.multiValue(shell.gridBits[i]))
        return out.join(",")
    }
    function checkStrip() {
        var tops = {}
        if (!dialog.stripItems) { shell.check("strip marks sit on the board's rows", false, "the dialog exposes no stripItems"); return }
        for (var name in shell.boardStripTops) tops[name] = dialog.stripItems[name].mapToItem(dialog.cardItem, 0, 0).y
        shell.check("strip marks sit on the board's rows", JSON.stringify(tops) === JSON.stringify(shell.boardStripTops), JSON.stringify(tops))
    }

    Item { id: holder }

    // The real StatusBar, which draws the line the dialog's changed note becomes and elides its middle when it does not fit.
    Item {
        width: shell.statusWindowWidth
        height: bar.implicitHeight
        Flea.StatusBar {
            id: bar
            width: shell.statusWindowWidth
            path: "/d"
            total: 5
            listingState: "ready"
            fsName: "overlay"
            fsFree: 142300000000
        }
    }
    // The note the dialog's Apply hands the status bar, as ui/WindowBody.qml says it.
    property string appliedNote: ""
    function checkStatusLine() {
        shell.check("status-bar-shows-the-one-skip-line-whole",
            shell.appliedNote.indexOf(shell.longestName) >= 0 && bar.primaryItem.text === shell.appliedNote && !bar.primaryItem.truncated,
            bar.primaryItem.text + "|truncated=" + bar.primaryItem.truncated + "|width=" + bar.primaryItem.width + "/" + bar.primaryItem.implicitWidth)
    }

    FloatingWindow {
        implicitWidth: 904
        implicitHeight: 699
        color: "#303030"
        Flea.PermissionsDialog { id: dialog }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function advance() {
        shell.ticks += 1
        if (shell.ticks < 2) return
        var setuid = "Read-only: setuid bit is present."
        if (shell.phase === 0) {
            // a.txt 0644 beside special.txt 4644: the card skips the second, so nothing is mixed and Owner R/W, Group R, Everyone R read on.
            shell.open(["/d/a.txt", "/d/special.txt"], [["0644", ""], ["4644", setuid]])
            shell.check("skipped-file-sets-and-mixes-nothing", shell.reads() === "on,on,off,on,off,off,on,off,off", shell.reads())
            shell.check("skipped-file-shows-no-bar", dialog.multiSummary.mixed === false, String(dialog.multiSummary.mixed))
            shell.check("skipped-file-is-named-in-one-sentence", dialog.displayedError === "special.txt keeps its mode because its setuid bit is set.", dialog.displayedError)
            shell.phase = 1
        } else if (shell.phase === 1) {
            shell.open(["/d/a.txt", "/d/b.txt", "/d/c.txt"], [["0644", ""], ["2755", "Read-only: setgid bit is present."], ["1777", "Read-only: sticky bit is present."]])
            shell.check("two-skipped-files-share-one-line", dialog.displayedError === "2 items keep their modes because a special bit is set: b.txt, c.txt.", dialog.displayedError)
            shell.check("two-skipped-files-mix-nothing", dialog.multiSummary.mixed === false, String(dialog.multiSummary.mixed))
            shell.phase = 2
        } else if (shell.phase === 2) {
            shell.open(["/d/a.txt", "/d/b.txt"], [["0644", ""], ["0755", "Read-only: you are not the owner."]])
            shell.check("foreign-file-mixes-no-bit", dialog.multiValue(shell.ownerExecute) === "off" && dialog.multiSummary.mixed === false, dialog.multiValue(shell.ownerExecute))
            shell.check("foreign-file-is-named-in-one-sentence", dialog.displayedError === "b.txt keeps its mode because you do not own it.", dialog.displayedError)
            shell.phase = 3
        } else if (shell.phase === 3) {
            // Permissions040: two files that are both 4644 draw rw-r--r-- at the disabled opacity, with Apply disabled and the note kept, as one unchangeable file does.
            shell.open(["/d/special.txt", "/d/x-special.txt"], [["4644", setuid], ["4644", setuid]])
            shell.check("all-skipped-boxes-show-the-files-bits", shell.reads() === "on,on,off,on,off,off,on,off,off", shell.reads())
            var controls = dialog.controls()
            var boxes = controls.filter(function (control) { return control.bit !== undefined })
            var apply = controls.filter(function (control) { return control.name === "Apply" })[0]
            shell.check("all-skipped-card-is-not-editable-and-apply-is-disabled",
                !dialog.editable && boxes.length === shell.gridBits.length && boxes.every(function (control) { return !control.enabled }) && !apply.enabled,
                dialog.editable + "/" + boxes.length + "/" + apply.enabled)
            var before = shell.sent.length
            dialog.apply()
            shell.check("all-skipped-apply-sends-nothing", shell.sent.length === before && !dialog.applyingMany, shell.sent.length + "/" + before)
            shell.check("all-skipped-card-keeps-its-note", dialog.displayedError === "2 items keep their modes because a special bit is set: special.txt, x-special.txt.", dialog.displayedError)
            shell.open(["/d/special.txt", "/d/y.txt"], [["4644", setuid], ["4755", setuid]])
            shell.check("all-skipped-files-that-differ-show-a-bar", dialog.multiValue(shell.ownerExecute) === "some" && !dialog.editable, shell.reads() + "/" + dialog.editable)
            shell.open(["/d/a.txt", "/d/special.txt"], [["0644", ""], ["4644", setuid]])
            shell.check("one-changeable-file-keeps-the-card-editable", dialog.editable && dialog.multiSummary.changeable, String(dialog.editable))
            shell.phase = 4
        } else if (shell.phase === 4) {
            Flea.ViewState.load(JSON.stringify({ display: { textSize: { mode: shell.boardStop } } }))
            shell.open(["/d/a.txt", "/d/b.txt", "/d/c.txt"], [["0644", ""], ["0600", ""], ["0755", ""]])
            shell.phase = 5
        } else if (shell.phase === 5) {
            shell.checkStrip()
            shell.phase = 6
        } else if (shell.phase === 6) {
            // One file changes and the 20-character one is skipped; the backend's ok reply closes the card and the note rides to the status bar.
            shell.open(["/d/a.txt", "/d/" + shell.longestName], [["0644", ""], ["4644", setuid]])
            dialog.applyMany()
            dialog.receiveMany({ op: "applyMany", id: dialog.requestId, ok: true })
            shell.phase = 7
        } else if (shell.phase === 7) {
            shell.checkStatusLine()
            shell.phase = 8
        } else if (shell.phase === 8) {
            for (var i = 0; i < shell.failures.length; i++) shell.log("FAIL " + shell.failures[i])
            shell.log("DONE failures=" + shell.failures.length)
            shell.phase = 9
            shell.quit()
        }
    }

    Component.onCompleted: {
        dialog.requested.connect(function (m) { shell.sent.push(m) })
        dialog.changed.connect(function (note) { shell.appliedNote = note; bar.say(note, false) })
    }
}
