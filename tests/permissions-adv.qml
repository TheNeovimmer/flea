//@ pragma ShellId flea-permissions-adv-test

import QtQuick
import Quickshell
import "flea" as Flea
import "permissions-columns.js" as Columns

// tests/permissions-adv.sh's harness: the multi-row Permissions card's advloop findings, red first.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0
    property int refreshes: 0
    property int changes: 0
    readonly property int titleRuleCount: 1
    readonly property int singleRuleCount: 4
    readonly property real sectionRuleOpacity: 0.4
    // Every stop the Display section offers; the window is odd so a centred card exposes a half pixel.
    readonly property var textStops: [9, 10, 11, 12, 14, 16, 20]
    readonly property int boardStop: 14
    readonly property int windowWidth: 801
    readonly property int windowHeight: 601
    // The board's bar at an 18 px box: 8 x 2, centred, and the box's 13 px bodySmall reference.
    readonly property int boardBarWidth: 8
    readonly property int boardBarHeight: 2
    readonly property int boardBarX: 5
    readonly property int boardBarY: 8
    // The several-items fixture reads 0644 and 0755, so the Owner execute bit (1 << 6) differs across the files.
    readonly property int mixedBit: 64
    readonly property real boardBodySmall: 13
    // lib.py note(): the note's line box is 1.5 x its font size, and the board's several-items card is 275 tall at 14.
    readonly property real noteLineRatio: 1.5
    readonly property int boardSeveralHeight: 275
    // Odd and even rooms and spans that a card centres in: the helper's whole size and origin are read from each.
    readonly property var helperRooms: [800, 801]
    readonly property var helperWants: [472.5, 473, 551.25, 480]
    readonly property int helperMargin: 16
    property int stopIndex: 0
    property int cardKind: 0

    function log(line) { console.log("PERMADV " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        if (cond) shell.log("PASS " + name)
        else shell.failures.push(name + " got " + detail)
    }

    function stopState(stop) {
        Flea.ViewState.load(JSON.stringify({ display: { textSize: { mode: stop } } }))
    }
    function whole(value) { return value === Math.round(value) }
    function sceneRect(item) {
        var r = item.mapToItem(null, 0, 0, item.width, item.height)
        return [r.x, r.y, r.width, r.height]
    }
    // The card's mapped rectangle has no fractional part, so every one of its four edges is one device pixel.
    function checkWholeCard(tag, item) {
        var r = shell.sceneRect(item)
        shell.check(tag + " card rect is whole pixels", r.every(shell.whole), r.join(","))
    }
    // Every check box of the grid sits on whole pixels too, because its 2 px frame is a hairline pair.
    function checkWholeBoxes(tag, card) {
        var bad = []
        var controls = card.controls()
        for (var i = 0; i < controls.length; i++) {
            if (controls[i].bit === undefined) continue
            var box = controls[i].item.children.find(function (child) { return typeof child.value === "string" })
            var r = shell.sceneRect(box)
            if (!r.every(shell.whole)) bad.push(controls[i].name + " " + r.join(","))
        }
        shell.check(tag + " check boxes are whole pixels", bad.length === 0, bad.join(" | "))
    }
    // The note is a whole-pixel line box of 1.5 x caption per line, its glyphs centred in it as CSS line-height centres them.
    function checkNote(tag, card) {
        var note = card.noteItem
        if (!note) { shell.check(tag + " note is reachable", false, "no noteItem"); shell.check(tag + " note glyphs are centred", false, "no noteItem"); return }
        var box = Math.round(shell.noteLineRatio * Flea.Theme.font.caption)
        // contentHeight is what the text layout laid out, so it moves with lineHeight or the font and not with the height binding.
        shell.check(tag + " note lays out lines of 1.5 x caption", note.lineCount > 0 && note.contentHeight === note.lineCount * box, note.contentHeight + " for " + note.lineCount + " lines of " + box)
        shell.check(tag + " note box holds its laid-out lines", note.height === note.contentHeight, note.height + " against " + note.contentHeight)
        var lead = (box - probeNote.implicitHeight) / 2
        shell.check(tag + " note glyphs are centred in the line box", Math.abs(note.topPadding - lead) <= 0.5, "topPadding " + note.topPadding + " want " + lead)
    }
    // check() takes a verdict; same() compares what was read with what the board draws and names both on a miss.
    function same(name, actual, expected) { shell.check(name, String(actual) === String(expected), String(actual) + " want " + String(expected)) }
    // Theme.cardSpan and cardOrigin give every card a whole size inside its room and a whole origin, in odd and even rooms.
    function checkHelper() {
        var ready = typeof Flea.Theme.cardSpan === "function" && typeof Flea.Theme.cardOrigin === "function"
        for (var r = 0; r < shell.helperRooms.length; r++) {
            var room = shell.helperRooms[r]
            for (var w = 0; w < shell.helperWants.length; w++) {
                var want = shell.helperWants[w]
                var span = ready ? Flea.Theme.cardSpan(want, room - 2 * shell.helperMargin) : -1
                var origin = ready ? Flea.Theme.cardOrigin(room, span) : -1
                shell.check("helper room " + room + " want " + want + " is whole", ready && shell.whole(span) && shell.whole(origin) && span >= want && span < want + 1 && origin >= 0 && origin + span <= room, span + " at " + origin)
            }
            var clamped = ready ? Flea.Theme.cardSpan(room * 2, room - 2 * shell.helperMargin) : -1
            shell.check("helper room " + room + " clamps to the room", ready && clamped === room - 2 * shell.helperMargin, String(clamped))
        }
    }
    // The check box the several-items fixture leaves mixed, read from the open card's own grid.
    function mixedBoxOf(card) {
        var controls = card.controls()
        for (var i = 0; i < controls.length; i++) {
            if (controls[i].bit !== shell.mixedBit) continue
            return controls[i].item.children.find(function (child) { return typeof child.value === "string" })
        }
        return undefined
    }
    // The mixed bar is a rectangle in the check's cut-out ink, the board's 8 x 2 scaled with the box, on whole pixels.
    function checkMixedBar(tag, card, stop) {
        var box = shell.mixedBoxOf(card)
        shell.check(tag + " card has a mixed Owner execute box showing the bar", !!box && box.value === "some" && !!box.barItem && box.barItem.visible, box ? box.value : "no box")
        if (!box) return
        var bar = box.barItem
        var scale = Flea.Theme.font.bodySmall / shell.boardBodySmall
        var wantWidth = Math.round(shell.boardBarWidth * scale)
        var wantHeight = Math.max(1, Math.round(shell.boardBarHeight * scale))
        shell.check(tag + " mixed bar is a rectangle", !!bar && String(bar).indexOf("QQuickRectangle") === 0, String(bar))
        var size = bar ? bar.width + "x" + bar.height : "none"
        shell.check(tag + " mixed bar size scales with the box", size === wantWidth + "x" + wantHeight, size + " want " + wantWidth + "x" + wantHeight)
        var at = bar ? bar.x + "," + bar.y : "none"
        shell.check(tag + " mixed bar sits on whole pixels", !!bar && shell.whole(bar.x) && shell.whole(bar.y), at)
        shell.check(tag + " mixed bar is centred in the box",
            !!bar && Math.abs(2 * bar.x + bar.width - box.width) <= 1 && Math.abs(2 * bar.y + bar.height - box.height) <= 1, at)
        shell.check(tag + " mixed bar draws in the check's ink", !!bar && Qt.colorEqual(bar.color, Flea.Theme.color.background) && bar.opacity === 1, bar ? String(bar.color) : "none")
        if (stop === shell.boardStop)
            shell.check(tag + " mixed bar is the board's 8 x 2 at 5,8", !!bar && size === shell.boardBarWidth + "x" + shell.boardBarHeight
                && bar.x === shell.boardBarX && bar.y === shell.boardBarY, size + " at " + at)
    }

    function visibleSections(item, result) {
        if (!item.visible) return result
        if (item.text === "WILL CHANGE") result.headers += 1
        if (item.height === Flea.Theme.spacing.hairline && item.opacity === sectionRuleOpacity) result.rules += 1
        for (var i = 0; i < item.children.length; i++) visibleSections(item.children[i], result)
        return result
    }

    Item {
        id: holder
    }

    FloatingWindow {
        implicitWidth: shell.windowWidth
        implicitHeight: shell.windowHeight
        color: "#303030"

        // One caption line at the note's font, whose natural height is what the line box centres its glyphs against.
        Text {
            id: probeNote
            visible: false
            text: "Hg"
            font { family: Flea.Theme.font.family; pixelSize: Flea.Theme.font.caption }
        }

        FontMetrics { id: probeFont; font { family: Flea.Theme.font.family; pixelSize: Flea.Theme.font.caption } }
        TextMetrics { id: probeInk; text: "READ"; font { family: Flea.Theme.font.family; pixelSize: Flea.Theme.font.caption } }

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
            dialog.multiToggle(1)
            shell.check("uniform-off-second-click-releases", dialog.multiValue(1) === "off", dialog.multiValue(1))
            dialog.multiToggle(1)
            shell.check("uniform-off-third-click-sets", dialog.multiValue(1) === "on", dialog.multiValue(1))
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
            var largePaths = []
            for (var li = 0; li < 1500; li++) largePaths.push("/p" + li)
            var markLarge = shell.sent.length
            dialog.openMany(largePaths, holder)
            var highest = 0
            for (var hi = markLarge; hi < shell.sent.length; hi++)
                if (shell.sent[hi].op === "inspect" && shell.sent[hi].id > highest) highest = shell.sent[hi].id
            var markSmall = shell.sent.length
            dialog.openMany(["/a", "/b"], holder)
            var clears = true
            var smallCount = 0
            for (var si = markSmall; si < shell.sent.length; si++)
                if (shell.sent[si].op === "inspect") { smallCount += 1; if (shell.sent[si].id <= highest) clears = false }
            shell.check("small-open-clears-large-block", clears && smallCount === 2, "highest=" + highest)
            shell.phase = 4
        } else if (shell.phase === 4) {
            var paths = []
            for (var i = 0; i < 1500; i++) paths.push("/q" + i)
            var before = dialog.requestId
            dialog.openMany(paths, holder)
            var span = dialog.requestId - before
            shell.check("large-open-reserves-its-block", span * dialog.inspectStride >= paths.length, "span=" + span)
            shell.phase = 5
        } else if (shell.phase === 5) {
            var marked5 = shell.sent.length
            dialog.openMany(["/a", "/b"], holder)
            shell.answerInspects(marked5, "0644", "", "0644", "Read-only: you are not the owner.")
            shell.check("reasoned-row-keeps-grid-editable", dialog.editable === true, String(dialog.editable))
            shell.check("reasoned-row-is-named", dialog.displayedError === "b keeps its mode because you do not own it.", dialog.displayedError)
            var beforeApply = shell.sent.length
            dialog.applyMany()
            var batch5 = null
            for (var bi = beforeApply; bi < shell.sent.length; bi++)
                if (shell.sent[bi].c === "permissionsBatch") batch5 = shell.sent[bi]
            shell.check("apply-skips-reasoned-row", batch5 !== null && batch5.paths.length === 1 && batch5.paths[0] === "/a", JSON.stringify(batch5))
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
            dialog.receiveMany({op: "applyMany", id: dialog.requestId, ok: false, error: "Could not change mode: refused. 1 of 2 items were changed; undo restores them."})
            shell.check("failure-asks-owner-refresh", shell.refreshes === 1, String(shell.refreshes))
            var reinspects = 0
            for (var i = 0; i < shell.sent.length; i++)
                if (shell.sent[i].op === "inspect" && i >= marked) reinspects += 1
            shell.check("failure-reissues-inspects", reinspects === 2, "reinspects=" + reinspects)
            shell.check("failure-resets-pending", dialog.multiPending === 2, String(dialog.multiPending))
            shell.answerInspects(marked, "0600", "", "0755", "")
            shell.check("retry-starts-from-disk", dialog.multiModes.join(",") === "0600,0755", dialog.multiModes.join(","))
            shell.phase = 8
        } else if (shell.phase === 8) {
            var marked8 = shell.sent.length
            dialog.openMany(["/s0", "/s1", "/s2"], holder)
            var ids8 = []
            for (var ci = marked8; ci < shell.sent.length; ci++)
                if (shell.sent[ci].op === "inspect") ids8.push(shell.sent[ci].id)
            var waits = true
            for (var ri = 0; ri < ids8.length; ri++) {
                dialog.receiveMany({op: "inspect", id: ids8[ri], ok: true, mode: "0644", reason: ""})
                if (ri + 1 < ids8.length && dialog.multiModes.length !== 0) waits = false
            }
            shell.check("summary-waits-for-last-reply", waits, dialog.multiModes.join(","))
            shell.check("summary-lands-once", dialog.multiModes.length === 3 && dialog.multiPending === 0, dialog.multiModes.join(",") + "/" + dialog.multiPending)
            shell.phase = 9
        } else if (shell.phase === 9) {
            var marked9 = shell.sent.length
            dialog.openMany(["/a", "/b"], holder)
            shell.answerInspects(marked9, "0644", "", "0644", "")
            // Make executable replies arriving after another card opens belong to neither its inspect nor its Apply.
            var changes9 = shell.changes
            dialog.receive({op: "applyMany", id: dialog.requestId, ok: true})
            shell.check("hunt:matching-id-without-apply-keeps-card", dialog.opened && shell.changes === changes9,
                        "opened=" + dialog.opened + " changes=" + (shell.changes - changes9))
            dialog.receive({op: "applyMany", ok: true})
            shell.check("hunt:untagged-batch-reply-keeps-card", dialog.opened && shell.changes === changes9,
                        "opened=" + dialog.opened + " changes=" + (shell.changes - changes9))
            dialog.receive({op: "applyMany", id: 1000001, ok: true})
            shell.check("hunt:unrelated-make-executable-reply-keeps-card",
                dialog.opened && shell.changes === changes9,
                "opened=" + dialog.opened + " changes=" + (shell.changes - changes9))
            shell.phase = 10
        } else if (shell.phase === 10) {
            var marked10 = shell.sent.length
            dialog.openMany(["/a", "/b"], holder)
            shell.answerInspects(marked10, "0644", "", "0644", "")
            dialog.applyMany()
            var applyingId = dialog.requestId
            dialog.receive({op: "applyMany", id: applyingId - 1, ok: false, error: "old batch refused"})
            shell.check("hunt:stale-batch-refusal-keeps-current-apply",
                dialog.opened && dialog.applyingMany && dialog.multiPending === 0 && dialog.errorText === "",
                "applying=" + dialog.applyingMany + " pending=" + dialog.multiPending + " error=" + dialog.errorText)
            dialog.receive({op: "applyMany", id: applyingId, ok: true})
            shell.check("hunt:matching-batch-reply-closes-card", !dialog.opened, "opened=" + dialog.opened)
            shell.phase = 11
        } else if (shell.phase === 11) {
            var marked11 = shell.sent.length
            dialog.openMany(["/a", "/b", "/c"], holder)
            for (var fi = marked11; fi < shell.sent.length; fi++)
                dialog.receiveMany({op: "inspect", id: shell.sent[fi].id, ok: true, mode: "0644", reason: ""})
            shell.phase = 12
        } else if (shell.phase === 12) {
            var multiSections = visibleSections(dialog.cardItem, {headers: 0, rules: 0})
            shell.check("r1:multi-has-no-preview-header", multiSections.headers === 0, JSON.stringify(multiSections))
            shell.check("r1:multi-keeps-only-title-rule", multiSections.rules === titleRuleCount, JSON.stringify(multiSections))
            dialog.open("/a", holder)
            dialog.receive({op: "inspect", id: dialog.requestId, ok: true, mode: "0644", reason: ""})
            shell.phase = 13
        } else if (shell.phase === 13) {
            var singleSections = visibleSections(dialog.cardItem, {headers: 0, rules: 0})
            shell.check("r1:single-keeps-preview-header", singleSections.headers === 1, JSON.stringify(singleSections))
            shell.check("r1:single-keeps-section-rules", singleSections.rules === singleRuleCount, JSON.stringify(singleSections))
            shell.phase = 14
        } else if (shell.phase === 14) {
            // One stop at a time: the text size first, then the single card, then the several-items card.
            shell.stopState(shell.textStops[shell.stopIndex])
            if (shell.cardKind === 0) {
                dialog.open("/a", holder)
                dialog.receive({op: "inspect", id: dialog.requestId, ok: true, mode: "0644", reason: ""})
            } else {
                var markedSize = shell.sent.length
                dialog.openMany(["/a", "/b"], holder)
                shell.answerInspects(markedSize, "0644", "", "0755", "")
            }
            shell.phase = 15
        } else if (shell.phase === 15) {
            var stop = shell.textStops[shell.stopIndex]
            var tag = "stop" + stop + (shell.cardKind === 0 ? ":single" : ":several")
            shell.checkWholeCard(tag, dialog.cardItem)
            shell.checkWholeBoxes(tag, dialog)
            shell.checkNote(tag, dialog)
            Columns.checkColumns(shell, tag, dialog, stop)
            Columns.checkHeading(shell, tag, dialog, probeNote.implicitHeight, Flea.Theme.font.caption, probeFont.ascent + probeInk.tightBoundingRect.y, stop)
            if (shell.cardKind === 0) Columns.checkOctalFrame(shell, tag, dialog, Flea.Theme)
            if (shell.cardKind === 1 && stop === shell.boardStop)
                shell.check(tag + " card is the board's 275", dialog.cardItem.height === shell.boardSeveralHeight, String(dialog.cardItem.height))
            if (shell.cardKind === 1) shell.checkMixedBar(tag, dialog, stop)
            dialog.close()
            shell.cardKind = (shell.cardKind + 1) % 2
            if (shell.cardKind === 0) shell.stopIndex += 1
            shell.phase = shell.stopIndex < shell.textStops.length ? 14 : 16
        } else if (shell.phase === 16) {
            shell.checkHelper()
            shell.phase = 17
        } else if (shell.phase === 17) {
            for (var i = 0; i < shell.failures.length; i++)
                shell.log("FAIL " + shell.failures[i])
            shell.log("DONE failures=" + shell.failures.length)
            shell.phase = 18
            shell.quit()
        }
    }

    Component.onCompleted: {
        dialog.requested.connect(function (m) { shell.sent.push(m) })
        dialog.refreshNeeded.connect(function () { shell.refreshes += 1 })
        dialog.changed.connect(function () { shell.changes += 1 })
    }
}
