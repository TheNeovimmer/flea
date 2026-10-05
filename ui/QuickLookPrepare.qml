import QtQuick
import Quickshell.Io
import "js/Markdown.js" as Markdown
import "js/MarkdownPrepared.js" as Prepared

// A rested cursor on a small regular local Markdown file reads it capped and parses it in the worker into Quick Look's entry.
// The document's small local pictures are decoded ahead too and held while the cursor rests, so the open draws them in its first frame.
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
    // The small local pictures the prepared document names, held decoded until the cursor moves, and whether each has finished loading.
    property var pictures: []
    property bool picturesSettled: true

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
        function onStorageKnownChanged() { root.moved() }
    }

    function moved() {
        root.seq++
        if (root.pictures.length > 0)
            root.pictures = []
        root.picturesSettled = true
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

    // stat sizes the pictures in one child, so no picture past PICTURE_MAX_BYTES is decoded ahead whatever the document links.
    Component {
        id: sizerComponent
        Process {
            id: sizer
            property int seq: 0
            property var urls: []
            command: ["stat", "-L", "--printf", "%s\\t%n\\n", "--"].concat(sizer.urls.map(Prepared.pathOfUrl))
            stdout: StdioCollector {
                onStreamFinished: {
                    root.sized(sizer.seq, sizer.urls, this.text)
                    sizer.destroy()
                }
            }
        }
    }

    // One held Image per small picture, built as the block builds its own so the open finds it in the pixmap cache, whose key holds
    // the url, the transform option and whether the fill keeps the aspect: an Image left at Stretch would never be found by a block.
    Repeater {
        id: held
        model: root.pictures
        delegate: Image {
            required property string modelData
            visible: false
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            autoTransform: true
            source: modelData
            onStatusChanged: root.recount()
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
        if (!Prepared.readsInline(row, pane.storageClass, pane.storageKnown))
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
        var entry = Prepared.take(path, text, dir, chrome, ink)
        if (entry !== null) {
            root.startPictures(entry)
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
        root.startPictures(reply.blocks)
        root.preparedPath = a.path
    }

    function startPictures(blocks) {
        var urls = Prepared.pictureUrls(blocks, Prepared.PICTURE_LIMIT)
        if (urls.length === 0)
            return
        root.picturesSettled = false
        sizerComponent.createObject(root, { seq: root.seq, urls: urls }).running = true
    }

    // The sizes landed: only a cursor that has not moved holds the pictures that fit.
    function sized(seq, urls, statText) {
        if (seq !== root.seq)
            return
        root.pictures = Prepared.smallPictures(urls, statText)
        root.recount()
    }

    // Settled once no held picture is still loading, a failed one included.
    function recount() {
        for (var i = 0; i < held.count; i++) {
            var one = held.itemAt(i)
            if (one !== null && one.status === Image.Loading) {
                root.picturesSettled = false
                return
            }
        }
        root.picturesSettled = true
    }

    // The worker thread lives only while a parse waits.
    function retire() {
        if (root.asked === null)
            parser.active = false
    }
}
