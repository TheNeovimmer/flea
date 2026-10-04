.import "../../ui/js/Buttons.js" as Buttons
.import "../../ui/js/Collide.js" as Collide
.import "sourcefixture.js" as Source

// The braced block holding a marker, found by brace depth so a renamed id or a moved line fails loudly.
// Sample input: blockOf("A { id: x; B { y: 1 } } C { z: 2 }", "id: x") answers "{ id: x; B { y: 1 } }".
function blockOf(text, marker) {
    var at = text.indexOf(marker)
    if (at < 0)
        throw new Error("buttons: missing marker " + marker)
    var open = at - 1
    for (var back = 0; open >= 0; open--) {
        if (text[open] === "}")
            back++
        else if (text[open] === "{" && back-- === 0)
            break
    }
    if (open < 0)
        throw new Error("buttons: no block holds " + marker)
    var depth = 0
    for (var end = open; end < text.length; end++) {
        if (text[end] === "{")
            depth++
        else if (text[end] === "}" && --depth === 0)
            return text.substring(open, end + 1)
    }
    throw new Error("buttons: the block holding " + marker + " never closes")
}
// Sample input: valuesOf("A { border.width: 1; border.color: Theme.color.accent }", "border.color") answers ["Theme.color.accent"]; it reads every `name:` in the text, at a line's start or after a `;` or `{`, so a one-line item cannot hide one.
function valuesOf(block, name) {
    var out = []
    var pattern = new RegExp("(?:^|[\\s;{])" + name.replace(/\./g, "\\.") + "\\s*:\\s*([^;\\n}]+)", "g")
    var hit
    while ((hit = pattern.exec(block)) !== null)
        out.push(hit[1].trim())
    return out
}

// Variant A (Buttons040, GM 2026-09-24): one control at Theme.rowHeight minus its padding, fixed primary per dialog, destructive as error ink, disabled 0.55.

