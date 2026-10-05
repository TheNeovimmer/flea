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
                process.write(lines[i]);
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
            // Lines sent while an idle stop was ending the process start it again.
            else if (root.queued.length > 0) {
                root.starting = true;
                process.running = true;
            }
        }
    }

    Timer {
        interval: root.pollMs
        repeat: true
        running: Object.keys(root.outstanding).length > 0
        onTriggered: {
            for (var id in root.outstanding) {
                if (Date.now() - root.outstanding[id].sentAt > root.replyMs) {
                    root.fail();
                    return;
                }
            }
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
        var waiting = root.outstanding;
        root.outstanding = {};
        for (var id in waiting) {
            if (waiting[id].op === "get")
                root.answered(Number(id), "");
            else
                root.known(Number(id), false);
        }
    }

    function stop() {
        if (process.running && !root.stopping) {
            root.stopping = true;
            process.running = false;
        }
    }

    function send(line) {
        if (!root.available)
            return false;
        if (process.running && !root.starting && !root.stopping) {
            process.write(line);
            return true;
        }
        root.queued.push(line);
        if (!root.starting && !root.stopping) {
            root.starting = true;
            process.running = true;
        }
        return true;
    }

    // Sample input: {"op":"get","id":3,"key":"math\n#101315|...\ntrue\nx^2"}.
    function get(id, key) {
        root.outstanding[id] = { op: "get", sentAt: Date.now() };
        if (!root.send(JSON.stringify({ op: "get", id: id, key: key }) + "\n")) {
            delete root.outstanding[id];
            Qt.callLater(function () { root.answered(id, ""); });
        }
    }

    // Sample input: {"op":"put","key":"math\n...","svg":"<svg ...>"}; there is no reply.
    function put(key, svg) {
        if (root.send(JSON.stringify({ op: "put", key: key, svg: svg }) + "\n"))
            root.puts++;
    }

    // Sample input: {"op":"known","id":4,"figures":["math\nx^2","mermaid\nflowchart TD\n    A --> B"]}.
    function ask(id, figures) {
        root.outstanding[id] = { op: "known", sentAt: Date.now() };
        if (!root.send(JSON.stringify({ op: "known", id: id, figures: figures }) + "\n")) {
            delete root.outstanding[id];
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
        var asked = root.outstanding[message.id];
        if (asked === undefined)
            return;
        delete root.outstanding[message.id];
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
