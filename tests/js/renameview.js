.import "../../ui/js/Anchor.js" as Anchor
.import "watch.js" as Fixture

// A rename commit puts the viewport back where it was: the re-list resets the view to its top, so only the anchor's restore can.
var ROW_H = 31
var AREA_H = 619
var FOOTER_H = 27
var TOTAL = 1202
var WINDOW = 350
var CONTEXT_ROWS = 3

function wireSource() {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("../../ui/PaneWire.qml"), false)
    request.send()
    return request.responseText
}

// Sample source: function refreshRename(request, selected, pointer) { ... } ends at the member's indentation.
function refreshRename(source) {
    var match = source.match(/function refreshRename\([^)]*\) \{([\s\S]*?)\n    \}/)
    if (!match)
        throw new Error("PaneWire.refreshRename missing")
    return new Function("root,pane,Anchor,watchSettle,request,selected,pointer", match[1])
}

// The list's scrolling surface and the rows it holds, kept apart from the pane stub so the stub carries only the pane's own members.
function makeView(contentY) {
    var view = { contentY: contentY, originY: 0, height: AREA_H, forceLayout: function () {}, asked: undefined, names: [] }
    view.contentHeight = TOTAL * ROW_H + FOOTER_H
    for (var i = 0; i < TOTAL; i++)
        view.names.push("f" + (1000 + i))
    return view
}

// The window the pane holds, cut from the listing's names the way a rows reply fills it.
function fill(p, from) {
    p.held = from
    p.rows = p.listArea.names.slice(from, from + WINDOW).map(function (name) { return { n: name } })
}

// One list the way ui/List.qml draws it: a reset to the top on a re-list, a contain-style reveal on setCursor, a clamp at the footer's end.
function makeList(start, cursor, contentY) {
    var p = Fixture.watched(start, [], cursor, TOTAL)
    var view = makeView(contentY)
    p.path = "/dir"
    p.viewMode = "list"
    p.searchMode = ""
    p.anchorRowHeight = ROW_H
    p.listArea = view
    p.pendingSelect = ""
    fill(p, start)
    p.refresh = function (select) {
        p.pendingSelect = select
        view.contentY = 0
        fill(p, 0)
    }
    function clamp(y) { return Math.max(0, Math.min(view.contentHeight - AREA_H, y)) }
    p.setCursor = function (index, context) {
        p.cursorIndex = index
        var top = index * ROW_H
        var low = context === 0 ? 0 : CONTEXT_ROWS * ROW_H
        if (top < view.contentY + low) view.contentY = clamp(top - low)
        else if (top + ROW_H > view.contentY + AREA_H - low) view.contentY = clamp(top + ROW_H + low - AREA_H)
    }
    p.selectOnly = function (index, context) { p.setCursor(index, context) }
    p.selectionAnchor = 0
    p.backend.window = function (from) { view.asked = from }
    return p
}

// What a rows reply does in ui/PaneSwap.qml: the pending select first, then the anchor, once per window the listing delivers.
function deliver(p, wire) {
    if (p.pendingSelect.length > 0) {
        var target = p.pendingSelect
        p.pendingSelect = ""
        var at = Anchor.matchListed(p, target)
        if (at >= 0) p.setCursor(at, 3)
    }
    wire.anchor = Anchor.apply(p, wire.anchor, ROW_H)
}

function commit(check, label, refresh, spec) {
    var p = makeList(spec.start, spec.cursor, spec.contentY)
    var view = p.listArea
    var wire = { stale: false, anchor: null }
    var before = p.cursorIndex * ROW_H - view.contentY
    var request = { source: "/dir/" + view.names[spec.from], destination: "/dir/" + spec.to, folder: "/dir" }
    view.names[spec.from] = spec.to
    if (spec.sortTo !== undefined) view.names.splice(spec.sortTo, 0, view.names.splice(spec.from, 1)[0])
    refresh(wire, p, Anchor, { stop: function () {} }, request, spec.name, spec.pointer)
    if (view.asked !== undefined) {
        deliver(p, wire)
        fill(p, view.asked)
    }
    deliver(p, wire)
    var after = p.cursorIndex * ROW_H - view.contentY
    check(label + ": the row the commit keeps stays at the same screen y", after, before)
    check(label + ": and the anchor is spent", wire.anchor, null)
    return p
}

function run(check) {
    var refresh = refreshRename(wireSource())
    var last = TOTAL - 1
    var bottom = TOTAL * ROW_H + FOOTER_H - AREA_H
    commit(check, "a deep click-away at the end of the list", refresh,
        { start: 900, cursor: last - 1, contentY: bottom, from: last, to: "f9999", pointer: true, name: "" })
    var pointerAt = commit(check, "a deep click-away", refresh,
        { start: 900, cursor: 1100, contentY: 1090 * ROW_H, from: last, to: "f9999", pointer: true, name: "" })
    check("a deep click-away keeps the click's row as the cursor", pointerAt.cursorIndex, 1100)
    commit(check, "a deep Enter at the end of the list", refresh,
        { start: 900, cursor: last, contentY: bottom, from: last, to: "f1201-new", pointer: false, name: "/dir/f1201-new" })
    commit(check, "an Enter in the middle of the first window", refresh,
        { start: 0, cursor: 300, contentY: 290 * ROW_H, from: 300, to: "f1300-new", pointer: false, name: "/dir/f1300-new" })
    var sorted = commit(check, "an Enter whose row sorts ten rows down", refresh,
        { start: 0, cursor: 300, contentY: 290 * ROW_H, from: 300, to: "f1310-new", sortTo: 310, pointer: false, name: "/dir/f1310-new" })
    check("an Enter that re-sorts the row keeps the cursor on it", sorted.cursorIndex, 310)
    commit(check, "an Enter at the top", refresh,
        { start: 0, cursor: 0, contentY: 0, from: 0, to: "f1000-new", pointer: false, name: "/dir/f1000-new" })
}
