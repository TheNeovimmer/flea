.pragma library

.import "Format.js" as Format

// Sample input: "/home/gm/archive.tar.gz"; every Copy as variant covers the
// whole selection, one path per line, through wl-copy.
function leaf(path) {
    var text = String(path)
    var cut = text.lastIndexOf("/")
    return cut < 0 ? text : text.substring(cut + 1)
}

// Sample input: "/home/gm/archive.tar.gz" -> "archive.tar"; a dotfile keeps
// its whole name, so ".bashrc" never becomes an empty stem.
function stem(path) {
    var name = leaf(path)
    var start = name.charAt(0) === "." ? 1 : 0
    var dot = name.lastIndexOf(".")
    if (dot <= start)
        return name
    return name.substring(0, dot)
}

// Sample input: "/home/gm/a.txt" -> "/home/gm"; "/" stays "/".
function dirpath(path) {
    var text = String(path)
    var cut = text.lastIndexOf("/")
    if (cut < 0)
        return text
    return cut === 0 ? "/" : text.substring(0, cut)
}

// Sample input: "/home/gm/a b.txt"; the file URI a clipboard reader expects.
function uri(path) {
    return Format.fileUri(String(path))
}

function one(path, kind) {
    if (kind === "name")
        return leaf(path)
    if (kind === "stem")
        return stem(path)
    if (kind === "dirpath")
        return dirpath(path)
    if (kind === "uri")
        return uri(path)
    if (kind === "quoted")
        return "'" + String(path).split("'").join("'\\''") + "'"
    return String(path)
}

function lines(paths, kind) {
    var out = []
    for (var i = 0; i < paths.length; i++)
        out.push(one(paths[i], kind))
    return out.join("\n")
}
