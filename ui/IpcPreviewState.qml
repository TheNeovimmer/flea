import QtQuick

// Quick Look and its shared PDF readers report the surfaces already built by the pane.
QtObject {
    id: root

    property var fleaWindow: null
    property var pane: null
    readonly property var columns: root.pane ? root.pane.columnsArea : null
    readonly property int textTailLimit: 4096

    // PaneSwap already exposes its wire; read that wire's actual floor without adding a pane alias.
    function listingDropActive(): bool {
        var wire = root.pane && root.pane.swap ? root.pane.swap.wire : null
        if (!wire) return false
        for (var i = 0; i < wire.children.length; i++) {
            var floor = wire.children[i]
            if (floor.enabled && floor.dest === root.pane.dropPath && floor.containsDrag === true) return true
        }
        return false
    }
    function previewOpen(): bool { return root.pane.preview.active }
    // Read the column's mounted Markdown view, empty until its document is ready.
    function columnMarkdownView(): string {
        var column = root.pane.previewColumnItem
        var markdown = column ? column.markdown : null
        return column && column.visible && markdown && markdown.active && markdown.contentReady ? markdown.view : ""
    }
    function previewKind(): string { return root.pane.preview.kind }
    function previewState(): string { return root.pane.preview.status }
    // One entry per figure block; "" while no Markdown body is mounted, so a case keeps polling.
    function previewFigures(): string {
        var m = root.pane.preview.markdownItem
        if (!m || !m.contentReady || m.blockList === undefined)
            return ""
        var out = []
        for (var i = 0; i < m.blockList.length; i++) {
            if (m.blockList[i].type !== "figure")
                continue
            var info = m.figureInfo(i)
            out.push(i + "=" + (info === null ? "deferred"
                : info.failed ? "failed" : info.ready ? "ready" : info.working ? "working" : "idle"))
        }
        return out.join(",")
    }
    function previewPosition(): int { return root.pane.preview.position }
    function previewDuration(): int { return root.pane.preview.duration }
    // Fix round 1: what the strip actually draws, not a re-derived guess at its visible: expression.
    function previewStrip(): string { return JSON.stringify({ visible: root.pane.preview.stripVisible, muted: root.pane.preview.muted, mute: root.fleaWindow.centreOf(root.pane.preview.muteMark) }) }
    // "" means no PDF is loaded, rather than zoom 1 or expanded false.
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
    function previewSwapState(): string { return JSON.stringify({ column: root.columns ? root.columns.swapState() : null, look: root.pane.preview.swapState(), lookVisible: root.pane.preview.visible }) }
    function previewSurfaceRect(): string { return root.fleaWindow.rectOf(root.pane.preview.surfaceItem()) }
    function previewPictureRect(): string { var p = root.pane.preview; if (!p) return ""; if (p.isImage) { var im = p.surfaceItem(); return im ? root.fleaWindow.rectOf(im.pictureItem) : "" } if (p.isMedia) { var me = p.surfaceItem(); return me ? root.fleaWindow.rectOf(me.contentItem) : "" } return "" }
    function previewMediaLoaded(): bool { return root.pane.preview.mediaLoaded() }
    function previewText(): string { return root.pane.preview.textShown() }
    function previewMarkdownView(): string { return root.pane.preview.markdownView() }
    // Length is in UTF-16 code units; the sweep's ASCII fixture has the same byte count.
    function previewTextLength(): int { return root.pane.preview.textShown().length }
    // Keep the reply bounded even if a caller asks for the entire file, including zero and negative counts.
    function previewTextTail(n: int): string {
        var count = Math.max(0, Math.min(n, root.textTailLimit))
        return count > 0 ? root.pane.preview.textShown().slice(-count) : ""
    }
    function previewArchiveNames(): string { return root.pane.preview.archiveNames() }
    // The slider centre lets a test wheel over the preview's seek slider without guessing its layout.
    function previewSliderCentre(): string {
        return root.pane.preview.active && root.pane.preview.isMedia ? root.fleaWindow.centreOf(root.pane.preview.seekSlider) : ""
    }
}
