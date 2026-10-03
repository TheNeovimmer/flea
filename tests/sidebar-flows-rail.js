// A press on the shown rail takes the keyboard when the rail is an overlay and leaves it where it was when docked.
function steps(root, pane, state) {
    var cursorBefore = ""
    var home = null
    function rail() { return root.find(pane, "PaneRail") }
    function shown() { return pane.sidebar && rail() && !rail().hidden }
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
            // A pointer left over the docked rail would leave its hover flag set across the unload.
            root.move(pane, 600, 300)
            return true
        },
        function () {
            if (pane.sidebar && rail().over) return false
            state.changeLeaf("places", { autoHide: true })
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
