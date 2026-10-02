pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// One figure request channel to the sandboxed quickjs-ng helper. The helper
// loads its own bundles, so maths alone never pays for the diagram bytes.
// Each answer lands here by ticket: a helper cannot be interrupted, so a
// render past renderMs is killed and its answer is dropped.
Item {
    id: root

    signal done(int ticket, string svg, string error)

    // Writable so the suite shrinks them; production never writes either.
    property int renderMs: 2000
    // With nothing waiting this long the helper exits, so its memory returns.
    property int idleExitMs: 30000
    // Revisits and theme flips back answer from here, never re-rendered.
    readonly property int cacheMax: 64
    // Answers that arrived through the helper; the suite reads this as the
    // proof the work happened off the thread.
    property int workerAnswers: 0
    // Latched false when the helper exits 127 or never starts: every figure
    // then shows its fenced source, with one log line and no retry storm.
    property bool available: true

    property int seq: 0
    property int sends: 0
    // True from the timeout kill until its exit lands, so that exit alone never fails a fresh ticket.
    property bool killing: false
    property var waiting: ({})
    property var answerCache: ({})
    property var answerOrder: []
    property var pending: []
    property bool starting: false
    // The suite reads this to prove the idle exit stopped the helper.
    readonly property bool helperRunning: helper.running
    // The helper's pid, so the suite reads its peak RSS while it runs.
    readonly property var helperPid: helper.processId
    // The deadline timer runs only while waiting holds a ticket, so an idle
    // session wakes for nothing; the suite reads this the same way.
    readonly property bool deadlineRunning: deadlineTimer.running

    // Mirrors ui/js/FigureWorker.mjs themeKey and cacheKey, the key the two
    // sides agree on; the module itself is an ES import this QML never loads.
    function cacheKeyOf(kind, source, t) {
        var key = [t.bg, t.fg, t.accent || "", t.font || "", t.bodyPx || 0].join("|");
        return kind + "\n" + key + "\n" + source;
    }

    function cached(kind, source, theme) {
        var key = root.cacheKeyOf(kind, source, theme);
        return root.answerCache[key];
    }

    function store(kind, source, theme, svg) {
        var key = root.cacheKeyOf(kind, source, theme);
        var at = root.answerOrder.indexOf(key);
        if (at >= 0)
            root.answerOrder.splice(at, 1);
        root.answerCache[key] = svg;
        root.answerOrder.push(key);
        while (root.answerOrder.length > root.cacheMax)
            delete root.answerCache[root.answerOrder.shift()];
    }

    Process {
        id: helper
        // FLEA_BIN is the dev seam, see AGENTS.md "Where the backend binary comes from".
        command: [Quickshell.env("FLEA_BIN") || "flea", "--figure-helper"]
        running: false
        stdinEnabled: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) { root.receive(data) }
        }

        onStarted: {
            root.starting = false;
            for (var i = 0; i < root.pending.length; i++)
                root.writeLine(root.pending[i]);
            root.pending = [];
        }

        // A spawn that fails raises runningChanged and never exited, measured, so it reports here.
        onRunningChanged: {
            if (!helper.running && root.starting) {
                root.starting = false;
                root.refuse("figure engine did not start");
            }
        }

        onExited: function (exitCode, exitStatus) {
            var killed = root.killing;
            root.killing = false;
            root.starting = false;
            if (exitCode === 127) {
                root.refuse("figure engine did not start");
                return;
            }
            // An unexpected death with tickets waiting answers them now, so a
            // broken helper shows the fence at once instead of a blank band.
            if (!killed && Object.keys(root.waiting).length > 0) {
                console.log("FigureService: the figure engine stopped, figures show their fenced source");
                for (var id in root.waiting) {
                    root.done(Number(id), "", "figure engine stopped");
                    delete root.waiting[id];
                }
            }
            // A deliberate kill or idle stop leaves the waiting to their own
            // deadlines; the next ask starts a fresh helper.
        }
    }

    Timer {
        id: deadlineTimer
        interval: 250
        repeat: true
        running: false
        onTriggered: {
            var now = Date.now();
            for (var id in root.waiting) {
                if (now > root.waiting[id].deadline) {
                    delete root.waiting[id];
                    root.done(Number(id), "", "render timed out");
                    root.killHelper();
                }
            }
            // The tick that finds waiting empty arms the idle exit, then stops.
            if (Object.keys(root.waiting).length === 0) {
                root.armIdle();
                deadlineTimer.stop();
            }
        }
    }

    Timer {
        id: idleTimer
        interval: root.idleExitMs
        onTriggered: {
            if (Object.keys(root.waiting).length === 0 && helper.running)
                helper.running = false;
        }
    }

    function armIdle() {
        if (Object.keys(root.waiting).length === 0 && helper.running)
            idleTimer.restart();
    }

    function killHelper() {
        if (helper.running) {
            root.killing = true;
            helper.signal(9);
        }
    }

    // Every waiting request fails the same way a render failure fails: the
    // figure shows its fenced source, and nothing is ever retried.
    function refuse(error) {
        if (!root.available)
            return;
        root.available = false;
        console.log("FigureService: " + error + ", figures show their fenced source");
        for (var id in root.waiting) {
            root.done(Number(id), "", error);
            delete root.waiting[id];
        }
        root.pending = [];
    }

    function receive(line) {
        // Sample input: {"id":3,"svg":"<svg ...>...</svg>"} or {"id":3,"error":"formula over 4 KiB"}.
        if (!line || line.length === 0)
            return;
        var message = null;
        try {
            message = JSON.parse(line);
        } catch (e) {
            return;
        }
        var id = message.id;
        if (root.waiting[id] === undefined)
            return;
        root.workerAnswers++;
        var asked = root.waiting[id];
        delete root.waiting[id];
        if (message.svg !== undefined) {
            root.store(asked.kind, asked.source, asked.theme, message.svg);
            root.done(id, message.svg, "");
        } else {
            root.done(id, "", message.error || "render failed");
        }
        root.armIdle();
    }

    function ensureHelper() {
        if (!root.available)
            return false;
        if (helper.running || root.starting)
            return true;
        root.starting = true;
        idleTimer.stop();
        helper.running = true;
        return true;
    }

    function writeLine(id) {
        var w = root.waiting[id];
        if (w === undefined)
            return;
        // Sample input: {"id":3,"kind":"math","source":"\\frac{a}{b}","display":true,"theme":{"bg":"#101315"}}.
        var line = JSON.stringify({ id: id, kind: w.kind, source: w.source, display: w.display, theme: w.theme }) + "\n";
        root.sends++;
        helper.write(line);
    }

    function ask(kind, source, display, theme) {
        root.seq++;
        var id = root.seq;
        // A revisit or a theme flip back never reaches the helper at all.
        var hit = root.cached(kind, source, theme);
        if (hit !== undefined) {
            // Deferred past this return, so the caller's ticket is set before its answer lands.
            Qt.callLater(function () { root.done(id, hit, ""); });
            return id;
        }
        if (!root.available) {
            Qt.callLater(function () { root.done(id, "", "figure engine did not start"); });
            return id;
        }
        root.waiting[id] = { kind: kind, source: source, display: display,
            theme: theme, deadline: Date.now() + root.renderMs };
        idleTimer.stop();
        deadlineTimer.start();
        if (root.ensureHelper()) {
            if (helper.running)
                root.writeLine(id);
            else
                root.pending.push(id);
        }
        return id;
    }
}
