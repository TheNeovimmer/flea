//@ pragma ShellId flea-sheet-query-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/sheet-query.sh's harness: the real ui/KeymapSheet.qml over a stub pane measures CommandPalette's query states.
ShellRoot {
    id: root

    property var failures: []
    property int checks: 0
    property int phase: 0
    // The menu answers for a regular file under the cursor; a dead context is a pane with nothing to act on.
    property var fileContext: ({ hasRow: true, hiddenActions: [], selectionCount: 1, rowMode: 0o100644, selectionModes: [0o100644],
        cursorIsTarget: true, rowIsFile: true, clipboardAvailable: true, canTrash: true, dirWritable: true, archiveFormats: ["zip"] })
    property var deadContext: ({ hasRow: true, hiddenActions: [], selectionCount: 0, rowMode: 0, selectionModes: [] })
    property var activated: []
    // Both ticks wait a frame so the sheet's bindings and layout settle before a read.
    readonly property int settleMs: 250

    function expect(label, ok, detail) {
        root.checks += 1
        if (!ok) root.failures.push(label + " got " + detail)
    }
    function walk(item, out) {
        for (var i = 0; i < item.children.length; i++) {
            out.push(item.children[i])
            root.walk(item.children[i], out)
        }
        return out
    }
    // Shown text only: the resting grid stays built beneath a query and carries its own ? cap.
    function texts(value) {
        return root.walk(sheet.cardItem, []).filter(function (item) { return item.visible && item.text === value })
    }
    function rowsOf() { return sheet.rows().split("\n") }

    Item {
        id: holder
        property bool dualMode: false
        property string home: "/home/probe"
        property var sidebar: null
        property bool listInFlight: false
        property var cursorRow: ({ n: "a.txt", d: false })
        property var context: root.fileContext
        property var menuActions: ({
            snapshot: function () {},
            activate: function (action, selected) { root.activated.push(action) }
        })
        function checkShebang() {}
        function message(text, sticky) {}
        function contextMenu() { return { listingContext: function () { return holder.context } } }
    }

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 700
        color: "#303030"
        Flea.KeymapSheet { id: sheet; anchors.fill: parent }
    }

    Timer {
        interval: root.settleMs
        running: true
        repeat: true
        onTriggered: root.advance()
    }

    function advance() {
        if (root.phase === 0) {
            sheet.open(holder)
            root.restWidth = sheet.capWidth
            root.restLabelX = sheet.cardItem.x
            root.phase = 1
        } else if (root.phase === 1) {
            sheet.query = "perm"
            root.phase = 2
        } else if (root.phase === 2) {
            root.checkPerm()
            sheet.query = "trash"
            root.phase = 3
        } else if (root.phase === 3) {
            root.checkPlace()
            root.phase = 4
            root.report()
        }
    }
    property int restWidth: 0
    property real restLabelX: 0

    function checkPerm() {
        // Item 4: one cap column in every state.
        root.expect("the cap column keeps its rest width under a query", sheet.capWidth === root.restWidth, sheet.capWidth + " vs " + root.restWidth)
        // Item 1: one action, one row.
        var labels = sheet.queryResults.map(function (row) { return row.label })
        root.expect("delete permanently lists once", labels.filter(function (l) { return l.toLowerCase() === "delete permanently" }).length === 1, labels.join("|"))
        // The IPC reader the native capture asserts on lists the same rows, a disabled one marked.
        root.expect("the sheet reads back its results", root.rowsOf().indexOf("shift-delete delete permanently") >= 0 && root.rowsOf().indexOf(" Permissions") >= 0, root.rowsOf().join("|"))
        // Item 3: the board's query line, the prompt in the cap column and the field on the label column.
        var prompts = root.texts("?")
        root.expect("a muted ? prompt is drawn", prompts.length === 1 && prompts[0].color.toString() === Flea.Theme.color.muted.toString(), prompts.length)
        if (prompts.length === 1) {
            root.expect("the prompt fills the cap column", prompts[0].width === sheet.capWidth && prompts[0].horizontalAlignment === Text.AlignHCenter, prompts[0].width)
            var fields = root.walk(sheet.cardItem, []).filter(function (item) {
                return item.border !== undefined && item.border.color.toString() === Flea.Theme.color.accent.toString() && item.height > 0 })
            root.expect("one hairline accent field frames the query", fields.length === 1 && fields[0].border.width === Flea.Theme.spacing.hairline, fields.length)
            if (fields.length === 1)
                root.expect("the field starts on the label column", fields[0].x === sheet.capWidth + sheet.capGap, fields[0].x)
        }
        // The washed run of a matching label is the same word at caption size; the field draws it at body size.
        var typed = root.texts("perm").filter(function (item) { return item.font.pixelSize === Flea.Theme.font.body })
        root.expect("the query text is drawn at body size", typed.length === 1, typed.length)
        // Item 5: the header reads esc closes under a query.
        root.expect("the header reads esc closes", root.texts("esc closes").length === 1 && root.texts("esc clears").length === 0, "closes=" + root.texts("esc closes").length)
        // Item 2: Permissions is live over a file, and Enter runs it through the menu.
        var permissionsAt = -1
        var results = sheet.queryResults
        for (var i = 0; i < results.length; i++)
            if (results[i].label === "Permissions") permissionsAt = i
        root.expect("a Permissions row is listed", permissionsAt >= 0, permissionsAt)
        root.expect("and it is available over a file", permissionsAt >= 0 && results[permissionsAt].disabled === false, "disabled")
        sheet.resultCursor = permissionsAt
        sheet.activateResult()
        root.expect("Enter runs Permissions through the menu", root.activated.join(",") === "permissions", root.activated.join(","))
        // With nothing to act on the row is disabled and Enter is refused.
        sheet.open(holder)
        holder.context = root.deadContext
        sheet.query = "perm"
        results = sheet.queryResults
        permissionsAt = -1
        for (var j = 0; j < results.length; j++)
            if (results[j].label === "Permissions") permissionsAt = j
        root.expect("Permissions reads disabled with nothing to act on", permissionsAt >= 0 && results[permissionsAt].disabled === true, permissionsAt)
        root.activated = []
        sheet.resultCursor = permissionsAt
        sheet.activateResult()
        root.expect("and Enter is refused", root.activated.length === 0 && sheet.opened, root.activated.join(","))
        holder.context = root.fileContext
    }

    function checkPlace() {
        // Item 6: a place result says where inline, muted, right after its name.
        var wheres = root.walk(sheet.cardItem, []).filter(function (item) { return item.text === " in Places" })
        root.expect("a place row carries its muted suffix", wheres.length >= 1, wheres.length)
        if (wheres.length >= 1) {
            var where = wheres[0]
            var row = where.parent
            var label = null
            for (var i = 0; i < row.children.length; i++)
                if (row.children[i].text === "Open Trash") label = row.children[i]
            root.expect("the suffix sits right after the name", label !== null && Math.abs(where.x - (label.x + label.width)) <= 1, label ? where.x + " vs " + (label.x + label.width) : "no label")
            root.expect("and not at the card's right edge", where.x + where.contentWidth < row.width - sheet.capWidth, where.x + " + " + where.contentWidth + " of " + row.width)
            root.expect("in the muted ink", where.color.toString() === Flea.Theme.color.muted.toString(), where.color)
        }
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("SHEETQUERY FAIL " + root.failures[f])
        if (root.failures.length === 0)
            console.log("SHEETQUERY PASS checks=" + root.checks)
        console.log("SHEETQUERY DONE failures=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
