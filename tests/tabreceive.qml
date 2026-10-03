import QtQuick
import "js/sourcefixture.js" as Source
import "js/tabsfixture.js" as Fixture
import "../ui/js/Tabs.js" as Tabs

Item {
    id: test
    property int checked: 0
    property int failed: 0

    Component {
        id: backendFactory
        QtObject {
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
            property var asks: []
            property string sortBy: "name"
            property bool sortDesc: false
            property int listRequests: 0
            property int dirDev: 0
            function peek(path, first, hidden, hiddenLast) {
                asks.push([path, first, hidden, hiddenLast])
            }
        }
    }

    function check(label, actual, expected) {
        test.checked++
        if (actual !== expected) {
            test.failed++
            console.log("FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
        }
    }

    // Sample input: block("function acceptTabDrop(payload, info, at) { ... }", "function acceptTabDrop(").
    function block(text, marker) {
        var start = text.indexOf(marker)
        if (start < 0)
            return ""
        var end = text.indexOf("{", start) + 1
        var depth = 1
        while (depth > 0 && end < text.length) {
            if (text[end] === "{")
                depth++
            else if (text[end] === "}")
                depth--
            end++
        }
        if (depth !== 0)
            throw new Error("unterminated shipped block " + marker)
        return text.slice(start, end)
    }

    // Preserve shipped bindings, Timer and Connections while omitting the Quickshell drag surface.
    function receiver(pane) {
        var text = Source.source("ui/TabBar.qml")
        var timer = block(text, "Timer {\n        id: tabDropDeadline")
        // Sample input: "readonly property int tabDropWaitMs: Tabs.ACK_WAIT_MS".
        var constants = text.match(/^\s*readonly property int tabDrop\w+:.*$/gm) || []
        // Sample input: "onPaneChanged: root.refuseTabDrop()".
        var changed = text.match(/^\s*onPaneChanged:.*$/m) || []
        var code = "import QtQuick\nimport " + JSON.stringify(String(Qt.resolvedUrl("../ui/js/Tabs.js"))) + " as Tabs\n"
            + "Item {\nid: root\nproperty var pane: null\nproperty var pendingTab: null\nproperty var acks: []\n"
            + "function traceTab(stage, detail) {}\nfunction sendTaken(pid, token) { root.acks.push(token) }\n"
            + constants.join("\n") + "\n" + changed.join("\n") + "\n"
            + block(text, "function acceptTabDrop(") + "\n"
            + block(text, "function refuseTabDrop(") + "\n"
            + block(text, "Connections {\n        target: root.pane ? root.pane.backend : null") + "\n"
            + timer + "\n"
            + (timer ? "property alias deadline: tabDropDeadline\n" : "property var deadline: null\n") + "}"
        var bar = Qt.createQmlObject(code, test, "shipped-tab-receiver.qml")
        bar.pane = pane
        return bar
    }

    function pane(path) {
        var result = Fixture.pane(path)
        result.backend = backendFactory.createObject(test)
        return result
    }

    function offer(bar, token, path) {
        var payload = JSON.stringify(["222", token, path, "list", ""])
        bar.acceptTabDrop(payload, Tabs.parseTabMime(payload), -1)
    }

    function answer(pane, path, failed) {
        pane.backend.peeked(path, false, 0, [], failed, 0, false, 2)
    }

    function expire(bar) {
        check("receiver has a deadline Timer", bar.deadline !== null, true)
        if (bar.deadline)
            bar.deadline.triggered()
    }

    Component.onCompleted: {
        Tabs.setOwnPid("111")
        var first = test.pane("/tmp/first")
        var second = test.pane("/tmp/second")
        var switched = test.receiver(first)
        test.offer(switched, "old", "/tmp/old")
        test.check("drop captures its receiving pane", switched.pendingTab.pane === first, true)
        test.check("request carries reserved peek discriminator and flags", JSON.stringify(first.backend.asks[0]), '["/tmp/old",2,false,false]')
        switched.pane = second
        test.check("pane switch clears pending drop", switched.pendingTab === null, true)
        test.check("pane switch visibly refuses on active pane", second.said.join("|"), "That tab could not be received.")
        test.check("pane switch sends no acknowledgment", switched.acks.length, 0)
        test.check("pane switch stops deadline", !switched.deadline || !switched.deadline.running, true)
        test.answer(second, "/tmp/old", false)
        test.check("active backend late reply opens no tab", Tabs.count(first) + Tabs.count(second), 2)
        test.check("active backend late reply sends no acknowledgment", switched.acks.length, 0)
        test.check("active backend late reply adds no refusal", second.said.join("|"), "That tab could not be received.")
        test.offer(switched, "new", "/tmp/new")
        test.check("next pane can request another drop", second.backend.asks.length, 1)
        test.answer(second, "/tmp/new", false)
        test.check("new pane receives next drop", second.path, "/tmp/new")
        test.check("only received drop is acknowledged", switched.acks.join("|"), "new")
        test.check("received drop stops deadline", !switched.deadline || !switched.deadline.running, true)

        var lostPane = test.pane("/tmp/lost")
        var lost = test.receiver(lostPane)
        test.offer(lost, "lost", "/tmp/missing-reply")
        test.check("deadline uses existing acknowledgment bound", lost.deadline ? lost.deadline.interval : 0, Tabs.ACK_WAIT_MS)
        test.expire(lost)
        test.check("lost reply clears pending drop at deadline", lost.pendingTab === null, true)
        test.check("deadline visibly refuses", lostPane.said.join("|"), "That tab could not be received.")
        test.check("deadline sends no acknowledgment", lost.acks.length, 0)
        test.answer(lostPane, "/tmp/missing-reply", false)
        test.check("late reply cannot receive expired drop", Tabs.count(lostPane), 1)
        test.check("late reply sends no acknowledgment", lost.acks.length, 0)
        test.offer(lost, "retry", "/tmp/retry")
        test.check("deadline permits next drop", lostPane.backend.asks.length, 2)
        lostPane.backend.peeked("/tmp/retry", true, 0, [], false, 0, false, 2)
        test.check("unrelated reply leaves pending drop", lost.pendingTab ? lost.pendingTab.token : "", "retry")
        test.check("unrelated reply leaves deadline running", !!lost.deadline && lost.deadline.running, true)
        test.answer(lostPane, "/tmp/retry", false)
        test.check("retry receives its own folder", lostPane.path, "/tmp/retry")
        test.check("retry acknowledges once", lost.acks.join("|"), "retry")
        test.expire(lost)
        test.check("stopped deadline reports no second refusal", lostPane.said.length, 1)

        var gonePane = test.pane("/tmp/gone")
        var gone = test.receiver(gonePane)
        test.offer(gone, "gone", "/tmp/gone-drop")
        gone.pane = null
        test.check("removed pane clears pending drop", gone.pendingTab === null, true)
        test.check("removed pane refuses on captured pane", gonePane.said.join("|"), "That tab could not be received.")
        test.check("removed pane sends no acknowledgment", gone.acks.length, 0)

        var missingPane = test.pane("/tmp/control")
        var missing = test.receiver(missingPane)
        test.offer(missing, "failed", "/tmp/not-there")
        test.answer(missingPane, "/tmp/not-there", true)
        test.check("failed peek clears pending drop", missing.pendingTab === null, true)
        test.check("failed peek keeps existing refusal", missingPane.said.join("|"), "That folder is no longer there.")
        test.check("failed peek sends no acknowledgment", missing.acks.length, 0)
        test.check("failed peek stops deadline", !missing.deadline || !missing.deadline.running, true)
        console.log("tabreceive: " + test.checked + " checks, " + test.failed + " failed")
        Qt.exit(test.failed === 0 ? 0 : 1)
    }
}
