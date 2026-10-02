.pragma library

// A selection is a set of row indices over the current listing; a new list clears it, because an index
// into a directory that has changed means nothing. Task 8 declined ScriptModel plus ItemSelectionModel
// on measured memory (see AGENTS.md "The list model"), so this is a hand-rolled index set instead.
function create() {
    var rows = {}
    var n = 0
    // True while the set is one row a plain tap or a landing anchor made, which a plain move carries along.
    var lone = false
    // True only for the row a navigation landed on, which Escape climbs past instead of unwinding.
    var landed = false
    // Shift adds to the gesture's starting marks; other mutators end it, and a cursor differing from shiftLast starts a new block.
    var shiftBase = null
    var shiftLast = -1
    var shiftSeq = 0

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

    function dropLone() {
        lone = false
        landed = false
    }
    // v on its lone row keeps it and drops lone, so the next v toggles it off.
    function promote(i) { if (lone && n === 1 && has(i)) { dropLone(); return true } return false }

    return {
        has: has,
        promote: promote,
        count: function () { return n },
        // A lone row follows a plain move; any deliberate mark drops that promise at once.
        follows: function () { return lone && n === 1 },
        // Only a navigation landing keeps the climb-through promise; a click's own only() drops it.
        isLanded: function () { return landed === true && lone && n === 1 },
        toggle: function (i) { dropLone(); endShift(); has(i) ? remove(i) : add(i) },
        only: function (i, keep) {
            rows = {}
            n = 0
            add(i)
            lone = true
            landed = keep === true
            endShift()
        },
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
        shiftBegin: function (base, last, seq) { shiftBase = base.slice(); shiftLast = last; shiftSeq = seq || 0 },
        shiftMoved: function (last, seq) { shiftLast = last; shiftSeq = seq || 0 },
        shiftState: function () { return shiftBase === null ? null : { base: shiftBase, last: shiftLast, seq: shiftSeq } },
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
