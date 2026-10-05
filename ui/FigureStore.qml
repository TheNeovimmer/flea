import QtQuick
import Quickshell
import Quickshell.Io

// The persistent figure cache's process: lazy, one JSON line per request. Every failure is a miss, so a figure then draws by the helper as it always did.
Item {
    id: root

    // The drawn svg for a get, or "" for a miss; the figure service owns what a miss means.
    signal answered(int id, string svg)
    // Whether every figure of a warm query already has an entry.
    signal known(int id, bool all)

    // A failed start or an unexpected exit latches the store off for the session, with no retry storm.
    property bool available: true
    // A reply later than this ends the store: its figures draw by the helper.
    property int replyMs: 2000
    // A drain that outlasts a reply's wait is a store that ignores EOF, so it is killed and what waits behind it is a miss.
    property int drainMs: root.replyMs
    // The suite reads these to prove a repeat was served from disk and nothing else started.
    property int hits: 0
    property int misses: 0
    property int puts: 0
    property int exits: 0
    readonly property int pollMs: 250
    readonly property int killSignal: 9
    readonly property bool active: process.running || root.starting
    readonly property var pid: process.processId
    property bool starting: false
    property bool stopping: false
    property var queued: []
    property var outstanding: ({})
    // The replies still owed; a notifying count, because a var property announces only a reassignment and the reply timer binds to this.
    property int owed: 0

    // Flea's own binary, found the way the helper's is; FLEA_BIN is the dev seam.
    Process {
        id: process
        command: [Quickshell.env("FLEA_BIN") || "flea", "--figure-store"]
        running: false
        stdinEnabled: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) { root.receive(data) }
        }

        onStarted: {
            root.starting = false;
            if (root.stopping) {
                process.signal(root.killSignal);
                return;
            }
            var lines = root.queued;
            root.queued = [];
            for (var i = 0; i < lines.length; i++)
                root.write(lines[i].line, lines[i].id);
        }

        // A spawn that fails raises runningChanged and never exited, so it latches here.
        onRunningChanged: {
            if (!process.running && root.starting && !root.stopping)
                root.fail();
        }

        onExited: {
            root.exits++;
            var wasStopping = root.stopping;
            root.starting = false;
            root.stopping = false;
            if (!wasStopping)
                root.fail();
            // Lines sent while an idle stop was draining the process start it again.
            else if (root.queued.length > 0)
                root.begin();
        }
    }

    Timer {
        interval: root.pollMs
        repeat: true
        running: root.owed > 0
        onTriggered: {
            for (var id in root.outstanding) {
                // A line not yet written to the process has no reply clock.
                var sentAt = root.outstanding[id].sentAt;
                if (sentAt !== null && Date.now() - sentAt > root.replyMs) {
                    root.fail();
                    return;
                }
            }
        }
    }

    // A stop that has not exited by drainMs is hung; the timer runs only while the store is stopping.
    Timer {
        interval: root.drainMs
        running: root.stopping
        onTriggered: {
            root.abandon();
        }
    }

    // Releases everything waiting as a miss, so its figures draw by the helper.
    function release() {
        var waiting = root.outstanding;
        root.outstanding = {};
        root.owed = 0;
        for (var id in waiting) {
            if (waiting[id].op === "get")
                root.answered(Number(id), "");
            else
                root.known(Number(id), false);
        }
    }

    // Latches off, ends the process and releases everything waiting as a miss.
    function fail() {
        root.available = false;
        root.queued = [];
        if (process.running) {
            root.stopping = true;
            process.signal(root.killSignal);
        }
        root.release();
    }

    // Kills a store whose drain never ended and releases the lines behind it; no latch, and the queued puts go to the next store.
    function abandon() {
        if (process.running)
            process.signal(root.killSignal);
        root.queued = root.queued.filter(function (entry) { return entry.id === undefined; });
        root.release();
    }

    // An idle stop closes stdin so the store drains (every reply sent, every put committed) and exits; a refused stop is retried at the service's next idle.
    function stop() {
        if (!process.running || root.starting || root.stopping || root.owed > 0 || root.queued.length > 0)
            return false;
        root.stopping = true;
        process.stdinEnabled = false;
        return true;
    }

    // Starts the process with its stdin open, which an earlier stop closed.
    function begin() {
        root.starting = true;
        process.stdinEnabled = true;
        process.running = true;
    }

    function owe(id, op) {
        root.outstanding[id] = { op: op, sentAt: null };
        root.owed = Object.keys(root.outstanding).length;
    }

    function settle(id) {
        delete root.outstanding[id];
        root.owed = Object.keys(root.outstanding).length;
    }

    // Writes one line and starts its reply clock; a put has no id and no reply.
    function write(line, id) {
        process.write(line);
        if (id !== undefined && root.outstanding[id] !== undefined)
            root.outstanding[id].sentAt = Date.now();
    }

    function send(line, id) {
        if (!root.available)
            return false;
        if (process.running && !root.starting && !root.stopping) {
            root.write(line, id);
            return true;
        }
        root.queued.push({ line: line, id: id });
        if (!root.starting && !root.stopping)
            root.begin();
        return true;
    }

    // Sample input: {"op":"get","id":3,"key":"math\n#101315|...\ntrue\nx^2"}.
    function get(id, key) {
        root.owe(id, "get");
        if (!root.send(JSON.stringify({ op: "get", id: id, key: key }) + "\n", id)) {
            root.settle(id);
            Qt.callLater(function () { root.answered(id, ""); });
        }
    }

    // Sample input: {"op":"put","key":"math\n...","svg":"<svg ...>"}; there is no reply.
    function put(key, svg) {
        if (root.send(JSON.stringify({ op: "put", key: key, svg: svg }) + "\n"))
            root.puts++;
    }

    // Sample input: {"op":"known","id":4,"keys":["math\n#101315|...\ntrue\nx^2","mermaid\n#101315|...\ntrue\nflowchart TD\n    A --> B"]}.
    function ask(id, keys) {
        root.owe(id, "known");
        if (!root.send(JSON.stringify({ op: "known", id: id, keys: keys }) + "\n", id)) {
            root.settle(id);
            Qt.callLater(function () { root.known(id, false); });
        }
    }

    function receive(line) {
        // Sample input: {"id":3,"svg":"<svg ...>"}, {"id":3,"miss":true} or {"id":4,"known":true}.
        var message = null;
        try {
            message = JSON.parse(line);
        } catch (e) {
            return;
        }
        // A bare null parses and has no id to read.
        if (message === null)
            return;
        var asked = root.outstanding[message.id];
        if (asked === undefined)
            return;
        root.settle(message.id);
        if (asked.op === "known") {
            root.known(message.id, message.known === true);
        } else if (message.svg !== undefined) {
            root.hits++;
            root.answered(message.id, message.svg);
        } else {
            root.misses++;
            root.answered(message.id, "");
        }
    }
}
