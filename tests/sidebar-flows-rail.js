// A press on the shown rail takes the keyboard when the rail is an overlay and leaves it where it was when docked.
function steps(root, pane, state) {
    var cursorBefore = ""
    var home = null
    function rail() { return root.find(pane, "PaneRail") }
    function shown() { return pane.sidebar && rail() && !rail().hidden }
    // Pane coordinates: on the docked rail, at the window's left edge, and clear of both.
    var onRailX = 40, onRailY = 100, awayX = 600, awayY = 300
    // Rail rows and listing rows are the same height and sit on the same grid, so a press at a label's middle lands on a row seam; this lands inside the row.
    var pressInsetY = 2
    function reveal() { root.move(pane, 1, 80) }
    function homeRow() { return pane.sidebar.railItemFor(0) }
    // The listing the presses cover: enough rows (see tests/sidebar-flows.sh) that a row lies under every press point.
    function work() { return pane.home + "/Downloads" }
    var listsBefore = 0
    // The hover hold is read this many withdraw timers after the pointer came to rest on the rail.
    var holdSettles = 2, heldSince = 0
    // Sample input: file7.txt (the listing row whose bounds hold the point), or empty over bare listing ground.
    function rowUnder(item, x, y) {
        for (var i = 0; i < pane.rows.length; i++) {
            var row = pane.visibleItemFor(pane.held + i)
            if (!row) continue
            var at = item.mapToItem(row, x, y)
            if (at.x >= 0 && at.x < row.width && at.y >= 0 && at.y < row.height) return pane.rows[i].n
        }
        return ""
    }
    // Back to a list keyboard with the rail up, the rail cursor off the pressed row, and a listing row other than the one under the press marked.
    function arm(label, item, x, y) {
        pane.contextMenu().close()
        pane.focusView = "list"
        var under = item ? rowUnder(item, x, y) : ""
        var other = pane.rows.filter(function (r) { return r.n !== under })[0].n
        root.pick(other)
        cursorBefore = pane.cursorRow.n
        pane.sidebar.cursorIndex = pane.sidebar.entries.length - 1
        listsBefore = pane.backend.listRequests
        if (!item) return
        var covered = rowUnder(item, x, y)
        root.check(label + ": control: a listing row other than the cursor lies under the press", covered !== "" && covered !== cursorBefore, true)
    }
    function settle(label) {
        root.check(label + ": the rail has the keyboard", pane.focusView, "rail")
        root.check(label + ": the covered listing row stays the cursor", pane.cursorRow.n, cursorBefore)
        root.check(label + ": only the marked row is selected", pane.selectedIndices(), [root.indexOf(cursorBefore)])
    }
    // A press that is not a row's click opens nothing: the folder, the listing request count and Trash stay as armed.
    function idle(label) {
        root.check(label + ": no navigation left the folder", pane.path, work())
        root.check(label + ": no listing was requested", pane.backend.listRequests - listsBefore, 0)
        root.check(label + ": Trash was not opened", pane.trash.opened, false)
    }
    return [
        function () {
            // The pointer rests on the docked rail, which is how the hover flag gets set.
            if (!pane.sidebar || !rail() || rail().overlay || rail().hidden) return false
            root.move(pane, onRailX, onRailY)
            return true
        },
        function () {
            if (!rail().over) return false
            root.check("control: the pointer on the docked rail sets over", rail().over, true)
            state.changeLeaf("places", { autoHide: true })
            return true
        },
        function () {
            if (pane.sidebar) return false
            root.check("autohide-switch: over clears with the Sidebar", rail().over, false)
            root.check("autohide-switch: the rail is withdrawn", rail().hidden, true)
            reveal()
            return true
        },
        function () {
            if (!shown()) return false
            root.check("autohide-switch: the left edge reveals the rail again", rail().revealed, true)
            root.move(pane, onRailX, onRailY)
            return true
        },
        function () {
            // Off the edge strip and on the revealed rail, the rail's own hover is what holds it up, so it is still up after the withdraw timer would have run.
            if (!heldSince) { if (!rail().over) return false; heldSince = Date.now() }
            if (Date.now() - heldSince < holdSettles * rail().settleMs) return false
            root.check("autohide-switch: the pointer on the revealed rail holds it past the settle", shown() && rail().revealed, true)
            root.move(pane, awayX, awayY)
            return true
        },
        function () {
            if (pane.sidebar) return false
            root.check("autohide-switch: leaving withdraws the rail", rail().revealed, false)
            state.changeLeaf("places", { autoHide: false })
            return true
        },
        function () {
            if (!pane.sidebar || !rail() || rail().overlay || rail().hidden) return false
            root.move(pane, onRailX, onRailY)
            return true
        },
        function () {
            if (!rail().over) return false
            root.press(Qt.Key_B, Qt.ControlModifier)
            return true
        },
        function () {
            if (pane.sidebar) return false
            root.check("toggle-rail: over clears with the Sidebar", rail().over, false)
            state.changeLeaf("places", { autoHide: true })
            reveal()
            return true
        },
        function () {
            if (!shown()) return false
            root.check("toggle-rail: the left edge reveals the rail after auto-hide is switched on", rail().revealed, true)
            root.move(pane, awayX, awayY)
            return true
        },
        function () {
            if (pane.sidebar) return false
            state.changeLeaf("places", { rail: "shown" })
            // A list view runs the rows under the rail; a column view would put the parent column there.
            pane.chooseView("list")
            pane.open(pane.home)
            return true
        },
        function () {
            if (!root.ready(pane.home) || pane.viewMode !== "list") return false
            reveal()
            return true
        },
        function () {
            if (!shown()) return false
            // Home is the open folder here, so the press opens nothing new and the covered listing's cursor is still readable.
            var open = homeRow()
            arm("autohide-row-press", open.labelItem, 10, pressInsetY)
            root.click(open.labelItem, 10, pressInsetY)
            return true
        },
        function () {
            settle("autohide-row-press")
            root.check("autohide-row-press: the press stayed in the open folder", pane.path, pane.home)
            root.check("autohide-row-press: the open folder's own row requested no listing", pane.backend.listRequests - listsBefore, 0)
            pane.open(work())
            return true
        },
        function () {
            if (!root.ready(work())) return false
            reveal()
            return true
        },
        function () {
            if (!shown()) return false
            home = homeRow()
            arm("autohide-home-press", null, 0, 0)
            root.click(home.labelItem, 10, home.labelItem.height / 2)
            // A row that opens another folder cannot show the covered cursor once its listing lands, so this press pins the open itself.
            root.check("autohide-home-press: the rail has the keyboard", pane.focusView, "rail")
            root.check("autohide-home-press: the rail cursor is the pressed row", pane.sidebar.cursorIndex, 0)
            return true
        },
        function () {
            // The row keeps its click under the passive handler: the pane opens Home, which is not the open folder, with one listing request.
            if (!root.ready(pane.home)) return false
            root.check("autohide-home-press: the row opened its own folder", pane.path, pane.home)
            root.check("autohide-home-press: the row opened it with one listing request", pane.backend.listRequests - listsBefore, 1)
            pane.open(work())
            return true
        },
        function () {
            if (!root.ready(work())) return false
            reveal()
            return true
        },
        function () {
            if (!shown()) return false
            var sidebar = pane.sidebar
            var last = sidebar.railItemFor(sidebar.entries.length - 1)
            var y = last.mapToItem(sidebar, 0, last.height).y + 8
            root.check("control: the rail has blank ground below its last row", y < sidebar.height, true)
            arm("autohide-blank-press", sidebar, 10, y)
            root.click(sidebar, 10, y)
            return true
        },
        function () {
            settle("autohide-blank-press")
            idle("autohide-blank-press")
            root.check("autohide-blank-press: no row was activated", pane.sidebar.cursorIndex, pane.sidebar.entries.length - 1)
            reveal()
            return true
        },
        function () {
            if (!shown()) return false
            // Home offers no menu by default; the Trash row always does.
            var trash = pane.sidebar.railItemFor(pane.sidebar.entries.findIndex(function (e) { return e.kind === "trash" }))
            root.check("control: the rail has a Trash row", trash !== null, true)
            var y = trash.labelItem.height / 2
            arm("autohide-right-press", trash.labelItem, 10, y)
            root.click(trash.labelItem, 10, y, Qt.RightButton)
            return true
        },
        function () {
            var menu = pane.contextMenu()
            root.check("autohide-right-press: the rail's menu opened", menu.opened && menu.forRail, true)
            settle("autohide-right-press")
            idle("autohide-right-press")
            menu.close()
            state.changeLeaf("places", { autoHide: false })
            return true
        },
        function () {
            if (!pane.sidebar || !rail() || rail().overlay) return false
            home = homeRow()
            var y = home.labelItem.height / 2
            arm("docked-row-press", null, 0, 0)
            root.click(home.labelItem, 10, y)
            return true
        },
        function () {
            // The press reached the row (it opened Home from the work folder) and the docked rail left the keyboard on the list.
            if (!root.ready(pane.home)) return false
            root.check("docked-row-press: the rail cursor is the pressed row", pane.sidebar.cursorIndex, 0)
            root.check("docked-row-press: the row opened its own folder", pane.path, pane.home)
            root.check("docked-row-press: a docked press leaves the keyboard on the list", pane.focusView, "list")
            return true
        }
    ]
}
