.pragma library

.import "Filter.js" as Filter
.import "Format.js" as Format
.import "RecentMode.js" as RecentMode
.import "Search.js" as Search
.import "Sort.js" as Sort
.import "Startup.js" as Startup
.import "TabMove.js" as TabMove

// Hidden tabs are snapshots, so the pane and backend still own only one listing.
// The nine-tab cap matches TUI's direct digit selection; GUI shortcuts cycle through the same state.

var MAX = 9

// Where a tab snapshotted now should reopen: a search sets pane.path to the scope it walks, so the
// directory the user was in is searchFrom, and every caller reads this BEFORE dropOverlay clears it.
// A history is not a directory, so a pane standing on one records the folder it was opened over.
function restingPath(pane) {
    if (pane.searchMode === "results" && (pane.searchFrom || "").length > 0)
        return pane.searchFrom
    return RecentMode.restingPath(pane) || pane.path
}

function snapshot(pane, path) {
    var where = path === undefined ? restingPath(pane) : path
    // A cursor and a selection read off a search's own listing name nothing in the directory the
    // tab records, so a tab stepping back out of a search starts at its first row with none.
    var elsewhere = where !== pane.path
    return {
        path: where,
        history: pane.history.slice(),
        forwardHistory: (pane.forwardHistory || []).slice(),
        cursorIndex: elsewhere ? 0 : pane.cursorIndex,
        viewMode: pane.viewMode,
        showHidden: pane.showHidden,
        selected: elsewhere ? [] : pane.selectedIndices().slice(),
        // A lone row restores with only(), so a tab switch never re-arms the row a tap left behind.
        follows: elsewhere ? false : pane.selection.follows(),
        sortBy: pane.backend.sortBy,
        sortDesc: pane.backend.sortDesc,
        // Issue 94, nixfred: the counter every list bumps, so a selection only returns to its own rows.
        listRequests: pane.backend.listRequests,
        // The directory's filesystem, so a drop on this tab while another shows decides move against copy.
        dev: elsewhere ? 0 : pane.backend.dirDev
    }
}

function pack(items, index) {
    return {
        items: items,
        index: index,
        pendingCursor: -1,
        pendingSortBy: "",
        pendingSortDesc: false
    }
}

function label(path, home) {
    if (!path || path === "/")
        return "/"
    if (home && path === home)
        return "Home"
    var leaf = Format.leafPart(Format.tilde(path, home || ""))
    return leaf.length > 0 ? leaf : path
}

// The current tab's path lives on the pane, not in the snapshot, so a navigate does not wait for a switch.
function labelAt(pane, i) {
    return label(pathAt(pane.tabs, currentIndex(pane), i, pane.path), pane.home)
}

// The path tab i draws: the live pane path for the current tab, the snapshot's for a hidden one.
// Takes the values rather than the pane so ui/TabBar.qml's binding can read each one by name.
function pathAt(tabs, index, i, currentPath) {
    if (i === index)
        return currentPath
    return tabs && tabs.items && tabs.items[i] ? tabs.items[i].path : ""
}

// The tab's filesystem the same way, 0 when unknown, which ui/js/Drag.js verbFor reads as copy.
function devAt(tabs, index, i, currentDev) {
    if (i === index)
        return currentDev
    return tabs && tabs.items && tabs.items[i] ? Number(tabs.items[i].dev) || 0 : 0
}

function labels(pane) {
    var n = count(pane)
    var out = []
    for (var i = 0; i < n; i++)
        out.push(labelAt(pane, i))
    return out
}

function count(pane) {
    return pane.tabs && pane.tabs.items && pane.tabs.items.length > 0 ? pane.tabs.items.length : 1
}

function currentIndex(pane) {
    return pane.tabs ? pane.tabs.index : 0
}

// Issue 93, nixfred: says whether it dropped a walk's results, which are not the directory's rows.
// One shared step for the search; see ui/js/Search.js leaveWalk.
// A Recent listing is dropped the same way; see ui/js/RecentMode.js dropOverlay.
function dropOverlay(pane) {
    var dropped = pane.searchMode === "results" || RecentMode.dropOverlay(pane)
    Search.leaveWalk(pane)
    Filter.close(pane)
    return dropped
}

