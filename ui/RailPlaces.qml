pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "js/Icons.js" as Icons
import "js/Picker.js" as Picker
import "js/Places.js" as Places

// Place data outlives the visible rail, so hiding it cannot remove query destinations.
QtObject {
    id: root
    readonly property var settings: ViewState.state.places || ({})
    property string dirsText: ""
    readonly property var homeEntries: root.settings.showHome === false ? []
        : Places.homeEntries(Quickshell.env("HOME"), root.dirsText, Icons.sidebarGlyphFor)
    readonly property var favouriteEntries: Places.storedEntries(Favourites.records, Quickshell.env("HOME")).map(function (entry) {
        entry.error = entry.error || Favourites.statuses[entry.favouriteIndex] || ""
        return entry
    })
    readonly property var recentEntries: root.settings.showRecent === true
        ? [{ label: Picker.RECENT_LABEL, path: Picker.RECENT, group: "recent", kind: "recent", glyph: "history" }] : []
    readonly property var trashEntries: root.settings.showTrash === false ? []
        : [{ label: "Trash", path: "trash:///", group: "trash", kind: "trash", glyph: "trash" }]
    readonly property var entries: root.homeEntries.slice(0, 1).concat(root.recentEntries,
        root.homeEntries.slice(1), root.trashEntries, root.favouriteEntries)
    property FileView userDirs: FileView {
        id: dirs
        path: Quickshell.env("HOME") + "/.config/user-dirs.dirs"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.dirsText = dirs.text()
        onLoadFailed: root.dirsText = ""
    }
}
