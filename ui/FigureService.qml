pragma Singleton

import QtQuick
import Quickshell.Io

// One figure request channel to the shared figure worker. The worker is
// classic syntax assembled from ui/js/FigureWorker.mjs
// (tools/vendor-js/assemble-figure-workers.py), because Qt's worker engine
// rejects module syntax and wedges compiling a bundle as a worker source.
// Each bundle travels as text: the service reads it off disk once per kind
// and the worker installs it with one eval, so parsing and rendering stay
// off the thread while the main thread only ever reads a file. A worker
// starts on the first request and a bundle loads on its kind's first
// request, so maths alone never pays for the diagram bytes. Late answers die
// here by ticket: a worker cannot be interrupted, so a render past RENDER_MS
// keeps running and its answer is dropped.
Item {
    id: root

    signal done(int ticket, string svg, string error)
    signal needBundle(int ticket, string kind)

    readonly property int renderMs: 2000
    // Answers that arrived through the worker; the suite reads this as the
    // proof the work happened off the thread.
    property int workerAnswers: 0

    property int seq: 0
    property int sends: 0
    property var waiting: ({})
    property var resends: ({})
    property var loadAttempts: ({})
    property var bundleText: ({})
    property var bundleLoading: ({})
    property var workerReady: ({})

    Loader { id: workerLoader; active: false; sourceComponent: workerComponent }

    Component {
        id: workerComponent
        WorkerScript {
            source: "vendor/figure-worker.js"
            onMessage: function (messageObject) {
                root.handleMessage(messageObject);
            }
        }
    }

    function handleMessage(messageObject) {
        root.workerAnswers++;
        var id = messageObject.id;
        if (root.waiting[id] === undefined)
            return;
        if (messageObject.needBundle !== undefined) {
            root.needBundle(id, messageObject.needBundle);
            return;
        }
        var kind = root.waiting[id].kind;
        delete root.waiting[id];
        delete root.resends[id];
        root.workerReady[kind] = true;
        if (messageObject.svg !== undefined)
            root.done(id, messageObject.svg, "");
        else
            root.done(id, "", messageObject.error || "render failed");
    }

    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            var now = Date.now();
            for (var id in root.waiting) {
                if (now > root.waiting[id].deadline) {
                    delete root.waiting[id];
                    delete root.resends[id];
                    root.done(Number(id), "", "render timed out");
                }
            }
        }
    }

    function worker() {
        if (!workerLoader.active)
            workerLoader.active = true;
        return workerLoader.item;
    }

    function ask(kind, source, display, theme) {
        root.seq++;
        var id = root.seq;
        root.waiting[id] = { kind: kind, source: source, display: display,
            theme: theme, deadline: Date.now() + root.renderMs };
        root.send(id);
        return id;
    }

    function send(id) {
        var w = root.waiting[id];
        if (w === undefined)
            return;
        var message = { id: id, kind: w.kind, source: w.source,
            display: w.display, theme: w.theme };
        if (!root.workerReady[w.kind] && root.bundleText[w.kind])
            message.bundleText = root.bundleText[w.kind];
        root.sends++;
        root.worker().sendMessage(message);
    }

    // A ticket the worker cannot render yet: hand it the bundle text when
    // the text is here, and read the text when it is not. An empty resend
    // ping-pongs forever (measured 1.7M round trips), so only a non-empty
    // text is ever attached; anything else reloads.
    Connections {
        target: root
        function onNeedBundle(ticket, kind) {
            if (root.waiting[ticket] === undefined)
                return;
            if (root.resends[ticket] === undefined)
                root.resends[ticket] = 0;
            root.resends[ticket]++;
            if (root.resends[ticket] > 5) {
                delete root.resends[ticket];
                delete root.waiting[ticket];
                root.done(ticket, "", "figure engine did not start");
                return;
            }
            if (root.bundleText[kind]) {
                root.send(ticket);
                return;
            }
            if (!root.bundleLoading[kind]) {
                root.bundleLoading[kind] = true;
                root.loadAttempts[kind] = 0;
                root.pumpLoader();
            }
        }
    }

    function bundlePath(kind) {
        // Absolute filesystem path, so the read works from a packaged
        // /usr/share/flea/ui and from a dev tree alike. FileView reads
        // plain paths, never URLs, hence the scheme strip.
        var url = Qt.resolvedUrl(kind === "math" ? "vendor/math.mjs" : "vendor/mermaid.mjs");
        return String(url).replace(/^file:\/\//, "");
    }

    FileView {
        id: bundleFile
        printErrors: false
        onPathChanged: {
            if (bundleFile.path !== "")
                root.bundleFailed = false;
        }
        onLoadedChanged: root.bundleArrived()
        onLoadFailed: root.bundleRefused()
    }
    property string loadingKind: ""
    property bool bundleFailed: false

    function bundleArrived() {
        var kind = root.loadingKind;
        if (kind === "" || !bundleFile.loaded)
            return;
        var body = bundleFile.text();
        if (body === "") {
            // An empty read is a race, not a bundle: reload a bounded number
            // of times, then refuse rather than ping-pong forever.
            root.loadAttempts[kind] = (root.loadAttempts[kind] || 0) + 1;
            if (root.loadAttempts[kind] > 3) {
                root.bundleRefused();
                return;
            }
            bundleFile.path = "";
            var url = root.bundlePath(kind);
            bundleFile.path = url;
            return;
        }
        root.loadingKind = "";
        root.bundleLoading[kind] = false;
        root.bundleText[kind] = body;
        bundleFile.path = "";
        for (var id in root.waiting) {
            if (root.waiting[id].kind === kind)
                root.send(Number(id));
        }
        root.pumpLoader();
    }

    function bundleRefused() {
        var kind = root.loadingKind;
        if (kind === "")
            return;
        root.loadingKind = "";
        root.bundleLoading[kind] = false;
        bundleFile.path = "";
        for (var id in root.waiting) {
            if (root.waiting[id].kind === kind) {
                root.done(Number(id), "", "figure engine did not load");
                delete root.waiting[id];
                delete root.resends[id];
            }
        }
        root.pumpLoader();
    }

    // The one FileView reads one bundle at a time; a second kind waits its turn.
    function pumpLoader() {
        if (root.loadingKind !== "")
            return;
        for (var kind in root.bundleLoading) {
            if (root.bundleLoading[kind] && root.bundleText[kind] === undefined) {
                root.loadBundleText(kind);
                return;
            }
        }
    }

    // A plain file read on the thread: parsing the megabytes stays in the
    // worker, this only carries the bytes there.
    function loadBundleText(kind) {
        root.loadingKind = kind;
        bundleFile.path = root.bundlePath(kind);
    }
}