function run(check) {
    // The reader itself: a missing file throws naming it, so a renamed tree file fails loudly.
    var said = ""
    try {
        Source.source("ui/NoSuchFile-qml")
    } catch (e) {
        said = String((e && e.message) || e)
    }
    check("a missing file throws naming it", said.indexOf("ui/NoSuchFile-qml") >= 0, true)
    // indexOf coerces undefined to "undefined", so the guard runs before any search.
    var omitted = ""
    try {
        Source.slice("ab function f() {} undefined tail", "function f")
    } catch (e) {
        omitted = String((e && e.message) || e)
    }
    check("slice with an omitted marker throws its guard", omitted.indexOf("needs non-empty") >= 0, true)
    var emptyTo = ""
    try {
        Source.slice("ab function f() {} function g() {}", "function f", "")
    } catch (e) {
        emptyTo = String((e && e.message) || e)
    }
    check("slice with an empty toMarker throws its guard", emptyTo.indexOf("needs non-empty") >= 0, true)
    var emptyFrom = ""
    try {
        Source.slice("ab function f() {} function g() {}", "", "function g")
    } catch (e) {
        emptyFrom = String((e && e.message) || e)
    }
    check("slice with an empty fromMarker throws its guard", emptyFrom.indexOf("needs non-empty") >= 0, true)
    // One geometry for every dialog, card and picker button; the label follows Theme.font.body.
    check("one pad", Buttons.PAD, 9)
    check("one gap", Buttons.GAP, 9)
    check("the ring is its own signal", Buttons.RING, 2)
    check("a disabled control dims", Buttons.DISABLED_OPACITY, 0.55)
    check("hover is 8 percent of the ink", Buttons.WASH_HOVER, 0.08)
    check("press is 14 percent of the ink", Buttons.WASH_PRESS, 0.14)
    // The label follows the body's text stop, so text size moves the buttons with the rows.
    check("the label follows the body's text stop", Buttons.labelSizeFor(18), 18)
    check("and falls back to the shipped size without one", Buttons.labelSizeFor(null), Buttons.LABEL_SIZE)

    // The primary is fixed per dialog, the safe or asked-for action.
    check("trash opens on Cancel", Buttons.primaryFor("trash"), "cancel")
    check("collide opens on Keep both", Buttons.primaryFor("collide"), "keep")
    check("open-with opens on Open", Buttons.primaryFor("openWith"), "open")
    check("convert opens on Convert", Buttons.primaryFor("convert"), "convert")
    check("a new file opens on Create", Buttons.primaryFor("newFile"), "create")
    check("move opens on Move", Buttons.primaryFor("moveTo"), "move")
    check("copy opens on Copy", Buttons.primaryFor("copyTo"), "copy")
    check("network opens on its action", Buttons.primaryFor("network"), "action")
    check("permissions opens on Apply", Buttons.primaryFor("permissions"), "apply")
    check("the picker answers with Open", Buttons.primaryFor("picker"), "accept")
    check("an unknown dialog has no primary", Buttons.primaryFor("nope"), "")

    // A destructive action rests as the error label in a muted frame, never primary.
    check("delete is destructive", Buttons.isDestructive("trash", "delete"), true)
    check("cancel is not", Buttons.isDestructive("trash", "cancel"), false)
    check("replace is destructive", Buttons.isDestructive("collide", "replace"), true)
    check("keep both is not", Buttons.isDestructive("collide", "keep"), false)
    check("the picker's replace is destructive", Buttons.isDestructive("picker", "replace"), true)
    check("the picker's save is not", Buttons.isDestructive("picker", "accept"), false)

    // The card's keyboard opening and its primary agree, so Enter is safe.
    check("the card still opens on Keep both", Collide.START, Buttons.primaryFor("collide"))

    // The height lives in ui/DialogButton.qml as Theme.rowHeight minus its padding, or the strip's chromeHeight when hosted, so no constant here can drift from it.
    check("buttons draw the theme height, not a constant",
        Source.source("ui/DialogButton.qml").indexOf("implicitHeight: root.inStrip ? Theme.chromeHeight : Theme.rowHeight - Theme.spacing.rowPaddingY") >= 0, true)
    check("a hosted control draws the strip's control height, not a constant",
        Source.source("ui/DialogButton.qml").indexOf("root.inStrip ? Theme.chromeControlHeight : root.height") >= 0, true)

    // GM 2026-10-03: a field's focus is its own hairline frame in the accent, as 0.3.6 drew it; the 2 px ring is the buttons' alone.
    var accentFrame = "border.color: field.activeFocus ? Theme.color.accent : Theme.color.muted"
    var fields = {
        "ui/DialogField.qml": accentFrame,
        "ui/MenuActionDialog.qml": accentFrame,
        "ui/OpenWithDialog.qml": accentFrame,
        "ui/PickerSave.qml": accentFrame,
        "ui/PermissionsDialog.qml": "border.color: octal.activeFocus ? (errorLabel.visible && !root.busy ? Theme.color.error : Theme.color.accent) : Theme.color.muted",
        "ui/RenameField.qml": "border.color: root.errorText.length > 0 ? Theme.color.error : Theme.color.accent"
    }
    for (var file in fields) {
        var text = Source.source(file)
        check(file + " frames a focused field in the accent", text.indexOf(fields[file]) >= 0, true)
        check(file + " draws no button ring around a field", text.indexOf("Buttons.RING") < 0, true)
    }
    // The chrome path field is the editFrame block alone: one accent hairline, no ring, and no sibling draws a border around it.
    var chrome = Source.source("ui/ChromeBar.qml")
    var edit = blockOf(chrome, "id: editFrame")
    check("the path frame's border colour is the accent", valuesOf(edit, "border.color").join("|"), "Theme.color.accent")
    check("the path frame's border is one hairline", valuesOf(edit, "border.width").join("|"), "Theme.spacing.hairline")
    check("the path frame draws no ring or ring clearance", /Buttons\.RING|ringClearance|margins:\s*-/.test(edit), false)
    check("the strip draws no border but hairlines", valuesOf(chrome, "border.width").join("|"), "Theme.spacing.hairline")
    check("the strip never reads a ring width or ring clearance", /Buttons\.RING|ringClearance/.test(chrome), false)
    check("the strip groups no border properties, where a width would hide from the reader", /\bborder\s*\{/.test(chrome), false)
    check("the reader sees a border width inside a one-line item", valuesOf("Rectangle { border.width: 2; color: x }", "border.width").join("|"), "2")
    check("the block reader finds a nested block whole", blockOf("A { id: x; B { y: 1 } } C { z: 2 }", "id: x"), "{ id: x; B { y: 1 } }")

    // A ChromeButton under a strip rule drawn in its own last row takes the rule's row off its ring; the Permissions title band and the inline PDF strip draw no such rule.
    var ruled = { "ui/PdfViewer.qml": 6, "ui/MarkdownPane.qml": 1, "ui/PermissionsDialog.qml": 0, "ui/PreviewColumn.qml": 0 }
    for (var host in ruled) {
        var hostText = Source.source(host)
        var wanted = ruled[host]
        var drawn = hostText.split("Flea.ChromeButton {").length - 1
        check(host + " gives every strip rule's row to its ring", hostText.split("ruleRows: Theme.spacing.hairline").length - 1, wanted)
        check(host + " hosts the buttons the pin counts", wanted === 0 || drawn === wanted, true)
    }
}
