.import "../../ui/js/SheetQuery.js" as SheetQuery

function run(check) {
    // Candidate building from a stub menu model, a stub rail and a stub recent list, plus
    // the Enter dispatch decision. The menu entries arrive as Menu.listingEntries builds
    // them; the sheet passes no hidden filter, so a row Settings Menus hides is still found.
    function hint(action) {
        if (action === "deletePermanently") {
            return "shift-delete"
        }
        if (action === "trash") {
            return "dd"
        }
        return ""
    }
    var entries = [
        { id: "trash", action: "trash", label: "Move to Trash" },
        { id: "deletePermanently", action: "deletePermanently", label: "Delete permanently", danger: true },
        { id: "permissions", action: "permissions", label: "Permissions" },
        { id: "paste", action: "paste", label: "Paste", disabled: true },
        { id: "compress", action: "compress", label: "Compress",
          submenu: [{ id: ".zip", label: "Compress to .zip" }, { separator: true },
                    { id: ".7z", label: "Compress to .7z", disabled: true }] }
    ]
    var menus = SheetQuery.menuCandidates(entries, hint)
    check("a hidden row is still found",
          menus.some(function (row) { return row.label === "Permissions" }), true)
    check("a row with a key keeps its cap",
          menus.filter(function (row) { return row.label === "Delete permanently"; })[0].keys, "shift-delete")
    check("a keyless row draws no cap",
          menus.filter(function (row) { return row.label === "Permissions"; })[0].keys, "")
    check("a leaf reads its flyout for the muted suffix",
          menus.filter(function (row) { return row.label === "Compress to .zip"; })[0].where, "Compress")
    check("a leaf carries no cap",
          menus.filter(function (row) { return row.label === "Compress to .zip"; })[0].keys, "")
    check("a separator inside a flyout is no row",
          menus.some(function (row) { return row.menuAction === "compress:"; }), false)
    check("a disabled row is flagged",
          menus.filter(function (row) { return row.label === "Paste"; })[0].disabled, true)
    check("a disabled leaf is flagged too",
          menus.filter(function (row) { return row.label === "Compress to .7z"; })[0].disabled, true)
    // The rail's places read "Open <name>" with the group name the rail shows.
    var rail = [
        { label: "flea", group: "favourite", kind: "favourite", path: "/home/gm/flea" },
        { label: "Trash", group: "trash", kind: "trash", path: "trash:///" },
        { label: "NAS", group: "network", kind: "share", uri: "smb://host/data" },
        { label: "Recent", group: "recent", kind: "recent", path: "flea:recent" }
    ]
    var places = SheetQuery.placeCandidates(rail)
    check("a favourite says Favorites",
          places.filter(function (row) { return row.name === "flea"; })[0].where, "Favorites")
    check("trash says Places",
          places.filter(function (row) { return row.name === "Trash"; })[0].where, "Places")
    check("a share keeps its group name",
          places.filter(function (row) { return row.name === "NAS"; })[0].where, "Network")
    check("the Recent row is no place",
          places.some(function (row) { return row.name === "Recent"; }), false)
    check("a place reads Open plus its name",
          places.filter(function (row) { return row.name === "Trash"; })[0].label, "Open Trash")
    // Recent files read "Open <file>" with the parent folder, home abbreviated, from the same
    // xbel source the Recent place uses, bounded with no per-entry stat.
    var recents = SheetQuery.recentCandidates(["/home/gm/Documents/claude/mix.flac", "/etc/hosts"], "/home/gm")
    check("a recent file reads Open plus its leaf", recents[0].label, "Open mix.flac")
    check("its parent is home abbreviated", recents[0].where, "~/Documents/claude")
    check("a root outside home is left whole", recents[1].where, "/etc")
    // Enter runs the highlighted row: an action as its key, a menu row as the menu, a place
    // like a rail click, a recent file like Enter on that row, a destructive row through its
    // confirm, and a disabled row never runs.
    var actionRow = SheetQuery.actionCandidates([{ label: "trash", keys: "dd", action: "trash", context: "listing" }])[0]
    check("an action dispatches as its key", SheetQuery.dispatch(actionRow).kind, "action")
    var menuRow = menus.filter(function (row) { return row.label === "Move to Trash"; })[0]
    check("a menu row dispatches as the menu", SheetQuery.dispatch(menuRow).kind, "menu")
    var confirmRow = menus.filter(function (row) { return row.label === "Delete permanently"; })[0]
    var confirm = SheetQuery.dispatch(confirmRow)
    check("a destructive row keeps its confirm", confirm.kind, "confirm")
    check("through the row the menu would run", confirm.menuAction, "deletePermanently")
    var placeRow = places.filter(function (row) { return row.name === "Trash"; })[0]
    check("a place dispatches as a rail click", SheetQuery.dispatch(placeRow).kind, "place")
    check("a recent file dispatches as its row", SheetQuery.dispatch(recents[0]).kind, "recent")
    var disabledRow = menus.filter(function (row) { return row.label === "Paste"; })[0]
    check("a disabled row never runs", SheetQuery.dispatch(disabledRow).kind, "disabled")
}
