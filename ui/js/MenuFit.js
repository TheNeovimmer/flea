.pragma library

// How many times a card read its rows' wanted widths, so a test pins an open to one read a build and never one per row.
var reads = 0

// The widest wantedWidth among a card's rows, which ui/ContextMenu.qml's widestRow reads for the card's fit.
function widestWanted(rows) {
    reads += 1
    var widest = 0
    for (var i = 0; i < rows.length; i++)
        widest = Math.max(widest, rows[i].wantedWidth || 0)
    return widest
}