function closePreview(pane) {
    if (pane.preview && pane.preview.active)
        pane.preview.close()
}

function busy(pane) {
    if (pane.listInFlight) {
        pane.message("A directory is already loading.", false)
        return true
    }
    return false
}

// Only ever called for a switch that re-listed nothing; the clamp is the belt on top of that, since
// an index past the end would select a row that is not there at all.
function restoreSelection(pane, selected, follows) {
    pane.clearSelection()
    if (!selected || selected.length === 0)
        return
    if (follows === true && selected.length === 1 && selected[0] < pane.total) {
        pane.selection.only(selected[0])
        pane.selectionVersion++
        return
    }
    var kept = 0
    for (var i = 0; i < selected.length; i++) {
        if (selected[i] < pane.total) {
            pane.selection.toggle(selected[i])
            kept++
        }
    }
    if (kept > 0)
        pane.selectionVersion++
}

function apply(pane, item, dropped) {
    // Issue 93: a search dropped onto the scope it walked leaves rows that are not that directory's.
    var same = pane.path === item.path && pane.showHidden === item.showHidden && dropped !== true
    var viewChanged = pane.viewMode !== item.viewMode
    pane.history = item.history.slice()
    pane.forwardHistory = (item.forwardHistory || []).slice()
    pane.viewMode = item.viewMode
    pane.showHidden = item.showHidden
    if (same) {
        if (pane.backend && (pane.backend.sortBy !== item.sortBy || pane.backend.sortDesc !== item.sortDesc)) {
            // Issue 94: the one reset a reorder takes, ui/js/Sort.js's, which this branch half repeated.
            Sort.resort(pane, item.sortBy, item.sortDesc)
            pane.tabs.pendingCursor = item.cursorIndex
            return
        }
        // The switch that re-reads nothing, unless something else did: the watch and a write both list.
        pane.setCursor(item.cursorIndex)
        if (pane.backend && item.listRequests === pane.backend.listRequests) {
            restoreSelection(pane, item.selected, item.follows)
            return
        }
        pane.clearSelection()
        return
    }
    pane.tabs.pendingCursor = item.cursorIndex
    pane.tabs.pendingSortBy = item.sortBy
    pane.tabs.pendingSortDesc = item.sortDesc
    // The tab's own dotfile answer is restored above, so the listing keeps it rather than taking the
    // standing preference. A tab in another view clears at once: these rows were never listed in that view.
    pane.openWithoutHistory(item.path, { keepHidden: true, clearAtOnce: viewChanged })
}

function applyPending(pane) {
    if (!pane.tabs)
        return
    var t = pane.tabs
    // Issue 91, nixfred: spent on the first reply either way, or an order already in force never was.
    if (t.pendingSortBy && t.pendingSortBy.length > 0 && pane.backend) {
        var by = t.pendingSortBy
        var desc = t.pendingSortDesc
        t.pendingSortBy = ""
        if (pane.backend.sortBy !== by || pane.backend.sortDesc !== desc) {
            pane.backend.sort(by, desc)
            pane.backend.sortBy = by
            pane.backend.sortDesc = desc
            pane.backend.window(0, pane.windowSize)
            return
        }
    }
    if (t.pendingCursor >= 0) {
        var last = pane.total > 0 ? pane.total - 1 : 0
        pane.setCursor(Math.min(t.pendingCursor, last))
        t.pendingCursor = -1
    }
}

function currentItems(pane, here) {
    if (pane.tabs && pane.tabs.items && pane.tabs.items.length > 0)
        return pane.tabs.items.slice()
    return [snapshot(pane, here)]
}

// A caller may name where the new tab lands, which is what the Places row menu's own row does;
// without one it is Settings, View, Opening that decides, and that still defaults to this folder.
function openNew(pane, where) {
    if (busy(pane))
        return
    // Before the preview and the search go: a refused tenth tab must cost the user nothing.
    if (count(pane) >= MAX) {
        pane.message("Nine tabs is the most.", false)
        return
    }
    var here = restingPath(pane)
    closePreview(pane)
    var dropped = dropOverlay(pane)
    // Settings > View > Opening decides where the new tab lands; it cloned the current folder before
    // 0.2.1 and that is still the default. The tab the operator leaves keeps the path it was on.
    var target = where || Startup.newTabPath(pane.uiState, here, pane.home)
    var items = currentItems(pane, here)
    var index = currentIndex(pane)
    items[index] = snapshot(pane, here)
    items.push(snapshot(pane, target))
    pane.tabs = pack(items, items.length - 1)
    // dropOverlay clears the search but leaves the pane on the scope it walked and its rows on that
    // walk's results, so a target equal to the scope still has to be listed again. Escape already does.
    if (pane.path !== target || dropped)
        pane.openWithoutHistory(target)
}

