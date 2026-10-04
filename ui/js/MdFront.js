.pragma library

// MdFront: whether the lines at the top of a document are YAML front matter, which draws as a code block.
var KEY_LINE = /^(?:"[^"]*"|'[^']*'|[^\s#"'-][^:]*|-[^\s:][^:]*):(?:[ \t].*)?$/
var CONTINUATION_LINE = /^(?:[ \t]+\S.*|-(?:[ \t].*)?|#.*)$/

// Sample input: ["---", "title: A", "tags:", "  - b", "---"] answers 4, the closing line; ["---", "Foo", "---"] answers -1.
function closeAt(lines) {
    var end = 1
    while (end < lines.length && lines[end] !== "---" && lines[end] !== "...")
        end++
    if (lines[0] !== "---" || end >= lines.length)
        return -1
    var keyed = false
    for (var i = 1; i < end; i++) {
        if (lines[i].trim().length === 0)
            continue
        if (KEY_LINE.test(lines[i]))
            keyed = true
        else if (!keyed || !CONTINUATION_LINE.test(lines[i]))
            return -1
    }
    return keyed ? end : -1
}

// Sample input: lines of a front matter block closing at 4 send an open, a body line per line and a close, all held as code; answers 4.
function sendFront(lines, close, emit, state) {
    emit("fenceOpen", 0, "", null, lines[0])
    state.code[0] = true
    for (var i = 1; i < close; i++) {
        emit("fenceBody", i, lines[i], null, lines[i])
        state.code[i] = true
    }
    emit("fenceClose", close, "", null, lines[close])
    state.code[close] = true
    return close
}
