//@ pragma ShellId flea-menu-shebang-test
import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Permissions.js" as Permissions

// The real backend and IPC seam distinguish a completed negative read from a retained request path.
ShellRoot {
    id: root
    property int phase: 0
    property int checks: 0
    property int failures: 0
    property string scriptPath: Quickshell.env("SHEBANG_SCRIPT")
    property string notesPath: Quickshell.env("SHEBANG_NOTES")

    function check(label, ok) {
        root.checks += 1
        if (!ok) root.failures += 1
        console.log("MENUSHEBANG " + (ok ? "PASS " : "FAIL ") + label + " state=" + ipc.seam.menuState())
    }
    function ask(path, id) {
        stubPane.shebangAsked = path
        stubPane.shebangId = id
        stubPane.rowHasShebang = false
        probeBackend.send({c: "shebang", path: path, id: id})
    }
    function state() { return JSON.parse(ipc.seam.menuState()) }

    Flea.Backend { id: probeBackend; onQuitReady: root.finish() }
    QtObject {
        id: stubPane
        property var backend: probeBackend
        property string shebangAsked: ""
        property int shebangId: 0
        property bool rowHasShebang: false
        property var columnsArea: null
        property var menuActions: ({ready: true, requestId: 1})
        function contextMenu() {
            return {visible: true, hasRow: true, entries: [], cursor: 0, submenuOpen: false,
                submenuCursor: 0, submenuEntries: [], frameItem: null, submenuFrameItem: null,
                workArea: {}, forHeader: false, forRail: false}
        }
    }
    QtObject { id: windowStub; function rectOf(item) { return "" } }
    Flea.Ipc { id: ipc; pane: stubPane; fleaWindow: windowStub }
    Connections {
        target: probeBackend
        function onShebang(path, hasShebang, id) {
            if (!Permissions.landsShebang(path, id, stubPane.shebangAsked, stubPane.shebangId)) return
            stubPane.rowHasShebang = hasShebang
            Qt.callLater(root.advance)
        }
    }
    Component.onCompleted: root.ask(root.scriptPath, 1)

    function advance() {
        var s = root.state()
        if (root.phase === 0) {
            root.check("script-receipt", s.shebangReply.path === root.scriptPath && s.shebangReply.id === 1
                && s.shebangReply.hasShebang === true && s.shebangHas === true)
            root.phase = 1
            root.ask(root.notesPath, 2)
            s = root.state()
            root.check("pending-negative-is-not-a-receipt", !s.shebangHas && s.shebangReply.id !== s.shebangId)
        } else if (root.phase === 1) {
            root.check("plain-receipt-retains-asked-path", s.shebangAsked === root.notesPath && s.shebangId === 2
                && s.shebangReply.path === root.notesPath && s.shebangReply.id === 2
                && s.shebangReply.hasShebang === false && s.shebangHas === false)
            root.phase = 2
            root.ask(root.notesPath, 3)
            s = root.state()
            root.check("same-path-needs-new-id", s.shebangReply.id === 2 && s.shebangId === 3)
            probeBackend.shebang(root.notesPath, true, 2)
            s = root.state()
            root.check("old-id-is-observed-but-not-accepted", s.shebangReply.id === 2
                && s.shebangLastReply.hasShebang === true && s.shebangHas === false)
            probeBackend.shebang(root.scriptPath, true, 3)
            s = root.state()
            root.check("wrong-path-is-observed-but-not-accepted", s.shebangReply.path === root.notesPath
                && s.shebangLastReply.path === root.scriptPath && s.shebangHas === false)
        } else if (root.phase === 2) {
            root.check("new-plain-receipt", s.shebangReply.id === 3 && s.shebangReply.path === root.notesPath
                && s.shebangReply.hasShebang === false && s.shebangHas === false)
            probeBackend.shebang(root.notesPath, true, 2)
            s = root.state()
            root.check("late-old-reply-keeps-completion", s.shebangReply.id === 3
                && s.shebangLastReply.id === 2 && s.shebangHas === false)
            root.phase = 3
            probeBackend.quit()
        }
    }
    function finish() {
        console.log("MENUSHEBANG DONE checks=" + root.checks + " failures=" + root.failures)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    Timer {
        interval: 15000
        running: true
        onTriggered: { root.check("deadline", false); probeBackend.quit() }
    }
}
