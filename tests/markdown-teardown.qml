//@ pragma ShellId flea-markdown-teardown-test
import QtQuick
import Quickshell
import "flea" as Flea

// A Loader built as PreviewColumn builds its Markdown one, switched off and on at every pace, over a document whose blocks the list builds ahead.
ShellRoot {
    id: shell

    function log(line) { console.log("MARKDOWN_TEARDOWN " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    readonly property string fixture: Quickshell.env("FLEA_TEARDOWN_DOC")
    // Each round holds the Loader on for one to holdSpread timer ticks, so the switch-off lands at every stage of the build.
    readonly property int rounds: 300
    readonly property int holdSpread: 9
    // The Loader stays off this many ticks between rounds.
    readonly property int offTicks: 2
    // The test gives up on its own verdict after this long, so a hung stage fails and the run ends.
    readonly property int watchdogMs: 50000
    property bool on: false
    property int round: 0
    property int ticks: 0

    // The board's text size and palette, so the blocks lay out as they do on the card.
    readonly property string palette: 'background = "#1a1b26"\nforeground = "#a9b1d6"\nbright_foreground = "#c0caf5"\n'
    Component.onCompleted: {
        Flea.ViewState.state = { display: { textSize: { mode: 14 } } }
        Flea.Theme.applyColors(shell.palette)
    }

    FloatingWindow {
        implicitWidth: 500
        implicitHeight: 900
        color: "#101315"

        Loader {
            anchors.fill: parent
            active: shell.on
            source: "flea/PreviewMarkdown.qml"
            onLoaded: {
                item.path = shell.fixture
                item.size = 1
                item.active = Qt.binding(function () { return shell.on })
                item.compact = true
            }
        }
    }

    // A tick is a Timer turn, so the pace is a count of turns and nothing is asserted on a duration.
    Timer {
        interval: 1
        running: true
        repeat: true
        onTriggered: {
            shell.ticks++
            if (shell.round >= shell.rounds) {
                shell.log(shell.rounds + " rounds")
                shell.quit()
                return
            }
            if (shell.ticks >= (shell.on ? 1 + shell.round % shell.holdSpread : shell.offTicks)) {
                shell.ticks = 0
                if (shell.on)
                    shell.round++
                shell.on = !shell.on
            }
        }
    }

    Timer {
        interval: shell.watchdogMs
        running: true
        onTriggered: {
            shell.log("FAIL the watchdog outlived the rounds at " + shell.round)
            shell.quit()
        }
    }
}
