//@ pragma ShellId flea-bootload-test

import QtQuick
import Quickshell

// xw6r3: load every ui/boot/ file as the shell does; compile entries and instantiate Loader components with no props.
ShellRoot {
    id: root

    property var failures: []
    // Grace before the check, so the shell finishes starting first; a fixed pause, not a measured load time.
    readonly property int checkDelayMs: 800

    // A holder, so instantiated Items parent to an Item and open no window.
    Item { id: holder }

    function fail(text) { root.failures.push(text) }

    // Sample input: "ui/Pane.qml ui/Tabs.qml".
    function names(raw) {
        var out = []
        var cur = ""
        var s = String(raw) + " "
        for (var i = 0; i < s.length; i++) {
            if (s[i] === " ") {
                if (cur !== "") out.push(cur)
                cur = ""
            } else {
                cur += s[i]
            }
        }
        return out
    }

    function isEntry(name, entries) { return entries.indexOf(name) >= 0 }

    // Offscreen has no PanelWindow backend, so a non-class failure is a note, never a verdict.
    function isClass(text) { return /is not a type|Required property|Cannot assign to non-existent|Failed to load|unavailable/.test(String(text)) }

    // Only the missing offscreen PanelWindow backend is an allowed compile artifact.
    function isArtifact(text) { return String(text).indexOf("No PanelWindow backend loaded") >= 0 }

    function checkOne(name, entries) {
        var comp = Qt.createComponent("file://" + Quickshell.shellDir + "/boot/" + name)
        if (comp.status !== Component.Ready) {
            var cerr = comp.errorString().split("\n").join(" | ")
            if (root.isArtifact(cerr)) console.log("BOOTLOAD NOTE " + name + ": " + cerr)
            else root.fail(name + ": " + cerr)
            return
        }
        if (root.isEntry(name, entries)) return
        // No props, the state before a Loader's onLoaded assigns; a required prop fails here.
        var obj = comp.createObject(holder, {})
        if (obj === null) {
            var err = comp.errorString().split("\n").join(" | ")
            console.log("BOOTLOAD DIAG " + name + " class=" + (root.isClass(err) ? 1 : 0))
            // The pinned offscreen artifact first, so its verdict never depends on the class match.
            if (err.indexOf("No PanelWindow backend loaded") >= 0)
                console.log("BOOTLOAD NOTE " + name + ": " + err)
            else if (root.isClass(err)) root.fail(name + ": " + err)
            else console.log("BOOTLOAD NOTE " + name + ": " + err)
        }
    }

    Timer {
        interval: root.checkDelayMs
        running: true
        repeat: false
        onTriggered: root.check()
    }

    function check() {
        try {
            var files = root.names(Quickshell.env("FLEA_BOOTLOAD_FILES"))
            // An empty derivation passes vacuously, so it fails instead.
            if (files.length === 0) root.fail("FLEA_BOOTLOAD_FILES is empty")
            var entries = root.names(Quickshell.env("FLEA_BOOTLOAD_ENTRIES"))
            for (var i = 0; i < files.length; i++) root.checkOne(files[i], entries)
        } catch (e) {
            root.fail("check threw " + e)
        }
        root.report(files)
    }

    function report(files) {
        for (var f = 0; f < root.failures.length; f++)
            console.log("BOOTLOAD FAIL " + root.failures[f])
        if (root.failures.length === 0)
            console.log("BOOTLOAD PASS files=" + files.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