// Ctrl+Return on the cursor row, the keyboard twin of Tap.tappedTab's middle
// click: that directory in a new tab, leaving the cursor and selection alone.
function openCursorTab(pane) {
    var row = pane.rowFor ? pane.rowFor(pane.cursorIndex) : null
    if (!row || !row.d || typeof row.n !== "string") {
        pane.message("Only a folder opens in a new tab.", false)
        return
    }
    var base = pane.path
    openNew(pane, base === "/" ? "/" + row.n : base + "/" + row.n)
}

function selectAt(pane, i) {
    if (busy(pane))
        return
    var here = restingPath(pane)
    var items = currentItems(pane, here)
    if (i < 0 || i >= items.length) {
        pane.message("No tab " + (i + 1) + ".", false)
        return
    }
    var index = currentIndex(pane)
    if (i === index)
        return
    closePreview(pane)
    var dropped = dropOverlay(pane)
    items[index] = snapshot(pane, here)
    pane.tabs = pack(items, i)
    apply(pane, items[i], dropped)
}

function closeAt(pane, i) {
    if (busy(pane))
        return
    var items = currentItems(pane)
    if (items.length <= 1) {
        pane.message("Can't close the last tab.", false)
        return
    }
    if (i < 0 || i >= items.length) {
        pane.message("No tab " + (i + 1) + ".", false)
        return
    }
    var index = currentIndex(pane)
    items.splice(i, 1)
    var next = index
    if (i < index)
        next = index - 1
    else if (i === index)
        next = Math.min(i, items.length - 1)
    if (i === index) {
        closePreview(pane)
        var dropped = dropOverlay(pane)
        pane.tabs = pack(items, next)
        apply(pane, items[next], dropped)
    } else {
        pane.tabs = pack(items, next)
    }
}

function move(pane, from, to) {
    var items = currentItems(pane)
    if (items.length < 2)
        return
    var index = currentIndex(pane)
    items[index] = snapshot(pane, restingPath(pane))
    pane.tabs = pack(items, TabMove.reorder(items, from, to, index))
}

// Tabs040 callout 1: the { and } keys move the current tab one place. A reorder
// keeps the strip only: the pane stays on its path and lists nothing.
function moveCurrent(pane, delta) {
    var total = count(pane)
    if (total < 2)
        return
    var from = currentIndex(pane)
    move(pane, from, TabMove.step(from, delta, total))
}

function act(action, pane) {
    if (action === "tabMoveLeft" || action === "tabMoveRight") {
        moveCurrent(pane, action === "tabMoveRight" ? 1 : -1)
        return
    }
    if (action === "tabNext" || action === "tabPrevious") {
        var total = count(pane)
        var direction = action === "tabNext" ? 1 : -1
        selectAt(pane, (currentIndex(pane) + total + direction) % total)
        return
    }
    if (action === "tabNew") {
        openNew(pane)
        return
    }
    if (action === "tabClose") {
        closeAt(pane, currentIndex(pane))
        return
    }
    if (action.length === 4 && action.indexOf("tab") === 0 && action.charAt(3) >= "1" && action.charAt(3) <= "9")
        selectAt(pane, parseInt(action.charAt(3), 10) - 1)
}

// Tabs040 callout 2: with "Flea opens in" on Last folder the window reopens every tab in
// order. remembered() runs where lastPath is written and carries no new trigger; restorePlan()
// is the pure startup decision tests/js/tabrestore.js drives; restoreItems() shapes the plan
// into snapshots apply() can switch to. A folder that no longer exists is kept, because nothing
// here can stat a path: the listing's own error names it, the way startPath leaves a missing
// lastPath to that same error.
function remembered(pane) {
    var here = restingPath(pane)
    var items = pane.tabs && pane.tabs.items && pane.tabs.items.length > 0 ? pane.tabs.items : null
    if (!items)
        return { paths: [here], index: 0 }
    var index = currentIndex(pane)
    var out = []
    for (var i = 0; i < items.length; i++)
        out.push(i === index ? here : String((items[i] || {}).path || ""))
    return { paths: out, index: index }
}

