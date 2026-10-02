.pragma library

// The desktop's own history, read and never written; every bookmark is untrusted input.

// The freedesktop recent file, and where XDG_DATA_HOME defaults to when the session did not set it.
var HISTORY_LEAF = "recently-used.xbel"
var DEFAULT_DATA_HOME = "/.local/share"

// The output loop stops here and hands the rail the newest LIMIT paths.
var LIMIT = 500

// Sample input: ("/home/gm/.local/share", "/home/gm") and ("", "/home/gm"); an XDG_DATA_HOME that
// is not an absolute path is not a data home, so the default answers for it too.
function historyPath(dataHome, home) {
    var root = String(dataHome || "")
    if (root.charAt(0) !== "/") {
        root = String(home || "") + DEFAULT_DATA_HOME
    }
    return root.replace(/\/+$/, "") + "/" + HISTORY_LEAF
}

// Sample input: "file:///home/gm/a%20b.png" becomes "/home/gm/a b.png".
// Refuses non-file schemes, foreign authorities, bad escapes and control characters.
function pathOf(href) {
    var raw = String(href || "")
    if (raw.substring(0, 7).toLowerCase() !== "file://") {
        return ""
    }
    var rest = raw.substring(7)
    // The authority is everything before the path's own leading slash.
    var cut = rest.indexOf("/")
    if (cut < 0) {
        return ""
    }
    var authority = rest.substring(0, cut).toLowerCase()
    if (authority.length > 0 && authority !== "localhost") {
        return ""
    }
    var decoded = ""
    try {
        decoded = decodeURIComponent(rest.substring(cut))
    } catch (e) {
        return ""
    }
    if (decoded.charAt(0) !== "/" || decoded === "/") {
        return ""
    }
    // A control character cannot appear in a path this window will draw or send back as a URI.
    if (/[\x00-\x1f\x7f]/.test(decoded)) {
        return ""
    }
    return decoded
}

// Sample bookmarks: [{ href: "file:///home/gm/a.txt", stamp: "2026-08-30T11:32:04Z" }].
// Newest first with the stamps kept, so the Used column draws the visit, not the mtime.
function entries(bookmarks) {
    var rows = []
    for (var i = 0; i < bookmarks.length; i++) {
        var path = pathOf(bookmarks[i].href)
        if (path.length === 0) {
            continue
        }
        rows.push({ path: path, stamp: String(bookmarks[i].stamp || ""), at: rows.length })
    }
    // The file's own order is the tie-break, so two bookmarks sharing a stamp never swap between reads.
    rows.sort(function (a, b) {
        if (a.stamp === b.stamp) {
            return a.at - b.at
        }
        return a.stamp < b.stamp ? 1 : -1
    })
    var out = []
    var seen = {}
    for (var j = 0; j < rows.length && out.length < LIMIT; j++) {
        if (seen[rows[j].path]) {
            continue
        }
        seen[rows[j].path] = true
        out.push({ path: rows[j].path, stamp: rows[j].stamp })
    }
    return out
}

// Sample input: "/home/gm/a.txt" names "a.txt" in "/home/gm".
// The leaf draws as the name and its parent as the caption beside it.
function nameOf(path) {
    var text = String(path || "")
    var cut = text.lastIndexOf("/")
    return cut < 0 ? text : text.substring(cut + 1)
}

function locationOf(path) {
    var text = String(path || "")
    if (text.length === 0) {
        return ""
    }
    var cut = text.lastIndexOf("/")
    if (cut <= 0) {
        return "/"
    }
    var parent = text.substring(0, cut)
    return parent.charAt(0) === "/" ? parent : "/" + parent
}

// The rail's rows, newest first; a path seen twice keeps its first, newest position.
function paths(bookmarks) {
    return entries(bookmarks).map(function (entry) { return entry.path })
}
