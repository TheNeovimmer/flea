.import "../../ui/js/Keymap.js" as Keymap
.import "../../ui/js/Picker.js" as Picker
.import "../../ui/js/Sort.js" as Sort
.import "sourcefixture.js" as Source

// Execute the shipped list handler, grid dispatch and activation function under Qt's JS engine. This tests
// dispatch, including the real preset table; it does not simulate native key delivery or a portal round trip.
function run(check) {
    var handler = Source.slice(Source.source("ui/PickerList.qml"), "Keys.onPressed:",
                               "// The listing is a window").replace(/^Keys.onPressed:\s*/, "").trim()
    var dispatch = Source.slice(Source.source("ui/PickerGrid.qml"), "function handleAction(action, key, modifiers)",
                                "Keys.onPressed:").trim()
    var activate = Source.slice(Source.source("ui/PickerWindow.qml"), "function activate(index)",
                                "// File double clicks").trim()
    var savedPreset = Keymap.preset
    try {
        for (var preset of ["default", "vim", "mac", "windows"]) for (var view of ["list", "grid"]) {
            Keymap.setPreset(preset)
            var label = preset + " " + view
            var row = { n: "file.txt", d: false }
            var win = { cursorIndex: 0, path: "/fixture", marks: ["/fixture/file.txt"],
                accepted: [], opened: [], toggled: [], cancelled: false,
                rowFor: function() { return row },
                accept: function() { this.accepted.push(this.marks.slice()) },
                open: function(path) { this.opened.push(path) },
                toggleMark: function(index) { this.toggled.push(index) },
                cancel: function() { this.cancelled = true } }
            win.activate = new Function("win", "Picker", "return (" + activate + ")")(win, Picker)
            var root = { picker: win, firstArmed: false }
            var press = view === "list"
                ? new Function("root", "Keymap", "Qt", "Sort", "Picker", "return (" + handler + ")")(root, Keymap, Qt, Sort, Picker)
                : gridPress(dispatch, root)
            for (var key of [Qt.Key_Return, Qt.Key_Enter]) {
                for (var mods of [Qt.NoModifier, Qt.KeypadModifier]) {
                    row = { n: "file.txt", d: false }
                    var event = { key: key, text: "\r", modifiers: mods, accepted: false }
                    win.accepted = []; win.opened = []
                    root.firstArmed = true
                    press(event)
                    check(label + " Enter accepts the checked paths", JSON.stringify(win.accepted),
                          JSON.stringify([["/fixture/file.txt"]]))
                    check(label + " Enter consumes the event", event.accepted, true)
                    check(label + " Enter disarms the first-row chord", root.firstArmed, false)
                    row = { n: "folder", d: true }
                    win.accepted = []
                    press(event)
                    check(label + " Enter walks into a directory", win.opened.join(), "/fixture/folder")
                    check(label + " directory navigation submits nothing", win.accepted.length, 0)
                }
            }
            win.accepted = []; win.opened = []; row = null
            press({ key: Qt.Key_Return, text: "\r", modifiers: Qt.NoModifier })
            check(label + " no row means no submission", win.accepted.length, 0)
            row = { n: "file.txt", d: false }
            press({ key: Qt.Key_Space, text: " ", modifiers: Qt.NoModifier })
            check(label + " Space still marks the cursor", win.toggled.join(), "0")
            for (var modifier of [Qt.ControlModifier, Qt.AltModifier, Qt.ShiftModifier, Qt.MetaModifier]) {
                var action = Keymap.lookup(Qt.Key_Return, "\r", modifier, "listing")
                win.accepted = []
                press({ key: Qt.Key_Return, text: "\r", modifiers: modifier })
                check(label + " modified Enter keeps its binding " + modifier, win.accepted.length,
                      action === "open" || action === "pageForward" ? 1 : 0)
            }
            if (preset === "mac") {
                check("Mac listing Enter remains Rename", Keymap.lookup(Qt.Key_Return, "\r", Qt.NoModifier, "listing"), "rename")
                win.accepted = []
                press({ key: Qt.Key_Down, text: "", modifiers: Qt.ControlModifier })
                check("Mac Ctrl+Down still opens in the picker", win.accepted.length, 1)
            }
            press({ key: Qt.Key_Escape, text: "", modifiers: Qt.NoModifier })
            check(label + " Escape still cancels", win.cancelled, true)
        }
    } finally { Keymap.setPreset(savedPreset) }
}

// The grid's Keys.onPressed is the lookup plus handleAction, so this is the same two steps on its own source.
function gridPress(dispatch, root) {
    var handle = new Function("root", "Picker", "Sort", "Qt", "return (" + dispatch + ")")(root, Picker, Sort, Qt)
    return function (event) {
        event.accepted = handle(Keymap.lookup(event.key, event.text, event.modifiers, "listing"), event.key, event.modifiers)
    }
}
