.import "../../ui/js/MouseNav.js" as MouseNav
.import "../../ui/js/Nav.js" as Nav
.import "nav.js" as NavSuite
.import "sourcefixture.js" as Source

// A pane one back away with its own goForward taken from ui/Pane.qml, so the mouse and the key share one set of refusals.
function forwardPane(history) {
    var p = NavSuite.browsing(history)
    var source = Source.slice(Source.source("ui/Pane.qml"), "function goForward()", "// Rename lives").trim()
    p.trash = { opened: false, confirming: false, closed: 0, close: function () { this.closed += 1 } }
    p.recentMode = ""
    p.menuActions = { opened: false }
    p.renameEditor = function () { return null }
    p.sidebar = null
    p.goForward = new Function("root", "trashHost", "Nav", "return (" + source + ")")(p, p.trash, Nav)
    return p
}

// The window's side-button handler, taken from ui/WindowBody.qml, with every overlay it reads in its shut state.
function handlerFor(pane) {
    var source = Source.slice(Source.source("ui/WindowBody.qml"), "onTapped: function (eventPoint, button) {",
                              "\n    }\n\n    Component.onCompleted:").replace(/^onTapped:\s*/, "").trim()
    var overlays = { settingsPanel: { opened: false }, chrome: { editing: false }, convertDialog: { opened: false },
        permissionsDialog: { opened: false }, keymapSheet: { opened: false }, networkDialog: { opened: false },
        shareBrowser: { active: false, owner: null }, preview: { active: false } }
    var tap = new Function("view", "settingsPanel", "chrome", "convertDialog", "permissionsDialog", "keymapSheet",
        "networkDialog", "shareBrowser", "preview", "Nav", "MouseNav", "Qt", "return (" + source + ")")(
        { currentPane: pane }, overlays.settingsPanel, overlays.chrome, overlays.convertDialog, overlays.permissionsDialog,
        overlays.keymapSheet, overlays.networkDialog, overlays.shareBrowser, overlays.preview, Nav, MouseNav, Qt)
    return { tap: tap, overlays: overlays }
}

// What a pane did with one press, as one line: where it stands, the listings it asked for and the forward entries left.
function stood(pane) {
    return pane.path + "|" + pane.sent.length + "|" + pane.forwardHistory.length
}

function run(check) {
    // Back then forward is a round trip, and forward hands back the history back took.
    var round = forwardPane(["/home/gm"])
    Nav.mouseBack(round)
    check("mouse back goes to the remembered directory", round.path, "/home/gm")
    // ui/PaneSwap.qml clears this when the rows land; the stub's listing answers at the request.
    round.listInFlight = false
    MouseNav.forward(round)
    check("mouse forward retraces it", round.path, "/home/gm/Work")
    check("and puts the directory it left back behind it", round.history.join(",") + "|" + round.forwardHistory.length, "/home/gm|0")

    // With nothing ahead, forward is no navigation at all: it neither climbs nor asks for a listing.
    var ahead = forwardPane(["/home/gm"])
    MouseNav.forward(ahead)
    check("mouse forward with nothing ahead stays put and asks for no listing", stood(ahead), "/home/gm/Work|0|0")

    // A press during a load keeps the entry it would have taken, as back's guard does.
    var busy = forwardPane([])
    busy.forwardHistory = ["/home/gm/Work/flea"]
    busy.listInFlight = true
    MouseNav.forward(busy)
    check("a forward press during a load keeps the entry it would have taken",
          busy.forwardHistory.join(",") + "|" + busy.path, "/home/gm/Work/flea|/home/gm/Work")

    // Behind the pane's own context menu or the collision card the press does nothing, as back's does.
    var menuUp = forwardPane([])
    menuUp.forwardHistory = ["/home/gm/Work/flea"]
    menuUp.menuVisible = true
    MouseNav.forward(menuUp)
    check("mouse forward behind an open context menu goes nowhere", stood(menuUp), "/home/gm/Work|0|1")
    var cardUp = forwardPane([])
    cardUp.forwardHistory = ["/home/gm/Work/flea"]
    cardUp.collide = { opened: true }
    MouseNav.forward(cardUp)
    check("mouse forward behind an open collision card goes nowhere", stood(cardUp), "/home/gm/Work|0|1")

    // The keyboard's forward refuses in Trash and in Recent, so the mouse takes the same entry and the same refusals.
    var trashed = forwardPane([])
    trashed.forwardHistory = ["/home/gm/Work/flea"]
    trashed.trash.opened = true
    MouseNav.forward(trashed)
    check("mouse forward with Trash open goes nowhere", stood(trashed), "/home/gm/Work|0|1")
    var recent = forwardPane([])
    recent.forwardHistory = ["/home/gm/Work/flea"]
    recent.recentMode = "recent"
    MouseNav.forward(recent)
    check("mouse forward in Recent goes nowhere", stood(recent), "/home/gm/Work|0|1")

    // The window's own handler: forward in Trash does nothing, back there closes Trash, and no overlay lets either through.
    var inTrash = forwardPane(["/home/gm"])
    inTrash.forwardHistory = ["/home/gm/Work/flea"]
    inTrash.trash.opened = true
    var handler = handlerFor(inTrash)
    handler.tap(null, Qt.ForwardButton)
    check("the forward button in Trash does nothing", stood(inTrash) + "|" + inTrash.trash.closed, "/home/gm/Work|0|1|0")
    handler.tap(null, Qt.BackButton)
    check("the back button in Trash closes it and goes nowhere", stood(inTrash) + "|" + inTrash.trash.closed, "/home/gm/Work|0|1|1")
    var open = forwardPane(["/home/gm"])
    var through = handlerFor(open)
    through.tap(null, Qt.BackButton)
    open.listInFlight = false
    through.tap(null, Qt.ForwardButton)
    check("the handler sends back and then forward through the pane", open.path + "|" + open.history.length, "/home/gm/Work|1")
    var blockers = {
        "the pane menu": function (h, p) { p.menuActions.opened = true },
        "settings": function (h, p) { h.overlays.settingsPanel.opened = true },
        "the trash confirm": function (h, p) { p.trash.confirming = true },
        "the path field": function (h, p) { h.overlays.chrome.editing = true },
        "the convert dialog": function (h, p) { h.overlays.convertDialog.opened = true },
        "the permissions dialog": function (h, p) { h.overlays.permissionsDialog.opened = true },
        "the keys sheet": function (h, p) { h.overlays.keymapSheet.opened = true },
        "the network dialog": function (h, p) { h.overlays.networkDialog.opened = true },
        "the share browser": function (h, p) { h.overlays.shareBrowser.active = true; h.overlays.shareBrowser.owner = p },
        "a preview": function (h, p) { h.overlays.preview.active = true },
        "a rename editor": function (h, p) { p.renameEditor = function () { return {} } },
        "the sidebar's rename editor": function (h, p) { p.sidebar = { renameEditor: function () { return {} } } }
    }
    for (var name in blockers) {
        for (var button of [Qt.BackButton, Qt.ForwardButton]) {
            var held = forwardPane(["/home/gm"])
            held.forwardHistory = ["/home/gm/Work/flea"]
            var guard = handlerFor(held)
            blockers[name](guard, held)
            guard.tap(null, button)
            check("a side button behind " + name + " goes nowhere", stood(held) + "|" + held.history.length, "/home/gm/Work|0|1|1")
        }
    }
}
