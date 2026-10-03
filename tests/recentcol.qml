import QtQuick
import "flea" as Flea

// Sidebar040: inspect the actual Header and Row items, including the lazy path split.
Item {
    id: root
    readonly property int paneWidth: 800
    readonly property int locationWidth: 150
    readonly property int belowFloor: 1
    readonly property real nameFloor: 2 * Flea.Theme.spacing.rowPaddingX + Flea.Theme.iconSize + Flea.Theme.spacing.gap + Flea.Theme.column.nameMin
    readonly property real locationFloor: root.nameFloor + Flea.Theme.column.size + Flea.Theme.column.date + root.locationWidth + 3 * Flea.Theme.spacing.gap
    readonly property var file: ({n: "Documents/a-very-long-parent-directory/another-long-parent-directory/notes.txt", p: 33188, d: false, s: 18000, m: 1758835200})
    readonly property var longFile: Object.assign({}, root.file, {n: "Documents/a-very-long-parent-directory/another-long-parent-directory/a-very-long-filename-that-must-use-the-whole-name-column-and-keep-its-extension.txt"})

    Flea.Header { id: header; width: root.paneWidth; recent: true; hiddenCols: []; sortBy: "mtime"; sortDesc: true }
    Flea.Row { id: recent; width: header.contentWidth; row: root.file; recenting: true; hiddenCols: [] }
    Flea.Row { id: longRecent; width: recent.width; row: root.longFile; recenting: true; hiddenCols: [] }
    Flea.Header { id: floorHeader; width: root.locationFloor + Flea.Theme.spacing.rowPaddingX; recent: true; hiddenCols: [] }
    Flea.Row { id: floorRow; width: floorHeader.contentWidth; row: root.file; recenting: true; hiddenCols: [] }
    Flea.Header { id: narrowHeader; width: root.locationFloor - root.belowFloor + Flea.Theme.spacing.rowPaddingX; recent: true; hiddenCols: [] }
    Flea.Row { id: narrow; width: narrowHeader.contentWidth; row: root.file; recenting: true; hiddenCols: [] }
    Flea.Row { id: search; width: recent.width; row: root.file; searchQuery: "notes"; hiddenCols: [] }
    Flea.Row { id: plain; width: recent.width; row: root.file; hiddenCols: [] }

    // Find drawn text by value and type, without relying on a new production seam.
    function texts(row, walk) {
        var out = {name: null, location: null}
        walk(row, function (o) {
            if (String(o).indexOf("MatchText") === 0 && o.visible && o.text === row.decoratedName) out.name = o
            if (o.elide !== undefined && o.text === row.locationText && row.locationText.length > 0) out.location = o
        })
        return out
    }

    function run(check, walk) {
        var r = root.texts(recent, walk)
        var l = root.texts(longRecent, walk)
        var s = root.texts(search, walk)
        var n = root.texts(narrow, walk)
        var h = header.cell("location")
        check("Recent titles match Sidebar040", header.titles(), "Name|Location|Size|Used")
        check("Recent header names its drawn columns", header.columnSet(), "name,location,size,date")
        check("Recent row names its drawn columns", recent.columnSet(), header.columnSet())
        check("Recent exposes its Location header", h !== null, true)
        check("Recent builds its name and location", r.name !== null && r.location !== null, true)
        if (r.name && r.location) {
            var locationX = r.location.mapToItem(recent, 0, 0).x
            check("Location header and row share the exact left edge", h ? h.x : -1, locationX)
            check("Recent location has the board's fixed width", r.location.width, root.locationWidth)
            check("Recent location head elides", r.location.elide, Text.ElideLeft)
            check("Recent location is long enough to elide", r.location.truncated, true)
            check("Recent location is left aligned", r.location.horizontalAlignment, Text.AlignLeft)
            check("Recent location uses caption type", r.location.font.pixelSize, Flea.Theme.font.caption)
            check("Recent location uses row metadata ink", String(r.location.color), String(recent.cellInk))
            check("Recent name fills its own column", r.name.width, r.location.x - Flea.Theme.spacing.gap)
            check("Recent location ends before Size", locationX + r.location.width + Flea.Theme.spacing.gap, recent.cell("size").x)
            check("Recent short name no longer shrinks its slot", r.name.width > r.name.implicitWidth, true)
        }
        if (h) {
            check("Location header uses fixed width", h.width, root.locationWidth)
            check("Location header is left aligned", h.horizontalAlignment, Text.AlignLeft)
            check("Location header shares title ink", String(h.color), String(header.cell("name").color))
            check("Location header shares title weight", h.font.weight, header.cell("name").font.weight)
            var handlers = 0
            walk(h, function (o) { if (String(o).indexOf("QQuickTapHandler") === 0) handlers += 1 })
            check("Location header has no click handler", handlers, 0)
        }
        check("Used alone has the descending arrow", header.cell("date").text, "Used ▾")
        if (r.location && l.location) {
            check("Location never follows name length", l.location.mapToItem(longRecent, 0, 0).x, r.location.mapToItem(recent, 0, 0).x)
            check("Recent long name keeps the entire name slot", l.name.width, r.name.width)
        }
        check("Location draws exactly at its name floor", floorHeader.columnSet(), "name,location,size,date")
        check("Row keeps Location at the exact floor", floorRow.columnSet(), floorHeader.columnSet())
        check("Location drops below its name floor", narrowHeader.columnSet().indexOf("location"), -1)
        check("Narrow Recent header and row agree", narrow.columnSet(), narrowHeader.columnSet())
        check("Narrow Recent titles omit Location", narrowHeader.titles(), "Name|Size|Used")
        check("Narrow Recent draws no location", n.location ? n.location.visible && n.location.width > 0 : false, false)
        if (n.name) check("Narrow Recent name fills the available slot", n.name.width, narrow.cell("size").x - n.name.mapToItem(narrow, 0, 0).x - Flea.Theme.spacing.gap)
        check("Search builds both path texts", s.name !== null && s.location !== null, true)
        if (s.name && s.location) {
            check("Search keeps its inline name share", s.name.width, Math.min(s.name.implicitWidth, search.searchSlot * search.nameShare))
            check("Search location follows its name", s.location.x, s.name.width + Flea.Theme.spacing.gap)
            check("Search location keeps head elision", s.location.elide, Text.ElideLeft)
        }
        check("Ordinary row builds no location text", root.texts(plain, walk).location, null)
        console.log("RECENTCOL floor=" + root.locationFloor + " row-width; pane-floor=" + (root.locationFloor + Flea.Theme.spacing.rowPaddingX))
    }
}
