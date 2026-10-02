.pragma library

// Delete carries DEL through libxkbcommon; retain SheetQuery's single-character semantics.
function isPrintable(text) {
    var s = String(text || "")
    return s.length === 1 && s >= " " && s !== "\u007f"
}
