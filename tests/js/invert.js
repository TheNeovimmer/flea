.import "../../ui/js/Marks.js" as Marks

function run(check) {
    check("invert flips over the whole listing",
        Marks.inverted(5, null, [1, 3]).join(","), "0,2,4")
    check("invert of nothing is everything",
        Marks.inverted(3, null, []).join(","), "0,1,2")
    check("invert of everything is nothing",
        Marks.inverted(3, null, [0, 1, 2]).join(","), "")
    check("invert follows the filter, not the listing",
        Marks.inverted(5, [1, 2, 3], [1]).join(","), "2,3")
    check("invert never reaches a row the filter hid",
        Marks.inverted(5, [1, 2, 3], []).join(","), "1,2,3")
}
