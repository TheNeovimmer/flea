//@ pragma ShellId flea-pdf-first-test

import Quickshell
import QtQuick

// tests/pdf-first.sh's harness: the real ui/PreviewPdf.qml turns a slow first page before it lands and logs state every 15 ms.
ShellRoot {
    id: shell

    readonly property string uiDir: Quickshell.env("PDF_FIRST_UI")
    readonly property string pdfPath: Quickshell.env("PDF_FIRST_PDF")

    property double turnAt: 0
    property bool wantFetch: true
    property bool viewerDone: false
    property bool lateDone: false

    function log(line) { console.log("PDFFIRST " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function state() {
        var item = loader.item
        return "page=" + item.page + " shown=" + item.shownPage + " fellBack=" + (item.fellBack ? 1 : 0)
    }

    // A backend stand-in: PreviewPdf only calls pdfCopy and listens for pdfCopied.
    property var viewerBackend: QtObject {
        signal pdfCopied(int id, string path, string err)
        property int calls: 0
        function pdfCopy(id, path) { calls += 1 }
    }
    property var lateBackend: QtObject {
        signal pdfCopied(int id, string path, string err)
        function pdfCopy(id, path) {}
    }

    // The inner PreviewPdf Quick Look binds path, active and viewport to, found by its fetch id.
    function findInnerPdf(node) {
        if (!node || !node.children)
            return null
        for (var i = 0; i < node.children.length; i++) {
            var kid = node.children[i]
            if (kid.fetchId !== undefined)
                return kid
            var deep = shell.findInnerPdf(kid)
            if (deep)
                return deep
        }
        return null
    }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 560
        color: "#303030"

        Rectangle {
            id: host
            color: "#101315"
            x: 20
            y: 20
            width: 752
            height: 470

            Loader {
                id: loader
                anchors.fill: parent
                source: "file://" + shell.uiDir + "/PreviewPdf.qml"
                onLoaded: {
                    item.path = shell.pdfPath
                    item.active = true
                }
                onStatusChanged: if (status === Loader.Error) { shell.log("FAIL the surface did not load"); shell.quit() }
            }

            // Quick Look's own surface, loaded the way ui/Preview.qml's pdfLoader loads it.
            Loader {
                id: viewerLoader
                anchors.fill: parent
                visible: false
                source: "file://" + shell.uiDir + "/PdfViewer.qml"
                onLoaded: {
                    item.path = Qt.binding(function () { return shell.pdfPath })
                    item.active = true
                    item.backend = Qt.binding(function () { return shell.viewerBackend })
                    item.fetchFirst = Qt.binding(function () { return shell.wantFetch })
                    item.forceActiveFocus()
                    shell.log("VIEWER loaded")
                }
                onStatusChanged: if (status === Loader.Error) { shell.log("FAIL the viewer did not load"); shell.quit() }
            }
        }
    }

    // The viewer forwards its backend and fetch flag to its inner page, which then fetches.
    Timer {
        id: viewerTimer
        interval: 100
        repeat: true
        running: true
        property int waited: 0
        onTriggered: {
            waited += interval
            var outer = viewerLoader.item
            var inner = outer ? shell.findInnerPdf(outer) : null
            if (inner && inner.opened !== "" && shell.viewerBackend.calls >= 1) {
                stop()
                shell.viewerDone = true
                shell.log("VIEWER backend=" + (inner.backend !== null ? 1 : 0)
                    + " fetchFirst=" + (inner.fetchFirst === true ? 1 : 0)
                    + " asked=" + shell.viewerBackend.calls)
            } else if (waited > 8000) {
                stop()
                shell.viewerDone = true
                shell.log("FAIL the viewer never fetched")
            }
        }
    }

    // A storage class arriving after the document opened must not blank it: the fetch decision stands.
    Timer {
        id: lateTimer
        interval: 100
        repeat: true
        running: true
        property int waited: 0
        onTriggered: {
            waited += interval
            if (loader.item && loader.item.pageCount === 2 && !shell.lateDone) {
                stop()
                loader.item.backend = shell.lateBackend
                loader.item.fetchFirst = true
                shell.lateDone = true
                shell.log("FETCHLATE source=" + (loader.item.docSource() !== "" ? 1 : 0))
            } else if (waited > 20000) {
                stop()
                shell.lateDone = true
                shell.log("FAIL the document never opened")
            }
        }
    }

    // The document reports both pages once its first render starts; the turn follows about 50 ms later, while that slow render is still in flight.
    Timer {
        id: waitDocument
        interval: 10
        repeat: true
        running: true
        property int waited: 0
        onTriggered: {
            waited += interval
            if (loader.item && loader.item.pageCount === 2) {
                stop()
                turnTimer.restart()
            } else if (waited > 20000) {
                stop()
                shell.log("FAIL the document never opened")
                shell.quit()
            }
        }
    }

    Timer {
        id: turnTimer
        interval: 50
        onTriggered: {
            shell.turnAt = Date.now()
            loader.item.turn(1)
            shell.log("TURN " + shell.state())
            stateTimer.restart()
            doneTimer.restart()
        }
    }

    Timer {
        id: stateTimer
        interval: 15
        repeat: true
        onTriggered: shell.log("STATE " + (Date.now() - shell.turnAt) + " " + shell.state())
    }

    Timer {
        id: doneTimer
        interval: 50
        repeat: true
        onTriggered: {
            if (loader.item && loader.item.shownPage === 1 && shell.viewerDone && shell.lateDone) {
                stop()
                stateTimer.stop()
                shell.log("STATE " + (Date.now() - shell.turnAt) + " " + shell.state())
                shell.log("DONE")
                shell.quit()
            } else if (shell.viewerDone && shell.lateDone && Date.now() - shell.turnAt > 5000) {
                stop()
                stateTimer.stop()
                shell.log("FAIL the second page never showed")
                shell.quit()
            }
        }
    }
}
