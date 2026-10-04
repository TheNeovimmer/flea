.pragma library

// Where the Permissions card's bit columns, their headings and its octal frame sit, read off the live dialog by tests/permissions-adv.qml.

// Permissions040 at 14: a 480 card, its READ, WRITE and EXEC headings in thirds of the 350 the label leaves, an 18 px box centred in each, in card px.
var BOARD_STOP = 14
var BOARD_CARD_WIDTH = 480
var BOARD_HEAD_X = [113, 230, 346]
var BOARD_HEAD_WIDTH = [117, 116, 117]
var BOARD_BOX_X = [162, 279, 396]
var COLUMNS = 3
// The board's headings inherit the body's line-height of 1.6, so their line box is 1.6 x the caption, not the note's 1.5.
var LINE_RATIO = 1.6
// Text.FixedHeight, which a library cannot name.
var FIXED_HEIGHT = 1

function textsNamed(item, name, result) {
    if (item.text === name) result.push(item)
    for (var i = 0; i < item.children.length; i++) textsNamed(item.children[i], name, result)
    return result
}

function boxOf(control) { return control.item.children.find(function (child) { return typeof child.value === "string" }) }

// Cards place each column at the start of its exact third and each box at its exact centre, both rounded half up in whole numbers.
// Sample input: span 350, box 18, column 1 starts at floor((2 * 350 + 3) / 6) = 117 and its box at floor((2 * 350 + 350 - 54 + 3) / 6) = 166.
function checkColumns(shell, tag, card, stop) {
    var owner = textsNamed(card.bodyItem, "Owner", [])[0]
    var left = owner.mapToItem(card.cardItem, 0, 0).x
    var span = card.bodyItem.holderWidth - card.labelWidth
    var columns = []
    for (var i = 0; i < COLUMNS; i++) columns.push(i)
    var heads = [textsNamed(card.bodyItem, "READ", [])[0], textsNamed(card.bodyItem, "WRITE", [])[0],
        textsNamed(card.bodyItem, card.isMulti || !card.facts.directory ? "EXEC" : "ENTER", [])[0]]
    shell.same(tag + " heading columns start at the rounded thirds",
        heads.map(function (head) { return head ? head.mapToItem(card.cardItem, 0, 0).x - left - card.labelWidth : -1 }).join(","),
        columns.map(function (i) { return Math.floor((2 * i * span + 3) / 6) }).join(","))
    shell.same(tag + " heading columns tile what the label leaves",
        heads.reduce(function (sum, head) { return sum + (head ? head.width : 0) }, 0), span)
    var firstRow = card.controls().filter(function (control) { return control.bit !== undefined }).slice(0, COLUMNS)
    var boxWidth = boxOf(firstRow[0]).width
    var boxes = firstRow.map(function (control) { return boxOf(control).mapToItem(card.cardItem, 0, 0).x })
    shell.same(tag + " boxes sit at the rounded exact centre of each third", boxes.join(","),
        columns.map(function (i) { return left + card.labelWidth + Math.floor((2 * i * span + span - 3 * boxWidth + 3) / 6) }).join(","))
    if (stop === BOARD_STOP && card.isMulti) {
        shell.same(tag + " card is the board's 480 wide", card.cardItem.width, BOARD_CARD_WIDTH)
        shell.same(tag + " headings start at the board's card x 113, 230 and 346",
            heads.map(function (head) { return head ? head.mapToItem(card.cardItem, 0, 0).x : -1 }).join(","), BOARD_HEAD_X.join(","))
        shell.same(tag + " headings are the board's 117, 116 and 117 wide", heads.map(function (head) { return head ? head.width : -1 }).join(","), BOARD_HEAD_WIDTH.join(","))
    }
    if (stop === BOARD_STOP && card.cardItem.width === BOARD_CARD_WIDTH)
        shell.same(tag + " boxes start at the board's card x 162, 279 and 396", boxes.join(","), BOARD_BOX_X.join(","))
}

// The heading's 1.6 line box is centred in its row as the board's flex row centres it, and its glyphs are centred in the box as the note's are.
function checkHeading(shell, tag, card, captionHeight, caption, inkUnderLineTop, stop) {
    var head = textsNamed(card.bodyItem, "READ", [])[0]
    if (!head) { shell.check(tag + " heading is reachable", false, "no READ"); return }
    var box = Math.round(LINE_RATIO * caption)
    var got = head.lineHeight + "/" + (head.lineHeightMode === FIXED_HEIGHT) + "/" + head.topPadding + "/" + head.y
    shell.same(tag + " heading line box is centred in its row and holds its glyphs centred", got,
        box + "/true/" + Math.round((box - captionHeight) / 2) + "/" + Math.floor((card.headingHeight - box) / 2))
    checkHeadingInk(shell, tag, card, inkUnderLineTop, stop)
}

