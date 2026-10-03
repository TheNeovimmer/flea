//@ pragma ShellId flea-markdown-source-render-test
import QtQuick
import Quickshell
import "flea" as Flea

ShellRoot {
    id: shell
    property bool done: false
    property int checks: 0
    property int failures: 0
    property int step: 0
    property string output: Quickshell.env("XDG_RUNTIME_DIR") + "/markdown-source.png"
    Component.onCompleted: Flea.ViewState.state = { display: { textSize: { mode: 14 } } }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(ok, label) {
        checks++
        if (!ok) failures++
        console.log("MARKDOWN_SOURCE " + (ok ? "CHECK " : "FAIL ") + label)
    }
    FloatingWindow {
        implicitWidth: 1120
        implicitHeight: 240
        color: "#101315"
        Flea.PreviewMarkdown {
            id: sourcePane
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 560
            active: true
            view: "source"
            path: Quickshell.env("FLEA_MARKDOWN_FIXTURE")
            size: 1
        }
        Loader {
            id: reference
            x: sourcePane.width
            width: sourcePane.width
            height: sourcePane.height
            sourceComponent: Flea.PreviewMarkdown {
                active: true
                path: sourcePane.path
                size: 1
            }
        }
    }
    function sourceParts() {
        for (var i = 0; i < sourcePane.children.length; i++) {
            var flick = sourcePane.children[i]
            if (flick === sourcePane.bodyItem || flick.contentItem === undefined)
                continue
            for (var j = 0; j < flick.contentItem.children.length; j++) {
                var text = flick.contentItem.children[j]
                if (text.text !== undefined)
                    return { flick: flick, text: text }
            }
        }
        return null
    }
    function geometry() {
        var rendered = reference.item
        var parts = sourceParts()
        var block = rendered.blockItem(0)
        if (!parts || !block) {
            check(false, "source and rendered live text exist")
            return
        }
        var at = parts.text.mapToItem(sourcePane, 0, 0)
        var first = block.mapToItem(rendered, 0, 0)
        var label = " at body " + Flea.Theme.font.body
        check(at.x === first.x && at.x === sourcePane.insetX, "source left equals rendered inset" + label)
        check(at.y === first.y && at.y === sourcePane.insetY,
            "source top equals rendered inset" + label + " (" + at.y + "/" + first.y + "/" + sourcePane.insetY + ")")
        check(sourcePane.width - at.x - parts.text.width === sourcePane.insetX, "source right inset" + label)
        check(parts.flick.contentHeight === Math.max(parts.flick.height, parts.text.implicitHeight + 2 * sourcePane.insetY),
            "source bottom inset remains scrollable" + label)
        check(parts.text.textFormat === Text.PlainText && parts.text.text === sourcePane.rawText, "source remains verbatim" + label)
        var scrollbars = 0
        for (var i = 0; i < parts.flick.children.length; i++) {
            var bar = parts.flick.children[i]
            if (bar.knobItem === undefined || bar.flickable !== parts.flick || bar.width <= 0)
                continue
            scrollbars++
            check(bar.mapToItem(sourcePane, bar.width, 0).x === sourcePane.width, "source scrollbar stays on frame edge" + label)
        }
        check(scrollbars === 1, "exactly one Source scrollbar belongs to flickable with positive width" + label)
    }
    Timer {
        interval: 600
        repeat: true
        running: !shell.done
        onTriggered: {
            if (!sourcePane.contentReady || (reference.active && (!reference.item || !reference.item.contentReady)))
                return
            if (shell.step === 0) {
                shell.geometry()
                sourcePane.grabToImage(function(result) {
                    shell.check(result.saveToFile(shell.output), "source capture saved")
                    Flea.ViewState.state = { display: { textSize: { mode: 16 } } }
                    reference.active = false
                    shell.step = 1
                })
                shell.step = -1
            } else if (shell.step === 1) {
                // A fresh rendered reference measures initial insets without a previous font's scroll offset.
                reference.active = true
                shell.step = 2
            } else if (shell.step === 2) {
                shell.geometry()
                shell.done = true
                console.log("MARKDOWN_SOURCE " + shell.checks + " checks, " + shell.failures + " failed")
                shell.quit()
            }
        }
    }
    Timer {
        interval: 10000
        running: !shell.done
        onTriggered: {
            console.log("MARKDOWN_SOURCE FAIL watchdog")
            shell.quit()
        }
    }
}
