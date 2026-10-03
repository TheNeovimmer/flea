.pragma library

// The Permissions040 card for several items, read off the live dialog by tests/permissions-focus.qml.
var SINGLE_RULES = 3
var HEADING = "WILL CHANGE"
var MIXED_HINT = "Mixed boxes keep each file's own bit unless you change them."
var ERROR_NOTE = "Permission layout fixture refusal."
var BUSY_NOTE = "Reading permissions…"
// The board is drawn at base size 14: the surface gap is 8 px and the button row adds 6 above itself.
var BOARD_BASE = 14
var BOARD_GAP = 8
var BOARD_LEAD = 6
// The card is centred, so the rounded IPC rectangle may differ from the float height by one pixel.
var IPC_ROUNDING = 1

function visibleItems(item) {
    var items = []
    if (!item.visible)
        return items
    items.push(item)
    for (var i = 0; i < item.children.length; i++)
        items = items.concat(visibleItems(item.children[i]))
    return items
}

// A positioner lays out on the next frame, so a read right after a change forces every one, children first.
function settle(item) {
    for (var i = 0; i < item.children.length; i++)
        settle(item.children[i])
    if (typeof item.forceLayout === "function")
        item.forceLayout()
}

function parts(card, theme) {
    settle(card.bodyItem)
    var items = visibleItems(card.bodyItem)
    return {
        items: items,
        rules: items.filter(function (item) {
            return String(item).indexOf("QQuickRectangle") === 0
                && item.height === theme.spacing.hairline && item.width === card.bodyItem.width
        }),
        headings: items.filter(function (item) { return item.text === HEADING }),
        lastRow: items.find(function (item) { return item.text === "Everyone" }).parent,
        hint: items.find(function (item) { return item.text === MIXED_HINT }),
        cancel: card.controls().find(function (control) { return control.name === "Cancel" }).item
    }
}

function top(card, item) { return item.mapToItem(card.bodyItem, 0, 0).y }
function bottom(card, item) { return top(card, item) + item.height }

// One item keeps its three rules and its heading; several items keep neither, and the hint and buttons follow the board's gaps.
function checkLayout(harness, card, theme) {
    var layout = parts(card, theme)
    harness.check("body rules", layout.rules.length, card.isMulti ? 0 : SINGLE_RULES)
    harness.check("change headings", layout.headings.length, card.isMulti ? 0 : 1)
    if (!card.isMulti) {
        console.log("PERMFOCUS SINGLE_GEOMETRY " + harness.label() + " " + JSON.stringify({
            card: [card.cardItem.x, card.cardItem.y, card.cardItem.width, card.cardItem.height],
            body: [card.bodyItem.x, card.bodyItem.y, card.bodyItem.width, card.bodyItem.height, card.bodyItem.wanted],
            rows: layout.items.filter(function (item) { return item.parent === layout.lastRow.parent && item.height > 0 })
                .map(function (item) { return [item.x, item.y, item.width, item.height] })
        }))
        return
    }
    harness.check("text size is the board's", theme.baseSize, BOARD_BASE)
    harness.check("surface gap is the board's 8 px", card.multiGap, BOARD_GAP)
    harness.check("button lead is the board's 6 px", card.buttonLead, BOARD_LEAD)
    harness.check("hint follows the grid by one gap", top(card, layout.hint) - bottom(card, layout.lastRow), BOARD_GAP)
    harness.check("buttons follow the hint by a gap and the lead", top(card, layout.cancel) - bottom(card, layout.hint), BOARD_GAP + BOARD_LEAD)
    harness.check("body height ends at the buttons", card.bodyItem.wanted, bottom(card, layout.cancel))
    var state = JSON.parse(harness.ipcObject().seam.permissionsState())
    harness.check("IPC summary holds only the drawn hint", state.displayedSummary, MIXED_HINT)
    harness.check("IPC card height is the drawn card's", Math.abs(Number(state.rect.split(" ")[3]) - card.cardItem.height) <= IPC_ROUNDING, true)
}

// The busy line, then the error line, each held on the card for one read and then cleared as production clears them.
function checkStatuses(harness, card, theme) {
    card.multiPending = card.multiPaths.length
    card.busy = true
    checkStatus(harness, card, theme, BUSY_NOTE)
    card.busy = false
    card.multiPending = 0
    card.errorText = ERROR_NOTE
    checkStatus(harness, card, theme, ERROR_NOTE)
    card.errorText = ""
}

// The busy and error line stays visible between the grid and the hint, with the gaps the board keeps around the hint.
function checkStatus(harness, card, theme, text) {
    var layout = parts(card, theme)
    var messages = layout.items.filter(function (item) { return item.text === text })
    harness.check("status text stays visible", messages.length, 1)
    var message = messages[0]
    harness.check("status ink follows the grid by the dialog's gap", top(card, message) + message.topPadding - bottom(card, layout.lastRow), theme.spacing.gap)
    harness.check("hint follows the status by one gap", top(card, layout.hint) - bottom(card, message), BOARD_GAP)
    harness.check("buttons still follow the hint by a gap and the lead", top(card, layout.cancel) - bottom(card, layout.hint), BOARD_GAP + BOARD_LEAD)
}
