// A press on the shown rail takes the keyboard when the rail is an overlay and leaves it where it was when docked.
function steps(root, pane, state) {
    var cursorBefore = ""
    var home = null
    function rail() { return root.find(pane, "PaneRail") }
    function shown() { return pane.sidebar && rail() && !rail().hidden }
    // Pane coordinates: on the docked rail, at the window's left edge, and clear of both.
    var onRailX = 40, onRailY = 100, awayX = 600, awayY = 300
    function reveal() { root.move(pane, 1, 80) }
    function homeRow() { return pane.sidebar.railItemFor(0) }
    // Back to a list keyboard with the rail up, a listing row under the rail marked, and the rail cursor off Home.
    function arm() {
        pane.contextMenu().close()
        pane.focusView = "list"
        root.pick("readonly")
        cursorBefore = pane.cursorRow.n
        pane.sidebar.cursorIndex = pane.sidebar.entries.length - 1
    }
    function settle(label) {
        root.check(label + ": the rail has the keyboard", pane.focusView, "rail")
        root.check(label + ": the covered listing row stays the cursor", pane.cursorRow.n, cursorBefore)
        root.check(label + ": the pane stays where it was", pane.path, pane.home)
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
            // Off the edge strip and on the revealed rail, the rail's own hover is what holds it up.
            if (!rail().over) return false
            root.check("autohide-switch: the pointer on the revealed rail holds it", rail().wanted, true)
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
            pane.open(pane.home)
            return true
        },
        function () {
            if (!root.ready(pane.home)) return false
            reveal()
            return true
        },
        function () {
            if (!shown()) return false
            arm()
            home = homeRow()
            root.click(home.labelItem, 10, home.labelItem.height / 2)
            return true
        },
        function () {
            settle("autohide-row-press")
            root.check("autohide-row-press: the rail cursor is the pressed row", pane.sidebar.cursorIndex, 0)
            reveal()
            return true
        },
        function () {
            if (!shown()) return false
            arm()
            var sidebar = pane.sidebar
            var last = sidebar.railItemFor(sidebar.entries.length - 1)
            var y = last.mapToItem(sidebar, 0, last.height).y + 8
            root.check("control: the rail has blank ground below its last row", y < sidebar.height, true)
            root.click(sidebar, 10, y)
            return true
        },
        function () {
            settle("autohide-blank-press")
            root.check("autohide-blank-press: no row was activated", pane.sidebar.cursorIndex, pane.sidebar.entries.length - 1)
            reveal()
            return true
        },
        function () {
            if (!shown()) return false
            arm()
            // Home offers no menu by default; the Trash row always does.
            var trash = pane.sidebar.railItemFor(pane.sidebar.entries.findIndex(function (e) { return e.kind === "trash" }))
            root.check("control: the rail has a Trash row", trash !== null, true)
            root.click(trash.labelItem, 10, trash.labelItem.height / 2, Qt.RightButton)
            return true
        },
        function () {
            var menu = pane.contextMenu()
            root.check("autohide-right-press: the rail's menu opened", menu.opened && menu.forRail, true)
            settle("autohide-right-press")
            menu.close()
            state.changeLeaf("places", { autoHide: false })
            return true
        },
        function () {
            if (!pane.sidebar || !rail() || rail().overlay) return false
            arm()
            pane.sidebar.cursorIndex = 0
            home = homeRow()
            root.click(home.labelItem, 10, home.labelItem.height / 2)
            return true
        },
        function () {
            root.check("docked-row-press: a docked press leaves the keyboard on the list", pane.focusView, "list")
            root.check("docked-row-press: the covered listing row stays the cursor", pane.cursorRow.n, cursorBefore)
            return true
        }
    ]
}
