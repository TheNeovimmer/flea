import QtQuick
import "." as Flea

// Quick Look and its shared PDF readers report the surfaces already built by the pane.
QtObject {
    id: root

    property var fleaWindow: null
    property var pane: null
    readonly property var columns: root.pane ? root.pane.columnsArea : null
    readonly property int textTailLimit: 4096
    // Quick Look is built by its first open, so until then every reader answers the closed overlay's own values.
    readonly property var look: root.pane && root.pane.preview ? root.pane.preview : root.idle
    readonly property var idle: QtObject {
        readonly property bool active: false
        readonly property bool visible: false
        readonly property bool isImage: false
        readonly property bool isMedia: false
        readonly property bool stripVisible: false
        readonly property bool muted: Flea.MediaSound.muted
        readonly property string kind: ""
        readonly property string status: ""
        readonly property int position: 0
        readonly property int duration: 0
        readonly property var muteMark: null
        readonly property var seekSlider: null
        readonly property var pdfItem: null
        readonly property var markdownItem: null
        function swapState() {
            return { holding: false, capturing: false, fellBack: false, holds: 0, fallbacks: 0,
                     bursts: 0, heldFrames: 0, midFrames: 0, loadingFrames: 0, last: { ms: 0, end: "" } }
        }
        function surfaceItem() { return null }
        function mediaLoaded() { return false }
        function textShown() { return "" }
        function markdownView() { return "" }
        function markdownCloseState() { return "{}" }
        function markdownEndGap() { return -1 }
        function markdownScrollY() { return -1 }
        function archiveNames() { return "" }
    }

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
    function previewOpen(): bool { return root.look.active }
    // Read the column's mounted Markdown view, empty until its document is ready.
    function columnMarkdownView(): string {
        var column = root.lookColumnItem
        var markdown = column ? column.markdown : null
        return column && column.visible && markdown && markdown.active && markdown.contentReady ? markdown.view : ""
    }
    function previewKind(): string { return root.look.kind }
    function previewState(): string { return root.look.status }
    // One entry per figure block; "" while no Markdown body is mounted, so a case keeps polling.
    function previewFigures(): string {
        var m = root.look.markdownItem
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
    function previewPosition(): int { return root.look.position }
    function previewDuration(): int { return root.look.duration }
    // Fix round 1: what the strip actually draws, not a re-derived guess at its visible: expression.
    function previewStrip(): string { return JSON.stringify({ visible: root.look.stripVisible, muted: root.look.muted, mute: root.fleaWindow.centreOf(root.look.muteMark) }) }
    // "" means no PDF is loaded, rather than zoom 1 or expanded false.
    function previewPdfPage(): int { var p = root.look.pdfItem; return p ? p.page : -1 }
    function previewPdfZoom(): string { var p = root.look.pdfItem; return p ? String(p.zoom) : "" }
    function previewPdfFocus(): int { var p = root.look.pdfItem; return p ? p.pdfControlIndex : -1 }
    function pdfState(overlay: bool): string {
        var p = overlay ? root.look.pdfItem : root.lookColumnItem
        if (!p) return "null"
        return JSON.stringify({ page: overlay ? p.page : p.pdfPage(), pages: overlay ? p.pageCount : p.pdfPages,
            frame: overlay ? "" : root.fleaWindow.rectOf(p.pdfFrameItem),
            toolbar: overlay ? "" : root.fleaWindow.rectOf(p.pdfToolbarItem),
            zoom: overlay ? p.zoom : p.pdfZoom, scrollY: p.pdfScrollY, focused: p.activeFocus, control: p.pdfControlIndex,
            controls: p.pdfControls.map(function (control) { return { name: control.accessName, enabled: control.enabled,
                visible: control.visible, centre: root.fleaWindow.centreOf(control) } }) })
    }
    function previewExpanded(): string { var p = root.look.pdfItem; return p ? String(p.expanded) : "" }
    function previewSwapState(): string { return JSON.stringify({ column: root.columns ? root.columns.swapState() : null, look: root.look.swapState(), lookVisible: root.look.visible }) }
    function previewSurfaceRect(): string { return root.fleaWindow.rectOf(root.look.surfaceItem()) }
    function previewPictureRect(): string { var p = root.look; if (!p) return ""; if (p.isImage) { var im = p.surfaceItem(); return im ? root.fleaWindow.rectOf(im.pictureItem) : "" } if (p.isMedia) { var me = p.surfaceItem(); return me ? root.fleaWindow.rectOf(me.contentItem) : "" } return "" }
    function previewMediaLoaded(): bool { return root.look.mediaLoaded() }
    function previewText(): string { return root.look.textShown() }
    function previewMarkdownView(): string { return root.look.markdownView() }
    function previewCloseState(): string { return root.look.markdownCloseState() }
    function previewEndGap(): int { return root.look.markdownEndGap() }
    function previewScrollY(): int { return root.look.markdownScrollY() }
    // Length is in UTF-16 code units; the sweep's ASCII fixture has the same byte count.
    function previewTextLength(): int { return root.look.textShown().length }
    // Keep the reply bounded even if a caller asks for the entire file, including zero and negative counts.
    function previewTextTail(n: int): string {
        var count = Math.max(0, Math.min(n, root.textTailLimit))
        return count > 0 ? root.look.textShown().slice(-count) : ""
    }
    function previewArchiveNames(): string { return root.look.archiveNames() }
    // The slider centre lets a test wheel over the preview's seek slider without guessing its layout.
    function previewSliderCentre(): string {
        return root.look.active && root.look.isMedia ? root.fleaWindow.centreOf(root.look.seekSlider) : ""
    }
}
