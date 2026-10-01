.import "tabsfixture.js" as Fixture
.import "../../ui/js/Tabs.js" as Tabs

function run(check) {
    // A search sets pane.path to the scope it walks and keeps the origin in searchFrom, which
    // dropOverlay clears. openNew is driven whole rather than restingPath alone, because the defect
    // was the ORDER of those two and a test on restingPath by itself passes either way.
    var searching = Fixture.pane("/")
    searching.searchMode = "results"
    searching.searchFrom = "/home/gm/Work"
    Tabs.openNew(searching)
    check("a tab opened from search results remembers where the user was, not the scope",
          searching.tabs.items[1].path, "/home/gm/Work")
    check("and so does the tab it was opened from", searching.tabs.items[0].path, "/home/gm/Work")
    check("and the search is dropped once the paths are taken", searching.searchMode, "")
    check("and the pane lands on the path the tab records", searching.path, "/home/gm/Work")
    check("carrying no cursor from the search's own listing", searching.tabs.items[1].cursorIndex, 0)
    check("and no selection from it either", searching.tabs.items[1].selected.length, 0)

    var plain = Fixture.pane("/tmp/here")
    Tabs.openNew(plain)
    check("an ordinary listing opens its tab on its own path", plain.tabs.items[1].path, "/tmp/here")

    // The cursor is clamped when a listing arrives and the selection was not, so a row past the end
    // of a directory that shrank while the tab was hidden was selected anyway.
    var shrunk = { total: 3, selectionVersion: 0, toggled: [], clearSelection: function () {} }
    shrunk.selection = { toggle: function (i) { shrunk.toggled.push(i) } }
    Tabs.restoreSelection(shrunk, [0, 2, 7, 40])
    check("a selection restored into a shrunken directory keeps only rows that still exist",
          shrunk.toggled.join(","), "0,2")
    var none = { total: 0, selectionVersion: 5, toggled: [], clearSelection: function () {} }
    none.selection = { toggle: function (i) { none.toggled.push(i) } }
    Tabs.restoreSelection(none, [1, 2])
    check("and a restore that kept nothing does not announce a selection change",
          none.toggled.length + "|" + none.selectionVersion, "0|5")

    // The clamp alone was not enough: a row deleted BELOW a kept index leaves that index in range
    // and naming a different file, which trash would then act on. A switch that re-lists carries no
    // selection at all now, and the re-list's own reset is what clears it.
    var moved = Fixture.pane("/tmp/a")
    moved.tabs = { items: [{ path: "/tmp/a" }, { path: "/tmp/b", history: [], cursorIndex: 1,
                            viewMode: "list", showHidden: false, selected: [0, 1, 2],
                            sortBy: "name", sortDesc: false }],
                   index: 0, pendingCursor: -1, pendingSortBy: "", pendingSortDesc: false }
    Tabs.selectAt(moved, 1)
    check("a switch that re-lists asks for no selection to be restored",
          moved.tabs.pendingSelected === undefined, true)
    check("and it did re-list, which is what clears the selection", moved.listed.join(","), "/tmp/b")

    // F3 and F4: a refusal and a background close must each cost the user nothing else.
    var full = Fixture.pane("/tmp/full")
    var nine = []
    for (var t = 0; t < 9; t++) nine.push({ path: "/tmp/" + t })
    full.tabs = { items: nine, index: 0, pendingCursor: -1, pendingSelected: null,
                  pendingSortBy: "", pendingSortDesc: false }
    full.preview.active = true
    full.searchMode = "results"
    full.searchRunning = true
    Tabs.openNew(full)
    check("a refused tenth tab says so", full.said[full.said.length - 1], "Nine tabs is the most.")
    check("and leaves the preview open", full.preview.active, true)
    check("and does not cancel the running search", full.searchRunning, true)
    check("and the search itself is still standing", full.searchMode, "results")

    // selectAt got the same read-before-dropOverlay hoist, and nothing drove it from a search.
    var leaving = Fixture.pane("/")
    leaving.searchMode = "results"
    leaving.searchFrom = "/home/gm/Work"
    var other = { path: "/tmp/other", history: [], cursorIndex: 0, viewMode: "list",
                  showHidden: false, selected: [], sortBy: "name", sortDesc: false }
    leaving.tabs = { items: [other, { path: "/" }], index: 1,
                     pendingCursor: -1, pendingSortBy: "", pendingSortDesc: false }
    Tabs.selectAt(leaving, 0)
    check("the tab left behind during a search records where the user was",
          leaving.tabs.items[1].path, "/home/gm/Work")

    var many = Fixture.pane("/tmp/one")
    many.tabs = { items: [{ path: "/tmp/one" }, { path: "/tmp/two" }, { path: "/tmp/three" }],
                  index: 0, pendingCursor: -1, pendingSelected: null,
                  pendingSortBy: "", pendingSortDesc: false }
    many.preview.active = true
    Tabs.closeAt(many, 2)
    check("closing a background tab leaves the current tab's preview alone", many.preview.active, true)
    check("and still removes it", Tabs.count(many), 2)

    // The strip's binding reads these four by name rather than through the pane, so a comma
    // expression is not needed to make a label re-read when a tab opens; qmllint flagged that.
    var items = [{ path: "/home/gm" }, { path: "/tmp/one" }]
    check("the current tab draws the pane's live path, not its snapshot",
          Tabs.pathAt({ items: items, index: 1 }, 1, 1, "/tmp/moved"), "/tmp/moved")
    check("a hidden tab draws its own snapshot",
          Tabs.pathAt({ items: items, index: 1 }, 1, 0, "/tmp/moved"), "/home/gm")
    check("no tabs at all still answers a string",
          Tabs.pathAt(null, 0, 3, "/home/gm"), "")

    check("a root tab is labelled with its separator", Tabs.label("/", ""), "/")
    check("the home directory uses the rail's own Home label", Tabs.label("/home/gm", "/home/gm"), "Home")
    check("a home child is labelled with its leaf, not the tilde form",
          Tabs.label("/home/gm/Work", "/home/gm"), "Work")
    check("one pane with no tab state still counts as one tab", Tabs.count(Fixture.pane()), 1)

    var born = Fixture.pane()
    Tabs.act("tabNew", born)
    check("t seeds the current folder and opens a second tab on it", Tabs.count(born), 2)
    check("and lands on the new tab", Tabs.currentIndex(born), 1)
    check("and does not re-list, because both tabs name the same directory", born.listed.length, 0)

    born.path = "/home/gm/Downloads"
    check("a navigate updates the current tab's label without a switch",
          Tabs.labelAt(born, 1), "Downloads")
    check("and leaves the other tab's snapshot alone", Tabs.labelAt(born, 0), "Work")

    Tabs.act("tab1", born)
    check("1 switches to the first tab", Tabs.currentIndex(born), 0)
    check("and lists the snapshot path, because it is a different directory",
          born.listed.join(","), "/home/gm/Work")
    check("and keeps the cursor to restore after rows arrive", born.tabs.pendingCursor, 4)

    Tabs.applyPending(born)
    check("the pending cursor lands once rows arrive", born.cursorIndex, 4)

    var cycling = Fixture.pane("/tmp/first")
    Tabs.openNew(cycling)
    cycling.path = "/tmp/second"
    cycling.cursorIndex = 7
    cycling.viewMode = "grid"
    cycling.showHidden = true
    cycling.backend.sortBy = "size"
    cycling.backend.sortDesc = true
    Tabs.act("tabNext", cycling)
    check("next wraps from the last tab to the first", Tabs.currentIndex(cycling), 0)
    check("next opens the first tab's directory", cycling.path, "/tmp/first")
    check("the tab left behind retains its live cursor, view and hidden preference",
          cycling.tabs.items[1].cursorIndex + "|" + cycling.tabs.items[1].viewMode + "|" + cycling.tabs.items[1].showHidden,
          "7|grid|true")
    Tabs.applyPending(cycling)
    Tabs.applyPending(cycling)
    check("next restores the target cursor and sorting after its listing arrives",
          cycling.cursorIndex + "|" + cycling.backend.sortBy + "|" + cycling.backend.sortDesc, "4|name|false")
    Tabs.act("tabPrevious", cycling)
    check("previous wraps from the first tab to the last", Tabs.currentIndex(cycling), 1)
    check("previous restores the second tab's directory, view and hidden preference",
          cycling.path + "|" + cycling.viewMode + "|" + cycling.showHidden, "/tmp/second|grid|true")
    Tabs.applyPending(cycling)
    Tabs.applyPending(cycling)
    check("previous restores the second tab's cursor and sorting",
          cycling.cursorIndex + "|" + cycling.backend.sortBy + "|" + cycling.backend.sortDesc, "7|size|true")
    Tabs.act("tabPrevious", cycling)
    check("previous steps backward before wrapping", Tabs.currentIndex(cycling), 0)
    Tabs.act("tabNext", cycling)
    check("next steps forward before wrapping", Tabs.currentIndex(cycling), 1)
    cycling.listInFlight = true
    var heldTabs = cycling.tabs
    Tabs.act("tabPrevious", cycling)
    Tabs.act("tabNext", cycling)
    check("both cycle directions retain tab ownership while a listing is loading", cycling.tabs === heldTabs, true)
    check("both loading refusals explain why the key did not switch",
          cycling.said.join("|"), "A directory is already loading.|A directory is already loading.")

    var single = Fixture.pane("/tmp/only")
    single.preview.active = true
    single.filterQuery = "keep"
    single.selection.toggle(2)
    Tabs.act("tabNext", single)
    Tabs.act("tabPrevious", single)
    check("cycling the only tab does not create tab state or relist", single.tabs === null && single.listed.length === 0, true)
    check("cycling the only tab preserves its preview, filter, cursor and selection",
          single.preview.active + "|" + single.filterQuery + "|" + single.cursorIndex + "|" + single.selectedIndices().join(","),
          "true|keep|4|2")

    var missing = Fixture.pane()
    Tabs.act("tab3", missing)
    check("a digit with no such tab says so in words", missing.said.join(""), "No tab 3.")

    var last = Fixture.pane()
    Tabs.act("tabClose", last)
    check("w on the only tab refuses rather than closing the window",
          last.said.join(""), "Can't close the last tab.")

    var pair = Fixture.pane("/home/gm/a")
    Tabs.act("tabNew", pair)
    pair.path = "/home/gm/b"
    Tabs.act("tabClose", pair)
    check("w on a second tab leaves one", Tabs.count(pair), 1)
    check("and lists the tab that remains", pair.listed.join(","), "/home/gm/a")

    var capped = Fixture.pane()
    var n
    for (n = 0; n < 12; n++)
        Tabs.act("tabNew", capped)
    check("the ninth tab is the last one t will open", Tabs.count(capped), 9)
    check("and the tenth says so", capped.said[capped.said.length - 1], "Nine tabs is the most.")

    var loading = Fixture.pane()
    loading.listInFlight = true
    Tabs.act("tabNew", loading)
    check("t while a listing is in flight uses the same sentence navigation does",
          loading.said.join(""), "A directory is already loading.")

    var previewing = Fixture.pane()
    previewing.preview.active = true
    Tabs.act("tabNew", previewing)
    check("t closes an open preview, so the new tab is not sitting under one",
          previewing.preview.closed, 1)

    var pending = Fixture.pane("/home/gm/a")
    pending.tabs = {
        items: [],
        index: 0,
        pendingCursor: 9,
        pendingSelected: null,
        pendingSortBy: "size",
        pendingSortDesc: true
    }
    Tabs.applyPending(pending)
    check("a pending size order is asked for before the cursor is restored",
          pending.sorted.join(",") + "|" + pending.cursorIndex, "size:true|4")
    Tabs.applyPending(pending)
    check("the next rows reply restores the cursor", pending.cursorIndex, 9)

    // nt1: Ctrl+Return opens the cursor folder in a new tab, the keyboard twin of the middle click.
    var folder = Fixture.pane("/tmp/base")
    folder.cursorIndex = 2
    folder.selection.toggle(1)
    folder.rowFor = function (i) { return i === 2 ? { n: "sub", d: true } : null }
    Tabs.openCursorTab(folder)
    check("a directory opens a tab on that folder", folder.tabs.items[1].path, "/tmp/base/sub")
    check("and the new tab is shown", Tabs.currentIndex(folder), 1)
    check("and the tab left behind keeps its cursor", folder.tabs.items[0].cursorIndex, 2)
    check("and keeps its selection", folder.tabs.items[0].selected.join(","), "1")
    var filePane = Fixture.pane("/tmp/base")
    filePane.cursorIndex = 2
    filePane.selection.toggle(1)
    filePane.rowFor = function () { return { n: "a.txt", d: false } }
    Tabs.openCursorTab(filePane)
    check("a file opens no tab", Tabs.count(filePane), 1)
    check("and says only a folder does", filePane.said[filePane.said.length - 1], "Only a folder opens in a new tab.")
    check("and leaves the cursor where it was", filePane.cursorIndex, 2)
    check("and leaves the selection alone", filePane.selectedIndices().join(","), "1")
    var emptyPane = Fixture.pane("/tmp/base")
    emptyPane.cursorIndex = 2
    emptyPane.rowFor = function () { return null }
    Tabs.openCursorTab(emptyPane)
    check("no cursor row opens no tab either", Tabs.count(emptyPane), 1)
    check("and says the same sentence", emptyPane.said[emptyPane.said.length - 1], "Only a folder opens in a new tab.")

    // xw6: a tab dragged past its window's edge leaves as a platform drag carrying the
    // folder, the view and the cursor file name, plus the folder alone for another app.
    var tabbed = Fixture.pane("/tmp/a")
    tabbed.tabs = { items: [{ path: "/tmp/a" }, { path: "/tmp/b", history: [], cursorIndex: 2,
                            viewMode: "grid", showHidden: false, selected: [],
                            sortBy: "name", sortDesc: false }],
                   index: 0, pendingCursor: -1, pendingSortBy: "", pendingSortDesc: false }
    tabbed.rowFor = function (i) { return i === 4 ? { n: "note.txt", d: false } : null }
    var info = Tabs.parseTabMime(Tabs.tabPayload(tabbed, 0))
    check("a tab encodes its folder, view and cursor file",
          info.path + "|" + info.view + "|" + info.cursor, "/tmp/a|list|note.txt")
    var hiddenInfo = Tabs.parseTabMime(Tabs.tabPayload(tabbed, 1))
    check("a hidden tab encodes its own snapshot", hiddenInfo.path + "|" + hiddenInfo.view, "/tmp/b|grid")
    var lift = Tabs.tabDragMime(tabbed, 0)
    check("the lift offers the tab MIME", lift[Tabs.TAB_MIME] === Tabs.tabPayload(tabbed, 0), true)
    check("and the folder as uri-list for another app", lift["text/uri-list"], "file:///tmp/a\r\n")
    check("and as plain text", lift["text/plain"], "/tmp/a")
    check("no such tab offers no payload", Tabs.tabPayload(tabbed, 7), "")
    check("and no MIME at all", Tabs.tabDragMime(tabbed, 7)["text/uri-list"], undefined)
    check("this window's own drag is never a receive", Tabs.isOwnTab(info), true)
    check("another window's is", Tabs.isOwnTab(Tabs.parseTabMime(
        JSON.stringify(["other-instance", "/tmp/a", "list", ""]))), false)
    check("garbage refuses", Tabs.parseTabMime("not json"), null)
    check("an empty payload refuses", Tabs.parseTabMime(""), null)
    check("a relative path refuses",
          Tabs.parseTabMime(JSON.stringify(["i", "tmp/a", "list", ""])), null)
    check("a control character refuses",
          Tabs.parseTabMime(JSON.stringify(["i", "/tmp/ab", "list", ""])), null)
    check("a wrong arity refuses", Tabs.parseTabMime(JSON.stringify(["i", "/tmp/a"])), null)

    // The strip answers an insertion point; off the strip the tab lands at the end.
    check("a drop past the last tab lands at the end", Tabs.dropIndexAt(9999, 100, 3), 3)
    check("a drop before the first lands at zero", Tabs.dropIndexAt(-50, 100, 3), 0)
    check("a drop over the second tab names its near edge", Tabs.dropIndexAt(140, 100, 3), 1)

    // A tab from another window opens at the drop position and is shown.
    var receiver = Fixture.pane("/tmp/r")
    var foreign = JSON.stringify(["other-instance", "/tmp/folder", "grid", "note.txt"])
    check("a foreign tab opens", Tabs.receiveTab(receiver, foreign, 1), true)
    check("at the drop position and shown",
          Tabs.currentIndex(receiver) + "|" + Tabs.count(receiver), "1|2")
    check("on the folder it names", receiver.path, "/tmp/folder")
    check("in the view it names", receiver.viewMode, "grid")
    check("carrying the cursor name", receiver.tabs.items[1].cursorName, "note.txt")
    var plainView = Fixture.pane("/tmp/r")
    Tabs.receiveTab(plainView, JSON.stringify(["other-instance", "/tmp/g", "britelite", ""]), -1)
    check("an unknown view keeps the standing one", plainView.viewMode, "list")
    check("and off the strip lands at the end", Tabs.currentIndex(plainView), 1)
    var own = Fixture.pane("/tmp/r")
    Tabs.receiveTab(own, Tabs.tabPayload(tabbed, 0), 0)
    check("this window's own drag never receives", Tabs.count(own), 1)
    var busyReceiver = Fixture.pane("/tmp/r")
    busyReceiver.listInFlight = true
    check("a loading window refuses the drop", Tabs.receiveTab(busyReceiver, foreign, 0), false)
    check("with navigation's own sentence",
          busyReceiver.said[busyReceiver.said.length - 1], "A directory is already loading.")
    var fullReceiver = Fixture.pane("/tmp/r")
    var nineFull = []
    for (var f = 0; f < 9; f++) nineFull.push({ path: "/tmp/" + f })
    fullReceiver.tabs = { items: nineFull, index: 0, pendingCursor: -1,
                          pendingSortBy: "", pendingSortDesc: false }
    check("a full strip refuses the drop", Tabs.receiveTab(fullReceiver, foreign, 0), false)
    check("with the cap's own sentence",
          fullReceiver.said[fullReceiver.said.length - 1], "Nine tabs is the most.")

    // After an accepted drop the source closes the tab that left.
    var moved = Fixture.pane("/tmp/one")
    moved.tabs = { items: [{ path: "/tmp/one" }, { path: "/tmp/two", history: [], cursorIndex: 0,
                           viewMode: "list", showHidden: false, selected: [],
                           sortBy: "name", sortDesc: false }],
                   index: 0, pendingCursor: -1, pendingSortBy: "", pendingSortDesc: false }
    check("a moved tab closes", Tabs.closeTabAfterMove(moved, 1), "closed")
    check("and is gone", Tabs.count(moved), 1)
    var only = Fixture.pane("/tmp/only")
    check("the last tab closes the window instead", Tabs.closeTabAfterMove(only, 0), "window")
    check("and stands until the drop answers", Tabs.count(only), 1)
    var kept = Fixture.pane("/tmp/one")
    kept.listInFlight = true
    check("a loading source keeps its tab", Tabs.closeTabAfterMove(kept, 0), "kept")
    check("no such tab keeps everything", Tabs.closeTabAfterMove(moved, 5), "kept")

    // The close resolves by folder when a key pressed mid-drag shifted every index.
    var shifted = Fixture.pane("/tmp/one")
    shifted.tabs = { items: [{ path: "/tmp/one" }, { path: "/tmp/two", history: [], cursorIndex: 0,
                             viewMode: "list", showHidden: false, selected: [],
                             sortBy: "name", sortDesc: false },
                             { path: "/tmp/three", history: [], cursorIndex: 0,
                             viewMode: "list", showHidden: false, selected: [],
                             sortBy: "name", sortDesc: false }],
                     index: 0, pendingCursor: -1, pendingSortBy: "", pendingSortDesc: false }
    check("the lift's index closes while it still names the folder",
          Tabs.resolveMovedTab(shifted, 1, "/tmp/two"), 1)
    check("a shifted index follows the folder, not the number",
          Tabs.resolveMovedTab(shifted, 0, "/tmp/two"), 1)
    check("a folder no tab names keeps every tab", Tabs.resolveMovedTab(shifted, 1, "/tmp/gone"), -1)
    check("and nothing resolves off no pane", Tabs.resolveMovedTab(null, 0, "/tmp/two"), -1)

    // A lift may not leave while a rename is open, or the close would take the editor's tab.
    check("a clean pane tears out", Tabs.tearRefusal(Fixture.pane()), "")
    var renaming = Fixture.pane()
    renaming.renamePending = true
    check("a pending rename refuses the drag",
          Tabs.tearRefusal(renaming), "Finish the rename before dragging a tab out.")
    var editing = Fixture.pane()
    editing.renameEditor = function () { return {} }
    check("a live editor refuses too",
          Tabs.tearRefusal(editing), "Finish the rename before dragging a tab out.")
    var loadingPane = Fixture.pane()
    loadingPane.listInFlight = true
    check("a loading listing refuses", Tabs.tearRefusal(loadingPane), "A directory is already loading.")
    check("a strip with room receives", Tabs.canReceive(Fixture.pane()), true)
    check("a loading strip does not", Tabs.canReceive(loadingPane), false)
    check("a full strip does not", Tabs.canReceive(fullReceiver), false)
}
