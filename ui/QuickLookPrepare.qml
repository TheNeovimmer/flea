import QtQuick
import Quickshell.Io
import "js/Markdown.js" as Markdown
import "js/MarkdownPrepared.js" as Prepared

// A rested cursor on a small regular local Markdown file reads it capped and parses it in the worker into Quick Look's entry.
Item {
    id: root

    property var pane: null
    // False while Quick Look is open: the entry is for the next Space.
    property bool resting: true
    // The rest the preview column's own settle waits, so a sweep reads nothing.
    property int restMs: 120
    // What a suite reads: files read at rest, the bytes the last read returned, parses the worker answered, and the file the entry last took.
    property int reads: 0
    property int readBytes: 0
    property int workerAnswers: 0
    property string preparedPath: ""
    // A cursor move bumps seq, so a read or a parse that answers after it is dropped.
    property int seq: 0
    // The one request waiting on the worker: its seq, path, text and the inputs the parse took.
    property var asked: null

    Timer {
        id: rest
        interval: root.restMs
        onTriggered: root.prepare()
    }

    Connections {
        target: root.pane
        function onCursorIndexChanged() { root.moved() }
        function onRowsChanged() { root.moved() }
        function onListInFlightChanged() { root.moved() }
    }

    function moved() {
        root.seq++
        rest.restart()
    }

    // head caps the bytes actually read, whatever the file grew to since its row was listed.
    Component {
        id: readerComponent
        Process {
            id: proc
            property int seq: 0
            property string path: ""
            command: ["head", "-c", String(Prepared.MAX_BYTES + 1), "--", proc.path]
            stdout: StdioCollector {
                onStreamFinished: {
                    root.landed(proc.seq, proc.path, this.text, this.data.byteLength)
                    proc.destroy()
                }
            }
        }
    }

    Loader {
        id: parser
        active: false
        sourceComponent: WorkerScript {
            source: "MarkdownWorker.js"
            onMessage: function (messageObject) { root.answered(messageObject) }
        }
    }

    function prepare() {
        var pane = root.pane
        if (!root.resting || !pane || pane.listInFlight)
            return
        var row = pane.rowFor(pane.cursorIndex)
        if (!Prepared.readsInline(row, pane.storageClass))
            return
        root.reads++
        var request = readerComponent.createObject(root, { seq: root.seq, path: pane.join(pane.path, row.n) })
        request.running = true
    }

    // The read landed: a stale or oversized answer is dropped, a held one is kept, and anything else goes to the worker.
    function landed(seq, path, text, bytes) {
        root.readBytes = bytes
        if (seq !== root.seq || bytes > Prepared.MAX_BYTES || text.length === 0)
            return
        var dir = Markdown.dirOf(path)
        var chrome = Prepared.hexOf(Theme.color.background)
        var ink = Prepared.hexOf(Theme.color.foreground)
        if (Prepared.take(path, text, dir, chrome, ink) !== null) {
            root.preparedPath = path
            return
        }
        root.asked = { seq: seq, path: path, text: text, dir: dir, chrome: chrome, ink: ink }
        parser.active = true
        parser.item.sendMessage({ seq: seq, source: text, dir: dir, chrome: chrome, ink: ink })
    }

    // The worker answered: the entry is stored only for the request still waiting and a cursor that has not moved.
    function answered(reply) {
        var a = root.asked
        if (a === null || a.seq !== reply.seq)
            return
        root.asked = null
        Qt.callLater(root.retire)
        // A parse that throws is Quick Look's to report on Space, so nothing is kept here.
        if (reply.seq !== root.seq || reply.error !== "")
            return
        Prepared.store(a.path, a.text, a.dir, a.chrome, a.ink, reply.blocks)
        root.workerAnswers++
        root.preparedPath = a.path
    }

    // The worker thread lives only while a parse waits.
    function retire() {
        if (root.asked === null)
            parser.active = false
    }
}
