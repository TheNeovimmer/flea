.pragma library

// MdUrl: URL reading and image-target classification for rendered Markdown.
// Every scan here advances one character at a time and never re-scans from an
// earlier position, so pathological inputs stay linear. Regexes below are all
// anchored to a fixed start with no nested quantifiers, never run over the tail.
.import "Format.js" as Format

// An http(s) URL, or a protocol-relative one (which inherits https), loads from the network.
function isRemoteUrl(url) {
    return /^(https?:)?\/\//i.test(String(url))
}

function hostOf(url) {
    var rest = String(url).replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, "").replace(/^\/\//, "")
    var host = rest.split(/[\/?#]/)[0]
    if (host.indexOf("@") >= 0)
        host = host.slice(host.lastIndexOf("@") + 1)
    if (host.charAt(0) === "[" && host.indexOf("]") > 0)
        return host.slice(0, host.indexOf("]") + 1)
    var colon = host.indexOf(":")
    host = colon >= 0 ? host.slice(0, colon) : host
    return host.length > 0 ? host : String(url)
}

function dirOf(path) {
    var text = String(path)
    var slash = text.lastIndexOf("/")
    return slash >= 0 ? text.slice(0, slash) : ""
}

// The board's placeholder, in the text flow where a box cannot go: the host it refused.
function placeholder(host) {
    return "Remote image not loaded \u00b7 " + host
}

// Decode one numeric character reference starting at i (after &#); answers the
// character and the index past the semicolon, or null when it is not one.
function numericRef(text, i) {
    var j = i
    var base = 10
    if (text.charAt(j) === "x" || text.charAt(j) === "X") {
        base = 16
        j++
    }
    var start = j
    while (j < text.length) {
        var c = text.charCodeAt(j)
        var digit = base === 16
            ? (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)
            : c >= 48 && c <= 57
        if (!digit)
            break
        j++
    }
    if (j === start || text.charAt(j) !== ";")
        return null
    var code = parseInt(text.slice(start, j), base)
    if (!(code > 0) || code > 1114111)
        return null
    return { ch: String.fromCharCode(code), end: j + 1 }
}

// A URL as the loader reads it: numeric references decoded, percent escapes
// decoded, ASCII whitespace and controls stripped. One pass, linear.
function canonicalUrl(raw) {
    var text = String(raw === undefined || raw === null ? "" : raw)
    var out = ""
    var i = 0
    while (i < text.length) {
        var c = text.charAt(i)
        if (c === "&" && text.charAt(i + 1) === "#") {
            var ref = numericRef(text, i + 2)
            if (ref !== null) {
                out += ref.ch
                i = ref.end
                continue
            }
            out += c
            i++
        } else if (c === "%" && i + 2 < text.length
                && /[0-9a-fA-F]/.test(text.charAt(i + 1)) && /[0-9a-fA-F]/.test(text.charAt(i + 2))) {
            out += String.fromCharCode(parseInt(text.slice(i + 1, i + 3), 16))
            i += 3
        } else {
            var code = text.charCodeAt(i)
            // Spaces survive: angle destinations may legally contain them.
            // Tabs, newlines and other controls never do.
            if (code === 32 || code > 32 && code !== 127)
                out += c
            i++
        }
    }
    return out
}

// Collapse . and a/.. segments without touching the filesystem. Answers null
// when the path escapes its root, so .. can reach beside the file but never above it.
function normalizeSubpath(name) {
    var parts = String(name).split("/")
    var kept = []
    for (var i = 0; i < parts.length; i++) {
        var seg = parts[i]
        if (seg === "" || seg === ".")
            continue
        if (seg === "..") {
            if (kept.length === 0)
                return null
            kept.pop()
            continue
        }
        kept.push(seg)
    }
    if (kept.length === 0)
        return null
    return kept.join("/")
}

// Where an image URL lands: remote (placeholder), local (inside the document's
// folder, as file://), or dropped (any other scheme, an absolute path or file://
// URL outside the folder, or a relative path escaping it: alt text only).
function classifyImage(raw, dir) {
    var url = String(raw === undefined || raw === null ? "" : raw)
    if (url.length === 0)
        return { kind: "dropped" }
    var seen = canonicalUrl(url)
    if (seen.length === 0)
        return { kind: "dropped" }
    if (isRemoteUrl(seen))
        return { kind: "remote", host: hostOf(seen) }
    // data:, file: and every other scheme never reach Qt unexamined.
    var scheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:/.exec(seen)
    if (scheme !== null) {
        if (/^file:/i.test(seen)) {
            var fp = seen.replace(/^file:\/\//i, "").replace(/^file:/i, "")
            try {
                fp = decodeURIComponent(fp)
            } catch (e) {
                return { kind: "dropped" }
            }
            var base = String(dir)
            if (fp === base || fp.indexOf(base + "/") === 0)
                return { kind: "local", url: Format.fileUri(fp) }
        }
        return { kind: "dropped" }
    }
    var name = seen
    if (name.charAt(0) === "<" && name.charAt(name.length - 1) === ">")
        name = name.slice(1, -1)
    if (name.length >= 2 && name.slice(0, 2) === "./")
        name = name.slice(2)
    // An absolute path loads only inside the document's folder tree.
    if (name.charAt(0) === "/" || name.charAt(0) === "\\") {
        var abs = name
        var root = String(dir)
        if (abs === root || abs.indexOf(root + "/") === 0)
            return { kind: "local", url: Format.fileUri(abs) }
        return { kind: "dropped" }
    }
    if (name.length === 0 || name === "." || name === ".." || name.indexOf("\\") >= 0)
        return { kind: "dropped" }
    var collapsed = normalizeSubpath(name)
    if (collapsed === null)
        return { kind: "dropped" }
    return { kind: "local", url: Format.fileUri(String(dir) + "/" + collapsed) }
}
