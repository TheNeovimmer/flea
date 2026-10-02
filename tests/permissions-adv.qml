//@ pragma ShellId flea-permissions-adv-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/permissions-adv.sh's harness: the multi-row Permissions card's advloop findings, red first.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0

    function log(line) { console.log("PERMADV " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        if (cond) shell.log("PASS " + name)
        else shell.failures.push(name + " got " + detail)
    }

    Item {
        id: holder
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        Flea.PermissionsDialog {
            id: dialog
        }
    }

    // Sample backend: {"c":"permissions","op":"inspect","id":1000,"path":"/a"} answers mode and reason.
    property var sent: []
    function answerInspects(marked, modeA, reasonA, modeB, reasonB) {
        var order = 0
        for (var i = marked; i < shell.sent.length; i++) {
            var m = shell.sent[i]
            if (m.op !== "inspect") continue
            if (order === 0) dialog.receiveMany({op: "inspect", id: m.id, ok: true, mode: modeA, reason: reasonA})
            if (order === 1) dialog.receiveMany({op: "inspect", id: m.id, ok: true, mode: modeB, reason: reasonB})
            order += 1
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    // Each phase opens the card, answers its inspects, and drives one finding's behavior.
    function advance() {
        shell.ticks += 1
        if (shell.ticks < 2) return
        if (shell.phase === 0) {
            var marked0 = shell.sent.length
            dialog.openMany(["/a", "/b"], holder)
            shell.answerInspects(marked0, "0644", "", "0644", "")
            shell.check("uniform-on-reads-on", dialog.multiValue(256) === "on", dialog.multiValue(256))
            dialog.multiToggle(256)
            shell.check("uniform-on-first-click-clears", dialog.multiValue(256) === "off", dialog.multiValue(256))
            dialog.multiToggle(256)
            shell.check("uniform-on-second-click-releases", dialog.multiValue(256) === "on", dialog.multiValue(256))
            shell.phase = 1
        } else if (shell.phase === 1) {
            var marked1 = shell.sent.length
            dialog.openMany(["/a", "/b"], holder)
            shell.answerInspects(marked1, "0644", "", "0644", "")
            dialog.multiToggle(1)
            shell.check("uniform-off-first-click-sets", dialog.multiValue(1) === "on", dialog.multiValue(1))
            shell.phase = 2
        } else if (shell.phase === 2) {
            var marked2 = shell.sent.length
            dialog.openMany(["/a", "/b"], holder)
            shell.answerInspects(marked2, "0644", "", "0755", "")
            shell.check("mixed-reads-some", dialog.multiValue(64) === "some", dialog.multiValue(64))
            dialog.multiToggle(64)
            shell.check("mixed-first-click-sets", dialog.multiValue(64) === "on", dialog.multiValue(64))
            dialog.multiToggle(64)
            shell.check("mixed-second-click-clears", dialog.multiValue(64) === "off", dialog.multiValue(64))
            dialog.multiToggle(64)
            shell.check("mixed-third-click-releases", dialog.multiValue(64) === "some", dialog.multiValue(64))
            shell.phase = 3
        } else if (shell.phase === 3) {
            var marked = shell.sent.length
            dialog.openMany(["/a", "/b"], holder)
            shell.answerInspects(marked, "0644", "", "0644", "")
            shell.check("inspect-stride-named", dialog.inspectStride === 1000, String(dialog.inspectStride))
            var ids = []
            for (var i = marked; i < shell.sent.length; i++)
                if (shell.sent[i].op === "inspect") ids.push(shell.sent[i].id)
            shell.check("inspect-ids-share-one-block", ids.length === 2 && (ids[1] - ids[0]) === 1, ids.join(","))
            shell.phase = 4
        } else if (shell.phase === 4) {
            var paths = []
            for (var i = 0; i < 1500; i++) paths.push("/p" + i)
            var before = dialog.requestId
            dialog.openMany(paths, holder)
            var span = dialog.requestId - before
            shell.check("large-open-reserves-its-block", span * 1000 >= 1500, "span=" + span)
            shell.phase = 5
        } else if (shell.phase === 5) {
            var marked5 = shell.sent.length
            dialog.openMany(["/a", "/b"], holder)
            shell.answerInspects(marked5, "0644", "", "0644", "Read-only: you are not the owner.")
            shell.check("inspect-reason-locks-grid", dialog.editable === false, String(dialog.editable))
            shell.check("inspect-reason-shows", dialog.displayedError.indexOf("not the owner") >= 0, dialog.displayedError)
            shell.phase = 6
        } else if (shell.phase === 6) {
            var marked6 = shell.sent.length
            dialog.openMany(["/a", "/b"], holder)
            shell.answerInspects(marked6, "0644", "", "0755", "")
            dialog.applyMany()
            var batch = null
            for (var i = 0; i < shell.sent.length; i++)
                if (shell.sent[i].c === "permissionsBatch") batch = shell.sent[i]
            shell.check("apply-sends-batch", batch !== null && batch.paths.length === 2, JSON.stringify(batch))
            dialog.backendFailed("the backend stopped")
            shell.check("transport-clears-applying", dialog.applyingMany === false, String(dialog.applyingMany))
            shell.check("transport-outcome-unknown", dialog.errorText.indexOf("outcome is unknown") >= 0, dialog.errorText)
            dialog.close()
            shell.check("transport-close-works", dialog.opened === false, String(dialog.opened))
            shell.phase = 7
        } else if (shell.phase === 7) {
            var marked7 = shell.sent.length
            dialog.openMany(["/a", "/b"], holder)
            shell.answerInspects(marked7, "0644", "", "0755", "")
            dialog.multiToggle(256)
            dialog.applyMany()
            var marked = shell.sent.length
            dialog.receiveMany({op: "applyMany", ok: false, error: "Could not change mode: refused. 1 of 2 items were changed; undo restores them."})
            var reinspects = 0
            for (var i = 0; i < shell.sent.length; i++)
                if (shell.sent[i].op === "inspect" && i >= marked) reinspects += 1
            shell.check("failure-reissues-inspects", reinspects === 2, "reinspects=" + reinspects)
            shell.check("failure-resets-pending", dialog.multiPending === 2, String(dialog.multiPending))
            shell.answerInspects(marked, "0600", "", "0755", "")
            shell.check("retry-starts-from-disk", dialog.multiModes.join(",") === "0600,0755", dialog.multiModes.join(","))
            shell.phase = 8
        } else if (shell.phase === 8) {
            for (var i = 0; i < shell.failures.length; i++)
                shell.log("FAIL " + shell.failures[i])
            shell.log("DONE failures=" + shell.failures.length)
            shell.phase = 9
            shell.quit()
        }
    }

    Component.onCompleted: {
        dialog.requested.connect(function (m) { shell.sent.push(m) })
    }
}
