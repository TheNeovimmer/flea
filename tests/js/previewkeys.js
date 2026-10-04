.import "../../ui/js/PreviewKeys.js" as PreviewKeys
.import "../../ui/js/Keymap.js" as Keymap
.import "sourcefixture.js" as Source

function run(check) {
    var activated = []
    var viewer = { pdfControlIndex: -1, pdfControls: [], turnPage: function() {},
        zoomBy: function() {}, toggleExpand: function() {}, scrollPage: function() {} }
    for (var i = 0; i < 6; i++) {
        (function(index) {
            viewer.pdfControls.push({enabled: index !== 0 && index !== 2, visible: true,
                activated: function() { activated.push(index) }})
        })(i)
    }
    PreviewKeys.pdfAction("focusNext", viewer)
    check("PDF focus enters first enabled control", viewer.pdfControlIndex, 1)
    PreviewKeys.pdfAction("preview", viewer)
    PreviewKeys.pdfAction("focusPrevious", viewer)
    check("PDF reverse focus wraps to Close", viewer.pdfControlIndex, 5)
    PreviewKeys.pdfAction("open", viewer)
    check("Space and Enter activate the focused PDF controls", activated.join(","), "1,5")
    viewer.pdfControls[5].enabled = false
    PreviewKeys.pdfAction("preview", viewer)
    check("a control disabled after focus never activates", activated.join(","), "1,5")
    viewer.pdfControls[5].visible = false
    PreviewKeys.pdfAction("focusNext", viewer)
    check("forward wrap skips disabled Previous", viewer.pdfControlIndex, 1)
    PreviewKeys.pdfAction("trash", viewer)
    check("listing actions do nothing in PDF context", activated.join(","), "1,5")

    // GM, 2026-09-11: "pressing space a second time should close the preview, just like Finder
    // does". It closes on every kind, media included, which reverses Task 22's play/pause on space.
    function previewPane(kind) {
        var pane = { closed: 0, played: 0 }
        pane.preview = {
            isMedia: kind === "audio" || kind === "video",
            isPdf: kind === "pdf",
            revealStrip: function () {},
            close: function () { pane.closed += 1 },
            togglePlay: function () { pane.played += 1 }
        }
        return pane
    }
    for (var kind of ["text", "image", "pdf", "archive", "audio", "video"]) {
        var open = previewPane(kind)
        PreviewKeys.act("preview", open)
        check("space closes a " + kind + " preview", open.closed, 1)
        check("and plays nothing on a " + kind + " preview", open.played, 0)
    }
    // Escape still closes, because a preview must never need a particular key to leave it.
    var escaped = previewPane("video")
    PreviewKeys.act("escape", escaped)
    check("escape still closes a media preview", escaped.closed, 1)

    // Space no longer plays, so p does, and only where there is something to play.
    var tune = previewPane("audio")
    PreviewKeys.act("playPause", tune)
    check("p plays and pauses a media preview", tune.played, 1)
    check("and closes nothing", tune.closed, 0)
    var still = previewPane("image")
    PreviewKeys.act("playPause", still)
    check("p does nothing to a still preview", still.played + still.closed, 0)
    check("space maps to preview in the pdf context", Keymap.lookupFor("default", Qt.Key_Space, " ", Qt.NoModifier, "pdf", "gui"), "preview")
    var viewerSrc = Source.source("ui/PdfViewer.qml")
    var keysBody = Source.slice(viewerSrc, "Keys.onPressed", "readonly property int page")
    check("the pdf viewer closes on the preview action", keysBody.indexOf('|| action === "preview") root.closed()') >= 0, true)

    // RenderedPreviews callout 1: r switches a Markdown Quick Look and nothing else.
    function markPane(markdown) {
        var pane = { switched: 0 }
        pane.preview = {
            isMarkdown: markdown,
            revealStrip: function () {},
            toggleMarkdownView: function () { pane.switched += 1 }
        }
        return pane
    }
    var notes = markPane(true)
    PreviewKeys.act("markdownView", notes)
    check("r switches a Markdown preview", notes.switched, 1)
    var photo = markPane(false)
    PreviewKeys.act("markdownView", photo)
    check("r does nothing to a non-Markdown preview", photo.switched, 0)
    check("r maps to markdownView in the preview context",
        Keymap.lookupFor("default", 0, "r", Qt.NoModifier, "preview", "gui"), "markdownView")
    var quickSrc = Source.source("ui/Preview.qml")
    check("the Quick Look flip is a local property and stores no choice",
        quickSrc.indexOf("root.markdownSource = !root.markdownSource") >= 0 && quickSrc.indexOf("markdownView:") < 0, true)
    check("r stays rename in the listing",
        Keymap.lookupFor("default", 0, "r", Qt.NoModifier, "listing", "gui"), "rename")
    // ButtonSystem040: Tab and Shift+Tab put the keyboard on the Markdown bar's close mark and take it off; Return or Space on it closes.
    function closePane(markdown) {
        var pane = { closed: 0 }
        pane.preview = {
            isMarkdown: markdown,
            markdownCloseFocused: false,
            revealStrip: function () {},
            toggleMarkdownClose: function () { pane.preview.markdownCloseFocused = !pane.preview.markdownCloseFocused },
            close: function () { pane.closed += 1 }
        }
        return pane
    }
    var bar = closePane(true)
    PreviewKeys.act("focusNext", bar)
    check("Tab focuses the Markdown close mark", bar.preview.markdownCloseFocused, true)
    PreviewKeys.act("focusPrevious", bar)
    check("Shift+Tab takes the focus off it", bar.preview.markdownCloseFocused, false)
    PreviewKeys.act("open", bar)
    check("Return on a close mark that holds no focus closes nothing", bar.closed, 0)
    PreviewKeys.act("focusPrevious", bar)
    check("Shift+Tab also reaches the close mark", bar.preview.markdownCloseFocused, true)
    PreviewKeys.act("open", bar)
    check("Return on the focused close mark closes", bar.closed, 1)
    PreviewKeys.act("preview", bar)
    check("Space still closes", bar.closed, 2)
    PreviewKeys.act("escape", bar)
    check("Escape still closes", bar.closed, 3)
    var plain = closePane(false)
    PreviewKeys.act("focusNext", plain)
    PreviewKeys.act("focusPrevious", plain)
    PreviewKeys.act("open", plain)
    check("Tab and Return mean nothing to a preview with no Markdown bar", plain.preview.markdownCloseFocused + plain.closed, 0)
    check("Tab maps to focusNext in the preview context",
        Keymap.lookupFor("default", Qt.Key_Tab, "\t", Qt.NoModifier, "preview", "gui"), "focusNext")
    check("Shift+Tab maps to focusPrevious in the preview context",
        Keymap.lookupFor("default", Qt.Key_Backtab, "", Qt.ShiftModifier, "preview", "gui"), "focusPrevious")
    check("Return maps to open in the preview context",
        Keymap.lookupFor("default", Qt.Key_Return, "\r", Qt.NoModifier, "preview", "gui"), "open")
    var paneSrc = Source.source("ui/MarkdownPane.qml")
    check("the close mark takes its keyboard state from the pane",
        Source.slice(paneSrc, "id: barClose", "onActivated").indexOf("keyboardFocused: root.closeFocused") >= 0, true)
    check("previewCloseState reports focused", paneSrc.indexOf("focused: barClose.keyboardFocused") >= 0, true)
    check("the Quick Look hands the toggle to the pane",
        quickSrc.indexOf("function toggleMarkdownClose()") >= 0 && quickSrc.indexOf("readonly property bool markdownCloseFocused") >= 0, true)
    runThumbThreading(check)
}