// Null unless Last folder holds a remembered strip: Home and Chosen folder start exactly as
// startPath answers, a named path outranks the strip, and an old file without the key, an
// empty strip or one with nothing usable falls back to that same startPath answer.
function restorePlan(state, argvPath) {
    if (argvPath && String(argvPath).length > 0)
        return null
    var data = state || {}
    if ((data.startIn || "home") !== "last")
        return null
    var stored = data.lastTabs || null
    var kept = stored && Array.isArray(stored.paths) ? stored.paths : []
    var paths = []
    for (var i = 0; i < kept.length && paths.length < MAX; i++) {
        if (typeof kept[i] === "string" && kept[i].length > 0)
            paths.push(kept[i])
    }
    if (paths.length === 0)
        return null
    var index = stored && stored.index === Math.floor(stored.index) ? stored.index : 0
    if (index < 0 || index >= paths.length)
        index = Math.min(Math.max(index, 0), paths.length - 1)
    return { paths: paths, index: index }
}

// A restored tab starts exactly like a tab opened fresh at that folder: snapshot() is what
// openNew() records for its own new tab, so the standing view, sort and hidden preference all
// come from the pane rather than from literals here.
function restoreItems(pane, paths) {
    var out = []
    for (var i = 0; i < paths.length; i++)
        out.push(snapshot(pane, String(paths[i])))
    return out
}

// xw6: a tab dragged past its window's edge becomes a platform drag carrying only
// Flea's private tab type. The payload is a JSON array, [pid, token, path, view,
// cursor]: pid names the source process the taken ack returns to, token names the
// lift the ack closes, path is the folder the tab stands on, view its mode, cursor
// the cursor row's file name. A folder path may itself hold a newline, so a line
// format could not carry it. No text/uri-list, no text/plain: a foreign app refuses
// the private type, so a tab can never move or copy the folder on disk (F4: Files
// moves a folder whenever Move is offered). supportedActions is Move only.
var TAB_MIME = "application/x-flea-tab"

var TAB_VIEWS = ["list", "grid", "columns"]

// The process this window runs as, set once from Quickshell.processId where the
// library is shared; tests/js/tabs.js sets it by hand. Empty until set, and an
// empty self never owns a tab, so an unset caller refuses its own drag.
var ownPid = ""

// Set once per window; every caller reads this rather than threading a pid.
function setOwnPid(pid) {
    ownPid = String(pid || "")
}

// One lift's token: the pid names the window, the token names the lift inside it.
function newToken() {
    return String(Date.now()) + "-" + String(Math.floor(Math.random() * 1000000000))
}

// The tab a lift names: the live snapshot for the current tab, the stored one for a hidden
// tab, with the cursor file name only when the row is at hand. Null when no such tab.
function tabInfo(pane, index) {
    if (!pane)
        return null
    var total = count(pane)
    if (index < 0 || index >= total)
        return null
    var here = restingPath(pane)
    var current = currentIndex(pane)
    var path, view, cursor
    cursor = ""
    if (index === current) {
        path = here
        view = pane.viewMode
        if (pane.rowFor && pane.cursorIndex >= 0) {
            var row = pane.rowFor(pane.cursorIndex)
            if (row && typeof row.n === "string")
                cursor = row.n
        }
    } else {
        var items = currentItems(pane, here)
        var item = items[index] || {}
        path = String(item.path || "")
        view = String(item.viewMode || "")
        if (typeof item.cursorName === "string")
            cursor = item.cursorName
    }
    if (!path || path.charAt(0) !== "/")
        return null
    return { path: path, view: view, cursor: cursor }
}

// The platform payload for a lift: JSON because the path may hold a newline. Each field is
// stripped of carriage returns first, so the decode never meets a split it did not write.
// pid and token default to this window and none; a payload with no token never validates.
function tabPayload(pane, index, pid, token) {
    var info = tabInfo(pane, index)
    if (!info)
        return ""
    var clean = function (text) { return String(text).replace(/\r/g, "") }
    var who = pid === undefined ? ownPid : pid
    var lift = token === undefined ? "" : token
    return JSON.stringify([clean(who), clean(lift), clean(info.path), clean(info.view), clean(info.cursor)])
}

