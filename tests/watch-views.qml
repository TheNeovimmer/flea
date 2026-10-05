//@ pragma ShellId flea-watch-views-test
import QtQuick
import Quickshell
import Quickshell.Io

// The real window on a real backend, one view per run: each outside change is waited for in the pane it shows.
ShellRoot {
    id: root
    // A step that has not shown its change by then is stale; the poll only bounds the wait, it asserts no duration.
    readonly property int stepBudgetMs: 8000
    readonly property int pollMs: 50
    readonly property string mode: Quickshell.env("WATCHVIEWS_MODE")
    readonly property string base: Quickshell.env("WATCHVIEWS_ROOT")
    readonly property string open: base + "/parent/open"
    readonly property string other: base + "/other"
    property bool finished: false
    property int stale: 0
    property int stepIndex: -1
    property double stepStarted: 0
    property bool settled: false
    property var steps: []
    property var cacheBefore: null

    function finish(reason) {
        if (finished) return
        finished = true
        console.log("WATCHVIEWS " + root.mode + " " + reason)
        console.log("WATCHVIEWS DONE stale=" + root.stale)
        if (body.item) body.item.quitBackends()
        retire.start()
    }

    function pane() { return body.item.currentPane }
    function namesOf(pane) {
        var out = []
        for (var i = 0; i < pane.total; i++) { var row = pane.rowFor(i); if (row) out.push(row.n) }
        return out
    }
    function neighbourNames(path) {
        var area = root.pane().columnsArea
        return area ? area.rowsFor(path).map(function (row) { return row.n }) : []
    }
    // A step is one outside command and the names the shown rows must then hold, and must no longer hold.
    function step(label, args, shown, has, gone) {
        return { label: label, args: args, shown: shown, has: has, gone: gone }
    }
    function plan() {
        var o = root.open, sub = o + "/sub", parent = root.base + "/parent"
        var out = []
        var middle = function (prefix, dir, shown) {
            out.push(root.step(prefix + "create", ["create", dir + "/new.txt"], shown, "new.txt", ""))
            out.push(root.step(prefix + "rename", ["rename", dir + "/" + (prefix === "second-" ? "o1" : "a") + ".txt", dir + "/renamed.txt"], shown, "renamed.txt", prefix === "second-" ? "o1.txt" : "a.txt"))
            out.push(root.step(prefix + "delete", ["delete", dir + "/" + (prefix === "second-" ? "o2" : "b") + ".txt"], shown, "", prefix === "second-" ? "o2.txt" : "b.txt"))
        }
        if (root.mode === "dual") {
            middle("first-", o, function () { return root.namesOf(root.pane()) })
            out.push({ label: "focus-second", focus: 1 })
            middle("second-", root.other, function () { return root.namesOf(root.pane()) })
            return out
        }
        middle("", o, function () { return root.namesOf(root.pane()) })
        if (root.mode === "columns") {
            var child = function () { return root.neighbourNames(sub) }
            out.push(root.step("child-create", ["create", sub + "/y.txt"], child, "y.txt", ""))
            out.push(root.step("child-rename", ["rename", sub + "/x.txt", sub + "/x2.txt"], child, "x2.txt", "x.txt"))
            out.push(root.step("child-delete", ["delete", sub + "/y.txt"], child, "", "y.txt"))
            var up = function () { return root.neighbourNames(parent) }
            out.push(root.step("parent-create", ["mkdir", parent + "/sibling2"], up, "sibling2", ""))
            out.push(root.step("parent-rename", ["rename", parent + "/sibling", parent + "/sibling-r"], up, "sibling-r", "sibling"))
            out.push(root.step("parent-delete", ["rmdir", parent + "/sibling2"], up, "", "sibling2"))
            // Climbing into the child makes the open folder a neighbour column and a later climb back makes the child one again: each must be watched anew.
            out.push({ label: "enter-child", go: sub })
            out.push(root.step("scrolled-parent-create", ["create", o + "/after-enter.txt"], function () { return root.neighbourNames(o) }, "after-enter.txt", ""))
            out.push({ label: "climb-back", go: o })
            out.push(root.step("returned-child-create", ["create", sub + "/after-climb.txt"], child, "after-climb.txt", ""))
        }
        return out
    }

    function readyToStart() {
        var p = pane()
        if (p.listInFlight || p.listingState !== "ready") return false
        if (root.mode === "dual") return p.total === 4 && body.item.currentPane.path === root.open
        if (p.total !== 4) return false
        if (root.mode !== "columns") return true
        var area = p.columnsArea
        return !!area && area.answered(root.open + "/sub") && area.answered(root.base + "/parent")
    }

    // What the settle wait saw, so a run that never starts says which condition held it.
    function where() {
        var p = pane(), area = p.columnsArea
        return "total=" + p.total + " state=" + p.listingState + " busy=" + p.listInFlight + " path=" + p.path
            + " area=" + !!area + (area ? " child=" + area.answered(root.open + "/sub") + " parent=" + area.answered(root.base + "/parent") + " visible=" + area.visible : "")
    }

    function holds(check) {
        var names = check.shown()
        return (check.has === "" || names.indexOf(check.has) >= 0) && (check.gone === "" || names.indexOf(check.gone) < 0)
    }

    Component {
        id: outsideProcess
        Process {
            id: proc
            running: true
            onExited: function (code) { if (code !== 0) { console.log("WATCHVIEWS outside command failed " + code); root.finish("FAIL outside") } proc.destroy() }
        }
    }

    function begin(index) {
        root.stepIndex = index
        if (index >= root.steps.length) return root.finish("complete")
        var one = root.steps[index]
        root.stepStarted = Date.now()
        if (one.focus !== undefined) {
            body.item.focusSide = one.focus
            return
        }
        if (one.go !== undefined) {
            // The cache before the move, so a later answer is told apart from one the earlier folder left behind.
            root.cacheBefore = root.pane().columnsArea ? root.pane().columnsArea.peeked : null
            root.pane().open(one.go)
            return
        }
        outsideProcess.createObject(root, { command: [Quickshell.env("WATCHVIEWS_OUTSIDE")].concat(one.args) })
    }

    function advance() {
        var one = root.steps[root.stepIndex]
        if (one.go !== undefined) {
            // The new folder's listing and its neighbour columns land before the next outside change.
            var at = root.pane(), area = at.columnsArea
            // A new cache holding the neighbour's answer is that folder's fresh peek, armed before its scan, so the next outside change can only arrive as an event.
            var fresh = !!area && area.peeked !== root.cacheBefore
            if (fresh && at.path === one.go && !at.listInFlight && at.listingState === "ready" && area.answered(one.go === root.open ? root.open + "/sub" : root.open))
                return root.begin(root.stepIndex + 1)
            if (Date.now() - root.stepStarted > root.stepBudgetMs) {
                root.stale += 1
                console.log("WATCHVIEWS " + root.mode + " " + one.label + " STALE no fresh peek answered after the move")
                root.begin(root.stepIndex + 1)
            }
            return
        }
        if (one.focus !== undefined) {
            // The second pane lists its own folder; wait for it before the next outside change.
            var p = root.pane()
            if (p.listInFlight || p.listingState !== "ready" || p.total !== 3) return
            return root.begin(root.stepIndex + 1)
        }
        var ok = root.holds(one)
        if (ok || Date.now() - root.stepStarted > root.stepBudgetMs) {
            if (!ok) root.stale += 1
            console.log("WATCHVIEWS " + root.mode + " " + one.label + " " + (ok ? "updated" : "STALE") + " total=" + root.pane().total + " names=" + one.shown().join(","))
            root.begin(root.stepIndex + 1)
        }
    }

    FloatingWindow {
        id: window
        implicitWidth: 1300
        implicitHeight: 600
        Loader {
            id: body
            anchors.fill: parent
            source: "file://" + Quickshell.env("WATCHVIEWS_UI") + "/WindowBody.qml"
            onLoaded: item.host = window
            onStatusChanged: if (status === Loader.Error) root.finish("FAIL WindowBody failed to load")
        }
    }

    Timer {
        interval: root.pollMs
        repeat: true
        running: true
        onTriggered: {
            if (root.finished || !body.item) return
            if (!root.settled) {
                if (!root.readyToStart()) return
                root.settled = true
                root.steps = root.plan()
                return root.begin(0)
            }
            root.advance()
        }
    }
    Timer { id: retire; interval: 200; onTriggered: Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    Timer { interval: 25000; running: true; onTriggered: if (!root.settled) root.finish("FAIL the first listing never settled: " + root.where()) }
}
