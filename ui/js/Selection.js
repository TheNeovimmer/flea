.pragma library

// A selection is a set of row indices over the current listing; a new list clears it, because an index
// into a directory that has changed means nothing. Task 8 declined ScriptModel plus ItemSelectionModel
// on measured memory (see AGENTS.md "The list model"), so this is a hand-rolled index set instead.
function create() {
    var rows = {}
    var n = 0
    // True while the set is one row a plain tap or a landing anchor made, which a plain move carries along.
    var lone = false
    // Additive Shift ranges: the marks a gesture started from, plus the cursor the last extend left.
    // Every mutator below ends the gesture except the gesture's own apply, so a plain move, a v, a
    // ctrl+click, a select-all or a fresh listing all start a new block; extend detects a move by the
    // cursor no longer matching shiftLast.
    var shiftBase = null
    var shiftLast = -1

    function endShift() { shiftBase = null }

    function has(i) {
        return rows[i] === true
    }

    function add(i) {
        if (!has(i)) { rows[i] = true; n += 1 }
    }

    function remove(i) {
        if (has(i)) { delete rows[i]; n -= 1 }
    }

    function dropLone() { lone = false }
    // v on its lone row keeps it and drops lone, so the next v toggles it off.
    function promote(i) { if (lone && n === 1 && has(i)) { dropLone(); return true } return false }

    return {
        has: has,
        promote: promote,
        count: function () { return n },
        // A lone row follows a plain move; any deliberate mark drops that promise at once.
        follows: function () { return lone && n === 1 },
        toggle: function (i) { dropLone(); endShift(); has(i) ? remove(i) : add(i) },
        only: function (i) { rows = {}; n = 0; add(i); lone = true; endShift() },
        extendTo: function (i, anchor) {
            dropLone()
            endShift()
            var lo = Math.min(i, anchor)
            var hi = Math.max(i, anchor)
            rows = {}
            n = 0
            for (var r = lo; r <= hi; r++)
                add(r)
        },
        all: function (total) {
            dropLone()
            endShift()
            rows = {}
            n = 0
            for (var r = 0; r < total; r++)
                add(r)
        },
        clear: function () { rows = {}; n = 0; dropLone(); endShift() },
        // The gesture's own trio, the only calls that leave the base standing. The base is a snapshot
        // taken once at gesture start, never per key, so the gesture's range may shrink without dropping it.
        shiftBegin: function (base, last) { shiftBase = base.slice(); shiftLast = last },
        shiftMoved: function (last) { shiftLast = last },
        shiftState: function () { return shiftBase === null ? null : { base: shiftBase, last: shiftLast } },
        shiftApply: function (range) {
            dropLone()
            rows = {}
            n = 0
            for (var i = 0; i < shiftBase.length; i++)
                add(shiftBase[i])
            for (var j = 0; j < range.length; j++)
                add(range[j])
        },
        indices: function () {
            var out = []
            for (var k in rows)
                out.push(Number(k))
            out.sort(function (a, b) { return a - b })
            return out
        }
    }
}
