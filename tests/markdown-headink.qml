//@ pragma ShellId flea-markdown-headink-test

import QtQuick
import Quickshell
import "flea" as Flea

// ui/Theme.qml's own heading ink, applied over palettes where bright_foreground wins, where color15 wins and where neither beats the foreground.
ShellRoot {
    id: shell
    property int checks: 0
    property int failures: 0
    readonly property string dark: 'background = "#1a1b26"\nforeground = "#a9b1d6"\n'
    readonly property string light: 'background = "#eff1f5"\nforeground = "#4c4f69"\n'
    function log(line) { console.log("MARKDOWN_HEADINK " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function inkOf(palette) {
        Flea.Theme.applyColors(palette)
        return String(Flea.Theme.color.foregroundBright)
    }
    function check(palette, want, name) {
        var got = shell.inkOf(palette)
        shell.checks++
        if (got !== want) shell.failures++
        shell.log((got === want ? "CHECK " : "FAIL ") + name + ": want " + want + ", got " + got)
    }
    Component.onCompleted: {
        shell.check(shell.dark, "#a9b1d6", "no bright key keeps the foreground")
        shell.check(shell.dark + 'bright_foreground = "#c0caf5"\n', "#c0caf5", "bright_foreground wins when it has more contrast")
        shell.check(shell.dark + 'bright_foreground = "#445066"\n', "#a9b1d6", "a dimmer bright_foreground keeps the foreground")
        shell.check(shell.dark + 'color15 = "#c0caf5"\n', "#c0caf5", "color15 wins when no bright_foreground is set")
        shell.check(shell.dark + 'color15 = "#445066"\n', "#a9b1d6", "a dimmer color15 keeps the foreground")
        shell.check(shell.dark + 'color15 = "#ffffff"\nbright_foreground = "#c0caf5"\n', "#c0caf5", "bright_foreground is read before color15")
        shell.check(shell.dark + 'color15 = "#ffffff"\nbright_foreground = "#445066"\n', "#a9b1d6", "a dim bright_foreground is not rescued by color15")
        shell.check(shell.light + 'bright_foreground = "#bcc0cc"\n', "#4c4f69", "on a light ground a lighter bright_foreground keeps the foreground")
        shell.check(shell.light + 'bright_foreground = "#11111b"\n', "#11111b", "on a light ground a darker bright_foreground wins")
        shell.log(shell.checks + " checks, " + shell.failures + " failed")
        shell.quit()
    }
}