// The cached thumbnail rides into Quick Look in memory, with zero new file work.
function thumbRoot(thumbValue) {
    var calls = []
    var root = { cursorIndex: 5, path: "/d", thumbState: { file: {}, order: [] },
        kindNames: ["Kind"],
        preview: { open: function (p, i, s, k, t) { calls.push(["open", p, t]) },
            follow: function (p, i, s, k, t) { calls.push(["follow", p, t]) } } }
    root.thumbState.file[5] = thumbValue
    root.rowFor = function (i) { return i === 5 ? { n: "b.jpg", d: false, i: "image-x-generic", s: 10, k: 0 } : null }
    root.join = function (b, n) { return b + "/" + n }
    return { root: root, calls: calls }
}

function runThumbThreading(check) {
    var held = thumbRoot("/cache/5.png")
    PreviewKeys.open(held.root)
    check("Space hands the held cache file to Quick Look", held.calls.join(";"), "open,/d/b.jpg,/cache/5.png")
    PreviewKeys.follow(held.root)
    check("a cursor move hands it to follow too", held.calls.join(";"),
        "open,/d/b.jpg,/cache/5.png;follow,/d/b.jpg,/cache/5.png")
    var missed = thumbRoot(undefined)
    PreviewKeys.open(missed.root)
    check("a row with nothing held opens with no interim", missed.calls.join(";"), "open,/d/b.jpg,")
    var dirRoot = thumbRoot("/cache/5.png")
    dirRoot.root.rowFor = function () { return { n: "sub", d: true, i: "folder", s: 0, k: 0 } }
    PreviewKeys.open(dirRoot.root)
    check("a directory opens nothing at all", dirRoot.calls.length, 0)
}