// What the lift offers: the private tab MIME and nothing else, so a foreign app refuses
// it. Empty when there is no such tab.
function tabDragMime(pane, index, pid, token) {
    var payload = tabPayload(pane, index, pid, token)
    if (!payload)
        return {}
    var mime = {}
    mime[TAB_MIME] = payload
    return mime
}

// The receiver takes only a well-formed lift: a numeric pid, a non-empty token without
// control characters, and an absolute folder path with none. Anything else, a foreign
// payload or a corrupt one, refuses. Existence and kind are the backend's own peek
// once the tab lands, the way a typed path meets it.
function parseTabMime(payload) {
    var fields = null
    try {
        fields = JSON.parse(String(payload))
    } catch (error) {
        return null
    }
    if (!fields || fields.length !== 5)
        return null
    var pid = String(fields[0] || "")
    var token = String(fields[1] || "")
    var path = String(fields[2] || "")
    if (!/^[0-9]+$/.test(pid))
        return null
    if (token.length === 0 || /[\x00-\x1f\x7f]/.test(token))
        return null
    if (path.length === 0 || path.charAt(0) !== "/" || /[\x00-\x1f\x7f]/.test(path))
        return null
    return { pid: pid, token: token, path: path,
             view: String(fields[3] || ""), cursor: String(fields[4] || "") }
}

// This window's own drag is the reorder path's, never a receive: without this a platform drag
// set down back on its own strip would open a second tab on the folder it came from.
// pid defaults to this window, so callers name only a foreign one to test against.
function isOwnTab(info, pid) {
    var self = pid === undefined ? ownPid : String(pid)
    return !!info && self.length > 0 && info.pid === self
}

// Whether a drag offers the tab MIME; formats alone decide at enter time.
function hasTabFormat(formats) {
    return !!formats && formats.indexOf(TAB_MIME) >= 0
}

// Enter-time accept for a foreign tab drag; payload arrives only at drop.
function enterAccepts(formats, payload, selfPid, canRecv, outActive) {
    var text = String(payload || "")
    if (text.length === 0)
        return hasTabFormat(formats) && canRecv === true
    var info = parseTabMime(text)
    if (!info)
        return false
    var self = selfPid === undefined ? ownPid : String(selfPid)
    if (self.length > 0 && info.pid === self)
        return outActive === true
    return canRecv === true
}

// The strip answers an insertion point, 0 before the first tab and count past the last;
// off the strip the tab lands at the end, which the caller passes as -1.
function dropIndexAt(x, tabWidth, tabCount) {
    return TabMove.insertionAt(x, tabWidth, tabCount)
}

// A catcher may retain drag focus after returning to the source on Hyprland.
// Compare compositor-global coordinates with the source snapshot, never tear off blind.
function catcherOutcome(rect, strip, x, y, tabWidth, tabCount) {
    if (!rect || !(rect.width > 0) || !(rect.height > 0) || !isFinite(x) || !isFinite(y))
        return { outcome: "cancel", at: -1 }
    var localX = x - rect.x, localY = y - rect.y
    if (localX < 0 || localY < 0 || localX >= rect.width || localY >= rect.height)
        return { outcome: "tearoff", at: -1 }
    if (strip && localX >= strip.x && localX < strip.x + strip.width
            && localY >= strip.y && localY < strip.y + strip.height)
        return { outcome: "return", at: dropIndexAt(localX - strip.x, tabWidth, tabCount) }
    return { outcome: "cancel", at: -1 }
}

// Whether the pane may receive a tab: a listing in flight and a full strip both refuse,
// the first with navigation's own sentence. Silent, so an enter probe refuses for free.
function canReceive(pane) {
    if (!pane || pane.listInFlight)
        return false
    return count(pane) < MAX
}

