.import "../../ui/js/MarkdownPrepared.js" as Prepared

// The one parsed entry Quick Look takes without parsing: it answers only for the same file, text, folder, chrome and ink.

function run(check) {
    var blocks = [{ type: "run", text: "hello" }]
    var text = "# hello\n"
    check("an empty store answers nothing", Prepared.take("/d/a.md", text, "/d/", "#101315", "#c0caf5"), null)
    Prepared.store("/d/a.md", text, "/d/", "#101315", "#c0caf5", blocks)
    check("the same request takes the stored blocks", Prepared.take("/d/a.md", text, "/d/", "#101315", "#c0caf5"), blocks)
    check("a file edited since the parse misses", Prepared.take("/d/a.md", text + "more\n", "/d/", "#101315", "#c0caf5"), null)
    check("another file with the same text misses", Prepared.take("/d/b.md", text, "/d/", "#101315", "#c0caf5"), null)
    check("another folder misses", Prepared.take("/d/a.md", text, "/e/", "#101315", "#c0caf5"), null)
    check("another chrome misses, the column's surface among them", Prepared.take("/d/a.md", text, "/d/", "#181825", "#c0caf5"), null)
    check("another ink misses", Prepared.take("/d/a.md", text, "/d/", "#101315", "#ffffff"), null)
    var big = new Array(Prepared.MAX_BYTES + 2).join("x")
    Prepared.store("/d/big.md", big, "/d/", "#101315", "#c0caf5", blocks)
    check("a document past the limit is never held", Prepared.take("/d/big.md", big, "/d/", "#101315", "#c0caf5"), null)
    check("the hex is assembled from the 0..1 components", Prepared.hexOf({ r: 16 / 255, g: 19 / 255, b: 21 / 255 }), "#101315")
    check("a low component keeps its leading zero", Prepared.hexOf({ r: 0, g: 1 / 255, b: 10 / 255 }), "#00010a")
}
