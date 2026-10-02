.pragma library

.import "Anchor.js" as Anchor
.import "Format.js" as Format

// Sample input: 2 is "Reloaded · 2 rows changed", 1 is "Reloaded · 1 row changed".
function line(changed) {
    return "Reloaded · " + Format.count(changed) + (changed === 1 ? " row changed" : " rows changed")
}

// A listing out refuses itself and a search owns its header, so both go quiet.
function begin(pane, wire) {
    if (pane.listInFlight) {
        pane.message("A directory is already loading.", false)
        return false
    }
    if (pane.searchMode.length > 0)
        return false
    // Recent re-reads its history rather than re-listing its base, which is the root.
    if (pane.recentMode.length > 0) {
        pane.refresh("")
        pane.reloadFrom = pane.total
        pane.reloadChanged = -1
        return true
    }
    wire.anchor = Anchor.watched(pane)
    // Set after the anchored re-read above, because opening the listing clears it first.
    pane.reloadFrom = pane.total
    pane.reloadChanged = -1
    return true
}

// Runs on every rows reply; only a manual reload owes a notice, said whenever rows changed.
function landed(pane) {
    if (pane.reloadFrom < 0)
        return ""
    // The backend counts added plus removed on a same-path re-list; a missing one falls back to net delta.
    var changed = pane.reloadChanged >= 0 ? pane.reloadChanged : Math.abs(pane.total - pane.reloadFrom)
    pane.reloadFrom = -1
    pane.reloadChanged = -1
    if (changed === 0)
        return ""
    var text = line(changed)
    pane.message(text, false)
    return text
}
