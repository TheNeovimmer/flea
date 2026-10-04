.pragma library

var FENCE_OPEN = /^ {0,3}(`{3,}|~{3,})(.*)$/
var FENCE_CLOSE = /^ {0,3}(`+|~+)[ \t]*$/

// Sample input: "a\n```js\n![x](u)\n```\nb" answers "a\n\nb", a fence being one empty line; "```a`b" opens none.
function withoutFences(text) {
    var lines = String(text).split("\n")
    var out = []
    for (var i = 0; i < lines.length; i++) {
        var open = FENCE_OPEN.exec(lines[i])
        // A backtick fence's info string holds no backtick, or the line is prose with a code span.
        if (open === null || (open[1].charAt(0) === "`" && open[2].indexOf("`") >= 0)) {
            out.push(lines[i])
            continue
        }
        var close = i + 1
        while (close < lines.length) {
            var hit = FENCE_CLOSE.exec(lines[close])
            if (hit !== null && hit[1].charAt(0) === open[1].charAt(0) && hit[1].length >= open[1].length)
                break
            close++
        }
        out.push("")
        i = close
    }
    return out.join("\n")
}
