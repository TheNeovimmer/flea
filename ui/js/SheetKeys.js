.pragma library
.import "Input.js" as Input

// The keymap sheet's key decisions; imports no QML, so tests drive it.

// Sample input: isPrintable("c") is true, isPrintable("\u007f") is false.
// The Delete keysym carries DEL as its text through libxkbcommon, so the bare range test would type it.
function isPrintable(text) {
    return Input.isPrintable(text)
}

// Sample input: isBareModifier(Qt.Key_Shift) is true, isBareModifier(Qt.Key_A) is false.
// A bare modifier carries no text, so without this the sheet would close under a shifted letter.
function isBareModifier(key) {
    return key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Alt
        || key === Qt.Key_AltGr || key === Qt.Key_Meta || key === Qt.Key_CapsLock
}

// Sample input: sheetKey("co", 2, 0, Qt.Key_Shift, "") is "ignore".
// The one decision the sheet's Keys.onPressed runs, so the handler owns no key meaning of its own.
function sheetKey(query, resultCount, cursor, key, text) {
    if (key === Qt.Key_Escape)
        return "close"
    if (String(query).length > 0) {
        if (key === Qt.Key_Up)
            return "up"
        if (key === Qt.Key_Down)
            return "down"
        if (key === Qt.Key_Return || key === Qt.Key_Enter)
            return "activate"
    }
    if (key === Qt.Key_Backspace)
        return String(query).length > 0 ? "backspace" : "close"
    if (isPrintable(text))
        return "type"
    // Delete edits nothing forward, so it is ignored rather than typed or closed on.
    if (key === Qt.Key_Delete || isBareModifier(key))
        return "ignore"
    return "close"
}

// Sample input: stepCursor(0, -1, 3) is 2, stepCursor(2, 1, 3) is 0.
// The cursor wraps at both ends; with no rows it parks at the first.
function stepCursor(cursor, delta, count) {
    if (!(count > 0))
        return 0
    return (((cursor + delta) % count) + count) % count
}