// The probe reads the font's tight box off its ascent, one row under where the raster draws the ink (the 0.3.8 build read 51 here and drew 50 in the capture).
var PROBE_ROW_BIAS = 1
// Permissions040 at 14, several items: the READ, WRITE and EXEC glyphs span rows 49 to 57 from the card top, read off the board's render.
var BOARD_HEAD_INK_TOP = 49

// Sample input: a heading at card y 45 with a 1 px lead and ink 4 px under the line top answers 50, which is board row 49 once the probe's bias is taken off.
// The ink top in card px is the heading's box top, its top padding and the font's own ink offset, which the caller reads from the font, never the dialog.
function checkHeadingInk(shell, tag, card, inkUnderLineTop, stop) {
    if (stop !== BOARD_STOP || !card.isMulti) return
    var head = textsNamed(card.bodyItem, "READ", [])[0]
    if (!head) { shell.check(tag + " heading ink is reachable", false, "no READ"); return }
    var top = head.mapToItem(card.cardItem, 0, 0).y + head.topPadding + inkUnderLineTop
    shell.same(tag + " heading ink starts on the board's row " + BOARD_HEAD_INK_TOP, Math.round(top) - PROBE_ROW_BIAS, BOARD_HEAD_INK_TOP)
}

// ButtonSystem040 A: the Octal field is DialogField's height at every text size, centred in its row, where the row's pitch is the card's own.
// The field is read off a live DialogField (its one bordered child), so a change to that field's height moves this pin with it.
function checkOctalHeight(shell, tag, card, dialogField) {
    var frame = card.octalFrame
    var box = dialogField.children.find(function (child) { return child.border !== undefined })
    if (!frame || !box) { shell.check(tag + " octal field and DialogField box are reachable", false, "frame=" + !!frame + " box=" + !!box); return }
    shell.same(tag + " octal field is DialogField's height", frame.height, box.height)
    var row = frame.parent
    shell.same(tag + " octal field is centred in its row", frame.y, Math.round((row.height - frame.height) / 2))
    shell.check(tag + " octal row keeps the card's control pitch", row.height === card.controlHeight, row.height + " vs " + card.controlHeight)
}

// A focused field is its own frame in the accent, the error role where its error line shows, and the muted rule once the keyboard leaves.
function checkOctalFrame(shell, tag, card, theme, dialogField) {
    checkOctalHeight(shell, tag, card, dialogField)
    var frame = card.octalFrame
    if (!frame) { shell.check(tag + " octal frame is reachable", false, "no octalFrame"); return }
    var octal = card.controls().find(function (control) { return control.name === "Octal" }).item
    var originalMode = card.modeText
    var holder = card.controls().find(function (control) { return control.item && control.item.activeFocus })
    octal.forceActiveFocus()
    card.modeText = "0644"
    shell.same(tag + " valid octal draws no error", card.displayedError, "")
    shell.same(tag + " focused octal frame is the accent", frame.border.color, theme.color.accent)
    card.modeText = "0649"
    shell.check(tag + " bad octal shows its line", card.displayedError !== "", card.displayedError)
    shell.same(tag + " focused octal frame is the error role while its line shows", frame.border.color, theme.color.error)
    card.modeText = "0644"
    shell.same(tag + " octal frame returns to the accent once the line is gone", frame.border.color, theme.color.accent)
    card.stepFocus(false)
    card.modeText = "0649"
    shell.same(tag + " an unfocused octal frame stays muted", frame.border.color, theme.color.muted)
    // The card goes back as it was found: its own mode text, and focus on what held it or on nothing.
    card.modeText = originalMode
    var stepped = card.controls().filter(function (control) { return control.item && control.item.activeFocus })
    for (var i = 0; i < stepped.length; i++) stepped[i].item.focus = false
    if (holder) holder.item.forceActiveFocus()
    shell.same(tag + " the octal check leaves the card's own mode", card.modeText, originalMode)
    var holding = card.controls().filter(function (control) { return control.item && control.item.activeFocus })
    shell.same(tag + " the octal check leaves focus where it found it", holding.map(function (control) { return control.name }).join(","), holder ? holder.name : "")
}