// A tab from another Flea window, opened at the drop position and shown. Own drags refuse,
// because the reorder owns those; a busy or full strip refuses with its sentence.
function receiveTab(pane, payload, at) {
    if (!pane)
        return false
    var info = parseTabMime(payload)
    if (!info || isOwnTab(info))
        return false
    if (busy(pane))
        return false
    if (count(pane) >= MAX) {
        pane.message("Nine tabs is the most.", false)
        return false
    }
    closePreview(pane)
    var dropped = dropOverlay(pane)
    var here = restingPath(pane)
    var items = currentItems(pane, here)
    var index = currentIndex(pane)
    items[index] = snapshot(pane, here)
    var snap = snapshot(pane, info.path)
    if (TAB_VIEWS.indexOf(info.view) >= 0)
        snap.viewMode = info.view
    if (info.cursor.length > 0)
        snap.cursorName = info.cursor
    var place = at >= 0 && at <= items.length ? at : items.length
    items.splice(place, 0, snap)
    pane.tabs = pack(items, place)
    apply(pane, snap, dropped)
    return true
}

// Finder parity: with one tab the strip is hidden, so a lone tab is not lifted;
// moving a window's only tab is moving the window.
function canLift(pane) {
    return count(pane) >= 2
}

// The taken ack names the lift it closes. True only for the outstanding token; the
// caller clears it, so a second ack for the same lift answers false.
function takeToken(stored, token) {
    return !!stored && stored.length > 0 && stored === String(token || "")
}

// xw6 r5: the source holds its lift until the ack arrives or this wait ends, one network leg's own 15 s bound (ui/NetworkMounts.qml mountTimeout).
var ACK_WAIT_MS = 15000

// Whether an ack arriving at now may still close the lift begun at liftedAt.
function ackCloses(stored, token, liftedAt, now) {
    if (!takeToken(stored, token))
        return false
    if (liftedAt > 0 && now - liftedAt > ACK_WAIT_MS)
        return false
    return true
}

// B's synchronous take decision at drop time; the async peek may still refuse, and then no ack goes out.
var DROP_TAKE = "move"
var DROP_IGNORE = "ignore"
function dropDecision(info, selfPid, outActive, canRecv) {
    if (!info)
        return DROP_IGNORE
    if (isOwnTab(info, selfPid))
        return outActive === true ? DROP_TAKE : DROP_IGNORE
    return canRecv === true ? DROP_TAKE : DROP_IGNORE
}

// After an accepted drop the source closes the tab that left. A lone tab is never
// lifted, so no move ever closes a window's only tab: that arm answers kept.
function closeTabAfterMove(pane, index) {
    if (!pane)
        return "kept"
    var total = count(pane)
    if (index < 0 || index >= total)
        return "kept"
    if (busy(pane))
        return "kept"
    if (total <= 1)
        return "kept"
    closeAt(pane, index)
    return "closed"
}

// A lift may not leave the window while a rename is open: the close after an accepted drop
// would take the tab under the editor. The sentence is the refusal, read at the lift.
function tearRefusal(pane) {
    if (!pane)
        return ""
    if (pane.listInFlight)
        return "A directory is already loading."
    if (pane.renamePending === true)
        return "Finish the rename before dragging a tab out."
    if (typeof pane.renameEditor === "function" && pane.renameEditor())
        return "Finish the rename before dragging a tab out."
    return ""
}

// The tab standing on a path: the live one for the current tab, the snapshot's for a
// hidden one. -1 when no tab names it.
function indexOfPath(pane, path) {
    if (!pane || !path)
        return -1
    var here = restingPath(pane)
    var items = currentItems(pane, here)
    var current = currentIndex(pane)
    for (var i = 0; i < items.length; i++) {
        var named = i === current ? here : String((items[i] || {}).path || "")
        if (named === path)
            return i
    }
    return -1
}

// Which tab an accepted drop closes: the lift's index while it still names the dragged
// folder, else the first tab that does. A key pressed mid-drag can shift every index, so
// the number alone may close the wrong tab; -1 when nothing names it, which keeps all.
function resolveMovedTab(pane, index, path) {
    if (!pane || !path)
        return -1
    var total = count(pane)
    if (index >= 0 && index < total) {
        var here = restingPath(pane)
        var items = currentItems(pane, here)
        var current = currentIndex(pane)
        var named = index === current ? here : String((items[index] || {}).path || "")
        if (named === path)
            return index
    }
    return indexOfPath(pane, path)
}
