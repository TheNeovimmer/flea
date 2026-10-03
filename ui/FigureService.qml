pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// A lazy sandboxed quickjs-ng helper answers by ticket and loads only the requested bundles; an overdue render kills its generation.
Item {
    id: root

    signal done(int ticket, string svg, string error)

    // Writable so the suite shrinks them; production never writes either.
    property int renderMs: 2000
    // With nothing waiting this long the helper exits, so its memory returns.
    property int idleExitMs: 30000
    // Revisits and theme flips back answer from here, never re-rendered.
    readonly property int cacheMax: 64
    // Helper answers prove the work happened off the GUI thread.
    property int workerAnswers: 0
    // A 127 exit or failed spawn latches the fenced-source fallback with one log line and no retry storm.
    property bool available: true

    property int seq: 0
    property int sends: 0
    property var waiting: ({})
    property var answerCache: ({})
    property var answerOrder: []
    property var pending: []
    property bool starting: false
    property bool stopping: false
    property int generation: 0
    readonly property int killSignal: 9
    readonly property int deadlinePollMs: 250
    // The suite reads this to prove the idle exit stopped the helper.
    readonly property bool helperRunning: helper.running
    // The helper's pid, so the suite reads its peak RSS while it runs.
    readonly property var helperPid: helper.processId
    // The deadline timer stops between tickets so an idle session wakes for nothing.
    readonly property bool deadlineRunning: deadlineTimer.running

    // Mirrors FigureWorker.cacheKey, including the display mode that changes formula layout.
    function cacheKeyOf(kind, source, t, display) {
        var key = [t.bg, t.fg, t.accent || "", t.font || "", t.bodyPx || 0].join("|");
        return kind + "\n" + key + "\n" + !!display + "\n" + source;
    }

    function cached(kind, source, theme, display) {
        var key = root.cacheKeyOf(kind, source, theme, display);
        return root.answerCache[key];
    }

    function store(kind, source, theme, display, svg) {
        var key = root.cacheKeyOf(kind, source, theme, display);
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
            if (root.stopping) {
                helper.signal(root.killSignal);
                return;
            }
            var pending = root.pending;
            root.pending = [];
            for (var i = 0; i < pending.length; i++)
                root.writeLine(pending[i]);
        }

        // A spawn that fails raises runningChanged and never exited, measured, so it reports here.
        onRunningChanged: {
            if (!helper.running && root.starting && !root.stopping) {
                root.starting = false;
                root.refuse("figure engine did not start");
            }
        }

        onExited: function (exitCode, exitStatus) {
            root.starting = false;
            root.stopping = true;
            var error = "figure engine exited " + exitCode + " (status " + exitStatus + ")";
            if (exitCode === 127)
                root.refuse(error);
            else
                root.failGeneration(root.generation, error);
            root.stopping = false;
            if (root.pending.length > 0)
                root.ensureHelper();
        }
    }

    Timer {
        id: deadlineTimer
        interval: root.deadlinePollMs
        repeat: true
        running: false
        onTriggered: {
            var now = Date.now();
            for (var id in root.waiting) {
                var asked = root.waiting[id];
                if (asked !== undefined && now > asked.deadline) {
                    if (asked.generation === 0) {
                        delete root.waiting[id];
                        root.pending = root.pending.filter(function (ticket) { return ticket !== Number(id); });
                        root.done(Number(id), "", "render timed out");
                    } else {
                        root.killHelper(asked.generation);
                    }
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
            if (Object.keys(root.waiting).length === 0 && helper.running) {
                root.stopping = true;
                helper.running = false;
            }
        }
    }

    function armIdle() {
        if (Object.keys(root.waiting).length === 0 && helper.running && !root.stopping)
            idleTimer.restart();
    }

    function failGeneration(generation, error) {
        var failed = [];
        for (var id in root.waiting) {
            if (root.waiting[id].generation === generation) {
                failed.push(Number(id));
                delete root.waiting[id];
            }
        }
        root.pending = root.pending.filter(function (id) { return failed.indexOf(id) < 0; });
        for (var i = 0; i < failed.length; i++)
            root.done(failed[i], "", error);
    }

    function killHelper(generation) {
        var ownsHelper = generation === root.generation && (helper.running || root.starting);
        if (ownsHelper)
            root.stopping = true;
        root.failGeneration(generation, "render timed out");
        if (ownsHelper && helper.running)
            helper.signal(root.killSignal);
    }

    // Refusal fails every ticket into its fenced source without retries.
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
        if (root.waiting[id] === undefined || root.stopping
                || root.waiting[id].generation !== root.generation)
            return;
        root.workerAnswers++;
        var asked = root.waiting[id];
        delete root.waiting[id];
        if (message.svg !== undefined) {
            root.store(asked.kind, asked.source, asked.theme, asked.display, message.svg);
            root.done(id, message.svg, "");
        } else {
            root.done(id, "", message.error || "render failed");
        }
        root.armIdle();
    }

    function ensureHelper() {
        if (!root.available)
            return false;
        if (root.stopping || helper.running || root.starting)
            return true;
        root.generation++;
        root.starting = true;
        idleTimer.stop();
        helper.running = true;
        return true;
    }

    function writeLine(id) {
        var w = root.waiting[id];
        if (w === undefined || root.stopping || !helper.running)
            return;
        w.generation = root.generation;
        // Sample input: {"id":3,"kind":"math","source":"\\frac{a}{b}","display":true,"theme":{"bg":"#101315"}}.
        var line = JSON.stringify({ id: id, kind: w.kind, source: w.source, display: w.display, theme: w.theme }) + "\n";
        root.sends++;
        helper.write(line);
    }

    function ask(kind, source, display, theme) {
        root.seq++;
        var id = root.seq;
        // A revisit or a theme flip back never reaches the helper at all.
        var hit = root.cached(kind, source, theme, display);
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
            theme: theme, generation: 0, deadline: Date.now() + root.renderMs };
        idleTimer.stop();
        deadlineTimer.start();
        if (helper.running && !root.starting && !root.stopping) {
            root.writeLine(id);
        } else {
            root.pending.push(id);
            root.ensureHelper();
        }
        return id;
    }
}
