.import "../../ui/js/MarkdownPrepared.js" as Prepared
.import "sourcefixture.js" as Source

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
    // Rows as the backend writes them: p is the whole st_mode, so its type bits say regular file, fifo, socket, device or link.
    var regular = { n: "a.md", d: false, s: 900, p: 33188, k: 0 }
    function row(patch) { var r = {}; for (var k in regular) r[k] = regular[k]; for (var q in patch) r[q] = patch[q]; return r }
    check("a small regular local Markdown file reads inline", Prepared.readsInline(regular, "", true), true)
    check("a file at the cap reads inline", Prepared.readsInline(row({ s: Prepared.MAX_BYTES }), "", true), true)
    check("a file past the cap does not", Prepared.readsInline(row({ s: Prepared.MAX_BYTES + 1 }), "", true), false)
    check("an empty file does not, since its size says nothing about what a read returns", Prepared.readsInline(row({ s: 0 }), "", true), false)
    check("a named pipe named .md never does", Prepared.readsInline(row({ s: 0, p: 4516 }), "", true), false)
    check("a named pipe with a size never does", Prepared.readsInline(row({ p: 4516 }), "", true), false)
    check("a socket never does", Prepared.readsInline(row({ p: 49645 }), "", true), false)
    check("a character device never does", Prepared.readsInline(row({ p: 8612 }), "", true), false)
    check("a symlink never does, whatever its target is", Prepared.readsInline(row({ p: 41471 }), "", true), false)
    check("a folder never does", Prepared.readsInline(row({ d: true }), "", true), false)
    check("another kind of file never does", Prepared.readsInline(row({ n: "a.txt" }), "", true), false)
    check("no row never does", Prepared.readsInline(null, "", true), false)
    // kernel cifs, nfs and every listed FUSE share (sshfs, rclone, s3fs) classify as network; a phone is its own class.
    var classes = ["network", "phone", "usb"]
    for (var i = 0; i < classes.length; i++)
        check("a " + classes[i] + " mount never reads inline or ahead", Prepared.readsInline(regular, classes[i], true), false)
    // A class that has not landed is never spent as local: it reads nothing until the reply says local.
    check("a local file reads nothing before its folder's class is known", Prepared.readsInline(regular, "", false), false)
    // The pictures a prepared document names are sized by stat and decoded ahead only when small and local.
    var doc = [{ type: "image", url: "file:///d/a.png" }, { type: "run", text: "x" },
        { type: "images", items: [{ url: "file:///d/b%20c.png" }, { url: "file:///d/a.png" }, { url: "https://x/y.png" }] }]
    check("a document's local pictures are named once, in reading order", JSON.stringify(Prepared.pictureUrls(doc, 8, "/d")), JSON.stringify(["file:///d/a.png", "file:///d/b%20c.png"]))
    check("a document past the limit names only the first pictures", JSON.stringify(Prepared.pictureUrls(doc, 1, "/d")), JSON.stringify(["file:///d/a.png"]))
    check("a document with no picture names none", JSON.stringify(Prepared.pictureUrls([{ type: "run", text: "x" }], 8, "/d")), JSON.stringify([]))
    check("a percent-encoded name is stat'd by its path", Prepared.pathOfUrl("file:///d/b%20c.png"), "/d/b c.png")
    check("a stray percent decodes to nothing instead of throwing", Prepared.pathOfUrl("file:///d/100%.png"), "")
    var odd = [{ type: "image", url: "file:///d/100%.png" }, { type: "image", url: "file:///d/ok.png" }]
    check("a picture with a stray percent is skipped, the rest are kept", JSON.stringify(Prepared.pictureUrls(odd, 8, "/d")), JSON.stringify(["file:///d/ok.png"]))
    // A picture on another path, a share among them, is never stat'd: only the document's own folder shares the class readsInline cleared.
    var away = [{ type: "image", url: "file:///mnt/nas/a.png" }, { type: "image", url: "file:///d/../e/a.png" }, { type: "image", url: "file:///dd/a.png" },
        { type: "image", url: "file:///d/img/in.png" }, { type: "image", url: "file:///d/%2e%2e/e/b.png" }]
    check("only pictures under the document's folder are named", JSON.stringify(Prepared.pictureUrls(away, 8, "/d")), JSON.stringify(["file:///d/img/in.png"]))
    check("a document at the root names none", JSON.stringify(Prepared.pictureUrls(away, 8, "")), JSON.stringify([]))
    var urls = ["file:///d/a.png", "file:///d/big.png", "file:///d/gone.png", "file:///d/b%20c.png", "file:///d/empty.png"]
    var statText = "2048\t/d/a.png\n" + (Prepared.PICTURE_MAX_BYTES + 1) + "\t/d/big.png\n" + Prepared.PICTURE_MAX_BYTES + "\t/d/b c.png\n0\t/d/empty.png\n"
    check("only a sized, non-empty picture within the cap is held", JSON.stringify(Prepared.smallPictures(urls, statText)), JSON.stringify(["file:///d/a.png", "file:///d/b%20c.png"]))
    check("a stat that printed nothing holds nothing", JSON.stringify(Prepared.smallPictures(urls, "")), JSON.stringify([]))
    // Neither the read nor the parse of a resting cursor may run on the UI thread: no FileView, no blocking read, no parser call in the item.
    var prepareSource = Source.source("ui/QuickLookPrepare.qml")
    check("the rest-time prepare calls no parser", prepareSource.indexOf("Markdown.blocks(") < 0, true)
    check("the rest-time prepare never reads blocking", prepareSource.indexOf("blockLoading") < 0 && prepareSource.indexOf("FileView") < 0, true)
    check("the rest-time prepare parses in the Markdown worker", prepareSource.indexOf('source: "MarkdownWorker.js"') >= 0, true)
}
