.pragma library

// Where the Permissions card's bit columns, their headings and its octal frame sit, read off the live dialog by tests/permissions-adv.qml.

// Permissions040 at 14: a 480 card, its READ, WRITE and EXEC headings in thirds of the 350 the label leaves, an 18 px box centred in each, in card px.
var BOARD_STOP = 14
var BOARD_CARD_WIDTH = 480
var BOARD_HEAD_X = [113, 230, 346]
var BOARD_HEAD_WIDTH = [117, 116, 117]
var BOARD_BOX_X = [162, 279, 396]
var COLUMNS = 3
// The note's line box is 1.5 x the caption, and the heading takes the same box.
var LINE_RATIO = 1.5
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

// The heading's line box is centred in its row as the board's flex row centres it, and its glyphs are centred in the box as the note's are.
function checkHeading(shell, tag, card, captionHeight, caption) {
    var head = textsNamed(card.bodyItem, "READ", [])[0]
    if (!head) { shell.check(tag + " heading is reachable", false, "no READ"); return }
    var box = Math.round(LINE_RATIO * caption)
    var got = head.lineHeight + "/" + (head.lineHeightMode === FIXED_HEIGHT) + "/" + head.topPadding + "/" + head.y
    shell.same(tag + " heading line box is centred in its row and holds its glyphs centred", got,
        box + "/true/" + Math.round((box - captionHeight) / 2) + "/" + Math.floor((card.headingHeight - box) / 2))
}

// A focused field is its own frame in the accent, the error role where its error line shows, and the muted rule once the keyboard leaves.
function checkOctalFrame(shell, tag, card, theme) {
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
