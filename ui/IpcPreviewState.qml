import QtQuick

// Quick Look and its shared PDF readers report the surfaces already built by the pane.
QtObject {
    id: root

    property var fleaWindow: null
    property var pane: null
    readonly property var columns: root.pane ? root.pane.columnsArea : null
    readonly property int textTailLimit: 4096

    function previewOpen(): bool { return root.pane.preview.active }
    function previewKind(): string { return root.pane.preview.kind }
    function previewState(): string { return root.pane.preview.status }
    function previewPosition(): int { return root.pane.preview.position }
    function previewDuration(): int { return root.pane.preview.duration }
    // Fix round 1: what the strip actually draws, not a re-derived guess at its visible: expression.
    function previewStrip(): string { return JSON.stringify({ visible: root.pane.preview.stripVisible, muted: root.pane.preview.muted, mute: root.fleaWindow.centreOf(root.pane.preview.muteMark) }) }
    // A 0.25 zoom step and an expand flag are not legible off a screenshot, so the seam is the
    // only honest answer for either; "" means no PDF is loaded, which is not zoom 1 or false.
    function previewPdfPage(): int { var p = root.pane.preview.pdfItem; return p ? p.page : -1 }
    function previewPdfZoom(): string { var p = root.pane.preview.pdfItem; return p ? String(p.zoom) : "" }
    function previewPdfFocus(): int { var p = root.pane.preview.pdfItem; return p ? p.pdfControlIndex : -1 }
    function pdfState(overlay: bool): string {
        var p = overlay ? root.pane.preview.pdfItem : root.pane.previewColumnItem
        if (!p) return "null"
        return JSON.stringify({ page: overlay ? p.page : p.pdfPage(), pages: overlay ? p.pageCount : p.pdfPages,
            frame: overlay ? "" : root.fleaWindow.rectOf(p.pdfFrameItem),
            toolbar: overlay ? "" : root.fleaWindow.rectOf(p.pdfToolbarItem),
            zoom: overlay ? p.zoom : p.pdfZoom, scrollY: p.pdfScrollY, focused: p.activeFocus, control: p.pdfControlIndex,
            controls: p.pdfControls.map(function (control) { return { name: control.accessName, enabled: control.enabled,
                visible: control.visible, centre: root.fleaWindow.centreOf(control) } }) })
    }
    function previewExpanded(): string { var p = root.pane.preview.pdfItem; return p ? String(p.expanded) : "" }
    function previewSwapState(): string { return JSON.stringify({ column: root.columns ? root.columns.swapState() : null, look: root.pane.preview.swapState() }) }
    function previewSurfaceRect(): string { return root.fleaWindow.rectOf(root.pane.preview.surfaceItem()) }
    function previewPictureRect(): string { var p = root.pane.preview; if (!p) return ""; if (p.isImage) { var im = p.surfaceItem(); return im ? root.fleaWindow.rectOf(im.pictureItem) : "" } if (p.isMedia) { var me = p.surfaceItem(); return me ? root.fleaWindow.rectOf(me.contentItem) : "" } return "" }
    function previewMediaLoaded(): bool { return root.pane.preview.mediaLoaded() }
    function previewText(): string { return root.pane.preview.textShown() }
    // Length is in UTF-16 code units; the sweep's ASCII fixture has the same byte count.
    function previewTextLength(): int { return root.pane.preview.textShown().length }
    // Keep the reply bounded even if a caller asks for the entire file, including zero and negative counts.
    function previewTextTail(n: int): string {
        var count = Math.max(0, Math.min(n, root.textTailLimit))
        return count > 0 ? root.pane.preview.textShown().slice(-count) : ""
    }
    function previewArchiveNames(): string { return root.pane.preview.archiveNames() }
    // The same lookup as rowCentre, but for the preview's own seek slider, so a test can drive
    // a real wheel event over it without hardcoding the strip's layout.
    function previewSliderCentre(): string {
        return root.pane.preview.active && root.pane.preview.isMedia ? root.fleaWindow.centreOf(root.pane.preview.seekSlider) : ""
    }
}
