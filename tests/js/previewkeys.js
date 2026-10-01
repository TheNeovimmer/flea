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
    check("r stays rename in the listing",
        Keymap.lookupFor("default", 0, "r", Qt.NoModifier, "listing", "gui"), "rename")
}
