.pragma library

.import "Anchor.js" as Anchor
.import "Format.js" as Format

// F5 and Ctrl+R re-read the folder through the listing swap, so the new rows land
// without a blank frame the way every other re-read does. The notice names how many
// rows changed, and only when rows changed.

// Sample input: 2 is "Reloaded · 2 rows changed", 1 is "Reloaded · 1 row changed".
function line(changed) {
    return "Reloaded · " + Format.count(changed) + (changed === 1 ? " row changed" : " rows changed")
}

// The manual re-read behind the reload key, taking the pane and its wire the way
// ui/PaneWire.qml's own reread does. A listing out refuses itself, and a search
// owns its header, so both go quiet rather than re-listing under it.
function begin(pane, wire) {
    if (pane.listInFlight) {
        pane.message("A directory is already loading.", false)
        return false
    }
    if (pane.searchMode.length > 0)
        return false
    wire.anchor = Anchor.watched(pane)
    // Set after the anchored re-read above, because opening the listing clears it first.
    pane.reloadFrom = pane.total
    return true
}

// Runs on every rows reply; only a manual reload owes a notice, and only a changed count.
function landed(pane) {
    if (pane.reloadFrom < 0)
        return ""
    var changed = Math.abs(pane.total - pane.reloadFrom)
    pane.reloadFrom = -1
    if (changed === 0)
        return ""
    var text = line(changed)
    pane.message(text, false)
    return text
}
