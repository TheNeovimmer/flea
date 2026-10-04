import QtQuick
import "flea" as Flea
import "flea/js/Filter.js" as Filter

// Only the Pane surface List, GridArea, Row, GridTile, RenameField, SelectionBand and FileDrag read; shared by the rename-scroll probes.
QtObject {
    id: pane
    property string mode: "list"
    property int totalRows: 1202
    property string path: "/probe"
    property var listArea: null
    property var rows: []
    property var shown: null
    property int shownTotal: totalRows
    property int total: totalRows
    property int held: 0
    property int cursorIndex: 0
    property int cursorSeq: 0
    property int renamingIndex: -1
    property string renameError: ""
    property var renameRequest: null
    readonly property bool renamePending: renameRequest !== null
    property bool paneFocused: true
    property bool dualMode: false
    property var clipboard: ({ paths: [], moving: false })
    property var thumbState: ({ file: {}, order: [] })
    property var dirSizeState: ({ file: {}, order: [] })
    property var kindNames: []
    property string searchMode: ""
    property string searchQuery: ""
    property string recentMode: ""
    property string filterQuery: ""
    property var selectionBand: null
    property int previewIndex: -1
    property bool storageKnown: true
    property string storageClass: ""
    property bool listInFlight: false
    property string listingState: "ready"
    property int visibleRows: listArea ? Math.ceil(listArea.height / Flea.Theme.fileRowHeight) : 0
    property int cacheRows: 0
    property int firstSettleMs: 70
    property int settleMs: 120
    property int coalesceMs: 16
    property int refetchMargin: 0
    property int buffer: 0
    property int windowSize: 25
    // Asked records the last window request, the held-window proof in the origin probe.
    property var backend: QtObject {
        property int asked: -1
        function peek(path, size, hidden) {}
        function thumb(rows, cacheOnly) {}
        function thumbcancel(rows) {}
        function dirsize(rows) {}
        function dirsizecancel() {}
        function window(start, count) { asked = start }
    }
    property var menu: QtObject {
        function close() {}
        function openBackground(point) {}
    }
    property var sidebar: null
    property var statusBar: null
    // The same reset Pane.qml does on its own renamingIndex change.
    onRenamingIndexChanged: if (renamingIndex < 0) renameError = ""
    function join(base, name) { return String(base) + "/" + String(name) }
    function rowFor(index) {
        if (index < 0 || index >= total) return null
        return { n: index === 0 ? "a-original.md" : "b-existing" + index + ".md", d: false, i: "text-x-generic",
                 p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 }
    }
    function isSelected(index) { return false }
    function commitRename(newName) {}
    function setCursor(index, context) { Filter.setCursor(pane, index, context) }
    // The list and grid branches of Pane.showRow; tests/rename-scroll.sh fails when Pane.qml stops carrying them.
    function showRow(view, context) {
        if (mode === "grid") listArea.positionViewAtIndex(view, GridView.Contain)
        else listArea.showCursor(view, context)
        listArea.restartCoalesce()
    }
    function pressSlowClick() {}
    function cancelSlowClick() {}
    function armSlowClick(index, modifiers, dragging, wasSole) {}
    function slowClickWasSole(index) { return false }
}
