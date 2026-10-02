import QtQuick
import qs.Commons
import "." as Flea
import "js/Buttons.js" as Buttons
import "js/Permissions.js" as Permissions

// One item, one mode; the backend owns its reviewed descriptor for this dialog's lifetime.
FocusScope {
    id: root
    anchors.fill: parent
    visible: opened
    property bool opened: false
    property int requestId: 0
    // Inspect ids are request blocks of this width; a wider selection reserves whole blocks.
    readonly property int inspectStride: 1000
    property int multiBase: 0
    property var facts: ({})
    property string path: ""
    property string modeText: ""
    property string errorText: ""
    property bool busy: false
    property bool transportFailed: false
    property Item focusHolder: null
    // The selection's paths with modes in the same order, the first inspect refusal, and the explicit bits.
    property var multiPaths: []
    // B7: the live inspect accumulation ui/js/Permissions.js noteMode owns,
    // written in place with no notify per reply; multiModes below is the one
    // snapshot the summary binding reads, assigned once at the last reply.
    property var multiStore: ({ modes: [], reasons: [], skipped: [] })
    property var multiModes: []
    property int multiPending: 0
    property int explicitSet: 0
    property int explicitClear: 0
    property bool applyingMany: false
    // B8: the skips the Apply sent (inspect-time skips plus special-bit and
    // read-only items), carried to the applyMany reply for the final message.
    property var multiApplySkipped: []
    property int multiApplySent: 0
    readonly property bool isMulti: multiPaths.length > 1
    readonly property var multiSummary: isMulti ? Permissions.summarize(multiModes) : null
    readonly property bool editable: isMulti ? !busy && !transportFailed
                                              : facts.ok === true && !facts.reason && !busy && !transportFailed
    readonly property int modeValue: Permissions.parse(modeText)
    readonly property bool applying: busy && facts.ok === true
    // Permissions040: a multi Apply cannot be cancelled either.
    readonly property bool applyLocked: applying || applyingMany
    readonly property real labelWidth: Math.round(96 * Theme.font.bodySmall / 13)
    readonly property int controlHeight: Math.max(Theme.rowHeight, Math.ceil(Theme.font.body * Theme.lineBoxRatio) + 2 * Theme.spacing.rowPaddingY)
    readonly property real bodyInset: 16 * Theme.font.bodySmall / 13 + Theme.spacing.hairline
    readonly property int headingHeight: Math.round(26 * Theme.font.bodySmall / 13)
    readonly property var cardItem: card
    readonly property var bodyItem: body
    readonly property string displayedError: errorLabel.text
    readonly property string displayedSummary: changeSummary.text + "\n" + scopeLabel.text
    function controls() {
        var result = [{name: "Close", item: closeMark, enabled: !applying}, {name: "Octal", item: octal, enabled: editable},
            {name: "Cancel", item: cancelFocus, enabled: !applying}, {name: "Apply", item: applyFocus, enabled: editable && modeValue >= 0}]
        for (var row = 0; row < permissionRows.count; row++) {
            var group = permissionRows.itemAt(row)
            for (var column = 0; column < group.checks.count; column++) {
                var checkbox = group.checks.itemAt(column)
                result.push({name: checkbox.Accessible.name, item: checkbox, checked: checkbox.checked, bit: checkbox.bit, enabled: editable})
            }
        }
        return result
    }
    readonly property string scopeText: facts.directory
        ? "Scope this directory only · enclosed items unchanged · ownership unchanged"
        : "Scope this item only · ownership unchanged"
    signal requested(var message)
    signal changed(string note)
    signal closed()

    function open(itemPath, holder) {
        requestId += 1
        multiPaths = []
        multiStore = ({ modes: [], reasons: [], skipped: [] })
        multiModes = []
        multiPending = 0
        multiApplySkipped = []
        multiApplySent = 0
        explicitSet = 0
        explicitClear = 0
        applyingMany = false
        path = itemPath
        focusHolder = holder
        facts = ({})
        modeText = ""
        errorText = ""
        transportFailed = false
        busy = true
        opened = true
        body.contentY = 0
        cancelFocus.forceActiveFocus()
        requested({ c: "permissions", op: "inspect", id: requestId, path: path })
    }
    // One Entry holds every path the Apply changed, so one undo restores them all.
    function openMany(paths, holder) {
        requestId += 1
        multiBase = requestId
        multiPaths = paths.slice()
        multiStore = ({ modes: [], reasons: [], skipped: [], pending: paths.length })
        multiModes = []
        multiPending = paths.length
        multiApplySkipped = []
        multiApplySent = 0
        explicitSet = 0
        explicitClear = 0
        applyingMany = false
        path = ""
        focusHolder = holder
        facts = ({})
        modeText = ""
        errorText = ""
        transportFailed = false
        busy = true
        opened = true
        body.contentY = 0
        cancelFocus.forceActiveFocus()
        for (var i = 0; i < paths.length; i++)
            requested({ c: "permissions", op: "inspect", id: multiBase * inspectStride + i, path: paths[i] })
        // A wider selection reserves whole strides so the next open's block cannot overlap this one.
        requestId += Math.max(0, Math.floor((paths.length - 1) / inspectStride))
    }
    function receive(message) {
        if (isMulti) { receiveMany(message); return }
        if (!opened || transportFailed || message.id !== requestId || message.op === "close") return
        busy = false
        cancelFocus.forceActiveFocus()
        if (!message.ok) { errorText = message.error || "Could not change permissions."; return }
        if (message.op === "apply") { changed(""); close(); return }
        facts = message
        modeText = message.mode
    }
    // The grid over several files; an untouched box takes the explicit opposite of what it shows.
    function multiBit(bit) {
        if (!multiSummary) return { on: false, mixed: false }
        for (var i = 0; i < multiSummary.bits.length; i++) {
            if (multiSummary.bits[i].mask === bit)
                return multiSummary.bits[i]
        }
        return { on: false, mixed: false }
    }
    function multiChecked(bit) {
        if ((explicitSet & bit) !== 0) return true
        if ((explicitClear & bit) !== 0) return false
        return multiBit(bit).on
    }
    function multiValue(bit) {
        if ((explicitSet & bit) !== 0) return "on"
        if ((explicitClear & bit) !== 0) return "off"
        var found = multiBit(bit)
        if (found.mixed) return "some"
        return found.on ? "on" : "off"
    }
    // Only a mixed box cycles set, clear, release; a uniform box flips to its opposite, then lets go.
    function multiToggle(bit) {
        if ((explicitSet & bit) !== 0) {
            explicitSet &= ~bit
            explicitClear |= bit
        } else if ((explicitClear & bit) !== 0) {
            explicitClear &= ~bit
        } else if (multiBit(bit).mixed || !multiBit(bit).on) {
            explicitSet |= bit
            explicitClear &= ~bit
        } else {
            explicitClear |= bit
            explicitSet &= ~bit
        }
    }
    function receiveMany(message) {
        if (!opened || transportFailed) return
        if (message.op === "applyMany") {
            applyingMany = false
            if (message.ok === true) {
                changed(Permissions.multiResult(multiApplySent, multiPaths.length, multiApplySkipped))
                close()
                return
            }
            errorText = message.error || "Could not change permissions."
            if (multiApplySkipped.length > 0)
                errorText += "\n" + Permissions.skipNote(multiApplySkipped)
            // A failed batch re-reads every mode so the grid and a retry start from disk.
            multiStore = ({ modes: [], reasons: [], skipped: [], pending: multiPaths.length })
            multiModes = []
            multiPending = multiPaths.length
            busy = true
            cancelFocus.forceActiveFocus()
            for (var i = 0; i < multiPaths.length; i++)
                requested({ c: "permissions", op: "inspect", id: multiBase * inspectStride + i, path: multiPaths[i] })
            return
        }
        if (message.op !== "inspect") return
        var at = (message.id || 0) - multiBase * inspectStride
        if (at < 0 || at >= multiPaths.length) return
        // Accumulated in place through ui/js/Permissions.js noteMode, which
        // tests/js/permissions.js pins to one summary for the whole selection.
        if (Permissions.noteMode(multiStore, at, multiPaths[at], message)) {
            multiPending = 0
            busy = false
            // One assignment notifies once, so multiSummary summarizes once.
            multiModes = multiStore.modes.slice()
            if (multiStore.skipped.length > 0 && errorText.length === 0) errorText = Permissions.skipNote(multiStore.skipped)
            cancelFocus.forceActiveFocus()
        } else {
            multiPending = multiStore.pending
        }
    }
    function backendFailed(message) {
        if (!opened || transportFailed) return
        // A multi Apply counts as applying with an unknown outcome, and ends so Cancel and close work.
        var applying = (busy && facts.ok === true) || applyingMany
        applyingMany = false
        transportFailed = true
        busy = false
        cancelFocus.forceActiveFocus()
        var reason = message || "the backend stopped"
        errorText = applying
            ? "Permission change outcome is unknown because " + reason + "; restart Flea and reopen Permissions to check the current mode."
            : "Permissions is unavailable because " + reason + "; restart Flea and reopen Permissions."
    }
    function close() {
        // An issued fchmod cannot be cancelled; retain its result before allowing dismissal.
        if (!opened || applying || applyingMany) return
        if (isMulti) {
            for (var i = 0; i < multiPaths.length; i++)
                requested({ c: "permissions", op: "close", id: multiBase * inspectStride + i })
        } else {
            requested({ c: "permissions", op: "close", id: requestId })
        }
        opened = false
        closed()
        if (focusHolder) focusHolder.forceActiveFocus()
    }
    function apply() {
        if (isMulti) { applyMany(); return }
        if (!editable || modeValue < 0) return
        root.forceActiveFocus()
        busy = true
        errorText = ""
        requested({ c: "permissions", op: "apply", id: requestId, mode: modeText })
    }
    // Permissions040: Apply is one undo step for all the files. Each file
    // keeps its own bits except the ones the grid explicitly set or cleared.
    // B8: an item with special bits, a read-only reason or a refused inspect
    // is counted and named rather than silently dropped, and a selection with
    // nothing applicable never reaches the backend's empty-batch refusal.
    function applyMany() {
        if (!editable) return
        root.forceActiveFocus()
        busy = true
        applyingMany = true
        errorText = ""
        // Built fresh from the per-row reasons, which already carry refused
        // inspects from noteMode above: every skip is counted exactly once.
        var skipped = []
        var paths = []
        var modes = []
        for (var i = 0; i < multiPaths.length; i++) {
            var why = multiStore.reasons[i] || ""
            var base = Permissions.parse(multiStore.modes[i])
            if (why.length === 0 && base < 0)
                why = Permissions.specialReason(multiStore.modes[i])
            if (why.length > 0 || base < 0) {
                skipped.push({ path: multiPaths[i],
                    why: why.length > 0 ? why : "Could not change permissions." })
                continue
            }
            var target = (base & ~explicitClear) | explicitSet
            paths.push(multiPaths[i])
            modes.push(Permissions.octal(target))
        }
        if (paths.length === 0) {
            applyingMany = false
            busy = false
            errorText = Permissions.multiResult(0, multiPaths.length, skipped)
            cancelFocus.forceActiveFocus()
            return
        }
        multiApplySkipped = skipped
        multiApplySent = paths.length
        requested({ c: "permissionsBatch", paths: paths, modes: modes, id: requestId })
    }
    function focusItems(item, result) {
        if (!item.visible || !item.enabled) return
        if (item.activeFocusOnTab) result.push(item)
        for (var i = 0; i < item.children.length; i++) focusItems(item.children[i], result)
    }
    function stepFocus(back) {
        var items = []
        focusItems(card, items)
        if (!items.length) return
        var current = -1
        for (var i = 0; i < items.length; i++) if (items[i].activeFocus) current = i
        var next = current < 0 ? (back ? items.length - 1 : 0)
            : (current + (back ? -1 : 1) + items.length) % items.length
        items[next].forceActiveFocus()
        body.reveal(items[next])
    }
    Keys.onTabPressed: function(event) { root.stepFocus((event.modifiers & Qt.ShiftModifier) !== 0); event.accepted = true }
    Keys.onBacktabPressed: function(event) { root.stepFocus(true); event.accepted = true }
    Keys.onPressed: function(event) { event.accepted = true }
    Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
        opacity: 0.5
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.close()
            onWheel: function(wheel) { wheel.accepted = true }
        }
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        // The board's 420 content width shares the Settings board's 560 scale.
        width: Math.max(0, Math.min(Theme.settings.panelWidth * 3 / 4 + 2 * Theme.spacing.hairline, root.width - 2 * Theme.spacing.gap))
        height: Math.max(0, Math.min(chrome.height + body.wanted + Theme.spacing.rowPaddingX + root.bodyInset, root.height - 2 * Theme.spacing.gap))
        color: Theme.color.surface
        border.color: Theme.color.muted
        border.width: Theme.spacing.hairline
        radius: Style.cornerRadius
        clip: true
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onWheel: function(wheel) { wheel.accepted = true }
        }
        Item {
            id: chrome
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Theme.chromeHeight
            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacing.rowPaddingX
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacing.gap
                Flea.Glyph { width: Theme.chromeMarkSize; height: title.height; name: "lock"; color: Theme.color.accent }
                    Text { id: title; text: root.isMulti ? "Permissions for " + root.multiPaths.length + " items" : "Permissions"; color: Theme.color.foreground; textFormat: Text.PlainText; font { family: Theme.font.family; pixelSize: Theme.font.caption; bold: true } }
            }
            // Dialogs rule 7: the way out is named beside the mark that performs it, the settings panel's own corner.
            Flea.EscapeHint {
                anchors.right: closeMark.left
                anchors.rightMargin: Theme.spacing.gap
                anchors.verticalCenter: closeMark.verticalCenter
            }

            Flea.ChromeButton {
                id: closeMark
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacing.rowPaddingX
                anchors.verticalCenter: parent.verticalCenter
                glyph: "x"; gesturePolicy: TapHandler.ReleaseWithinBounds
                // The one chrome control here, so brightness is all it has to say where the keyboard is: muted at rest, foreground under focus.
                restingColor: Theme.color.muted
                enabled: !root.applyLocked
                accessName: "Close permissions"
                activeFocusOnTab: true
                keyboardFocused: activeFocus
                Keys.onTabPressed: function(event) { root.stepFocus((event.modifiers & Qt.ShiftModifier) !== 0) }
                Keys.onBacktabPressed: root.stepFocus(true)
                Keys.onReturnPressed: root.close()
                Keys.onSpacePressed: root.close()
                onActivated: root.close()
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: Theme.spacing.hairline; color: Theme.color.muted; opacity: 0.4 }
        }
        Flea.CardScroll {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: chrome.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: root.bodyInset
            anchors.rightMargin: root.bodyInset
            anchors.topMargin: Theme.spacing.rowPaddingX
            anchors.bottomMargin: root.bodyInset
            Column {
                width: body.width
                spacing: 0
                Row {
                    width: parent.width
                    height: root.controlHeight
                    spacing: Theme.spacing.gap
                    // For several items the grid and Apply are the whole card, so the name row drops out.
                    visible: !root.isMulti
                    Flea.Glyph { width: Theme.markSize; height: nameLabel.height; anchors.verticalCenter: parent.verticalCenter; name: root.facts.directory ? "folder" : "file"; color: Theme.color.muted }
                    Text { id: nameLabel; width: parent.width - Theme.markSize - kindLabel.width - 2 * parent.spacing; anchors.verticalCenter: parent.verticalCenter; text: root.path.split("/").pop(); elide: Text.ElideMiddle; textFormat: Text.PlainText; color: Theme.color.foreground; font { family: Theme.font.family; pixelSize: Theme.font.body } }
                    Text { id: kindLabel; anchors.verticalCenter: parent.verticalCenter; text: root.facts.ok ? (root.facts.directory ? "directory" : "file") : ""; textFormat: Text.PlainText; color: Theme.color.foreground; font { family: Theme.font.family; pixelSize: Theme.font.caption } }
                }
                Rectangle { width: parent.width; height: Theme.spacing.hairline; color: Theme.color.muted; opacity: 0.4 }
                Row {
                    width: parent.width
                    height: root.headingHeight
                    Item { width: root.labelWidth; height: parent.height }
                    Repeater {
                        model: ["READ", "WRITE", root.isMulti || !root.facts.directory ? "EXEC" : "ENTER"]
                        Text { required property string modelData; width: (body.width - root.labelWidth) / 3; height: parent.height; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: modelData; textFormat: Text.PlainText; color: Theme.color.foreground; font { family: Theme.font.family; pixelSize: Theme.font.caption; letterSpacing: Theme.font.caption / 10 } }
                    }
                }
                Repeater {
                    id: permissionRows
                    model: ["Owner", "Group", "Everyone"]
                    Row {
                        id: permissionRow
                        required property string modelData
                        required property int index
                        readonly property alias checks: checks
                        width: body.width
                        height: root.controlHeight
                        Text { width: root.labelWidth; anchors.verticalCenter: parent.verticalCenter; text: permissionRow.modelData; textFormat: Text.PlainText; color: Theme.color.foreground; font { family: Theme.font.family; pixelSize: Theme.font.body } }
                        Repeater {
                            id: checks
                            model: 3
                            FocusScope {
                                id: checkbox
                                required property int index
                                readonly property int bit: 1 << (8 - permissionRow.index * 3 - index)
                                readonly property bool checked: root.isMulti ? root.multiChecked(bit)
                                    : (root.modeValue >= 0 ? root.modeValue : parseInt(root.facts.mode || "0", 8)) & bit
                                width: (body.width - root.labelWidth) / 3
                                height: permissionRow.height
                                activeFocusOnTab: true
                                enabled: root.editable
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: permissionRow.modelData + " " + ["read", "write", root.facts.directory ? "enter" : "execute"][index]
                                Accessible.checked: checked
                                Accessible.onPressAction: toggle()
                                Accessible.onToggleAction: toggle()
                                function toggle() {
                                    if (!root.editable) return
                                    if (root.isMulti) root.multiToggle(bit)
                                    else root.modeText = Permissions.toggle(root.modeText, bit)
                                    forceActiveFocus()
                                }
                                Keys.onSpacePressed: toggle()
                                Keys.onTabPressed: function(event) { root.stepFocus((event.modifiers & Qt.ShiftModifier) !== 0) }
                                Keys.onBacktabPressed: root.stepFocus(true)
                                Flea.CheckBox {
                                    anchors.centerIn: parent
                                    // A bit differing across the files shows a bar until it is clicked.
                                    value: root.isMulti ? root.multiValue(bit) : checkbox.checked ? "on" : "off"
                                    focused: checkbox.activeFocus
                                    // A disabled row stays checked, so the box dims and keeps its value.
                                    available: root.editable
                                }
                                TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: checkbox.toggle() }
                            }
                        }
                    }
                }
                Item {
                    width: parent.width
                    height: Theme.spacing.rowPaddingY + Theme.settings.railPaddingY / 2 + Theme.spacing.hairline
                    Rectangle { y: Theme.settings.railPaddingY / 2; width: parent.width; height: Theme.spacing.hairline; color: Theme.color.muted; opacity: 0.4 }
                }
                Row {
                    width: parent.width
                    height: root.controlHeight
                    spacing: Theme.spacing.gap
                    // Permissions040: for several items Octal drops out.
                    visible: !root.isMulti
                    Text { width: root.labelWidth; anchors.verticalCenter: parent.verticalCenter; text: "Octal"; textFormat: Text.PlainText; color: Theme.color.foreground; font { family: Theme.font.family; pixelSize: Theme.font.body } }
                    Rectangle {
                        width: body.width - root.labelWidth - parent.spacing
                        height: parent.height
                        color: Theme.color.background
                        border.color: Theme.color.muted
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -Buttons.RING
                            color: "transparent"
                            border.width: Buttons.RING
                            border.color: Theme.color.foreground
                            visible: octal.activeFocus
                        }
                        TextInput {
                            id: octal
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacing.gap
                            anchors.rightMargin: Theme.spacing.gap
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.modeText
                            readOnly: !root.editable
                            activeFocusOnTab: !root.isMulti
                            enabled: root.editable && !root.isMulti
                            Accessible.name: "Octal mode"
                            color: root.editable ? Theme.color.foreground : Theme.color.muted
                            font { family: Theme.font.family; pixelSize: Theme.font.body }
                            clip: true
                            selectByMouse: true
                            Keys.onTabPressed: function(event) { root.stepFocus((event.modifiers & Qt.ShiftModifier) !== 0) }
                            Keys.onBacktabPressed: root.stepFocus(true)
                            onTextEdited: root.modeText = text
                            onAccepted: if (root.editable && root.modeValue >= 0) applyFocus.forceActiveFocus()
                        }
                    }
                }
                Repeater {
                    model: ["Owner", "Group"]
                    Row {
                        required property string modelData
                        required property int index
                        // Permissions040: for several items Owner and Group drop out.
                        visible: !root.isMulti
                        width: body.width
                        height: root.controlHeight
                        spacing: Theme.spacing.gap
                        Text { width: root.labelWidth; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData; textFormat: Text.PlainText; color: Theme.color.foreground; font { family: Theme.font.family; pixelSize: Theme.font.body } }
                        Text { width: body.width - root.labelWidth - identity.width - 2 * parent.spacing; anchors.verticalCenter: parent.verticalCenter; text: root.facts.ok ? ((parent.index === 0 ? root.facts.owner : root.facts.group) || "Unknown") + " · read-only" : ""; textFormat: Text.PlainText; elide: Text.ElideRight; color: Theme.color.foreground; font { family: Theme.font.family; pixelSize: Theme.font.body } }
                        Text { id: identity; anchors.verticalCenter: parent.verticalCenter; text: root.facts.ok ? (parent.index === 0 ? "uid " + root.facts.uid : "gid " + root.facts.gid) : ""; textFormat: Text.PlainText; color: Theme.color.foreground; font { family: Theme.font.family; pixelSize: Theme.font.caption } }
                    }
                }
                Rectangle {
                    width: parent.width
                    height: directoryScope.implicitHeight + 2 * Theme.spacing.gap
                    // Permissions040: for several items the scope box drops out.
                    visible: root.facts.directory === true && !root.isMulti
                    color: Theme.color.background
                    border.width: Theme.spacing.hairline
                    border.color: Theme.color.muted
                    Flea.Glyph { id: scopeMark; x: Theme.spacing.gap; y: Theme.spacing.gap; width: Theme.font.bodySmall; height: width; name: "check"; color: Theme.color.accent }
                    Text {
                        id: directoryScope
                        x: scopeMark.x + scopeMark.width + Theme.spacing.gap
                        y: Theme.spacing.gap
                        width: parent.width - x - Theme.spacing.gap
                        text: "Scope: this directory only. Enclosed files and directories keep every bit."
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Theme.color.foreground
                        font { family: Theme.font.family; pixelSize: Theme.font.caption }
                    }
                }
                Text {
                    id: errorLabel
                    width: parent.width
                    visible: text.length > 0
                    topPadding: Theme.spacing.gap
                    text: root.errorText || root.facts.reason || (root.busy
                        ? (root.isMulti ? (root.multiPending > 0 ? "Reading permissions…" : "Applying permissions…")
                                        : (root.facts.ok ? "Applying permissions…" : "Reading permissions…"))
                        : root.facts.ok && root.modeValue < 0 ? "Enter three octal digits or a leading-zero four-digit mode." : "")
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: root.busy ? Theme.color.muted : Theme.color.error
                    font { family: Theme.font.family; pixelSize: Theme.font.caption }
                }
                Item {
                    width: parent.width
                    height: Theme.settings.railPaddingY + Theme.spacing.gap + Theme.spacing.hairline
                    Rectangle { y: Theme.settings.railPaddingY; width: parent.width; height: Theme.spacing.hairline; color: Theme.color.muted; opacity: 0.4 }
                }
                Text {
                    text: "WILL CHANGE"
                    bottomPadding: Theme.spacing.rowPaddingY / 2
                    textFormat: Text.PlainText
                    color: Theme.color.foreground
                    font { family: Theme.font.family; pixelSize: Theme.font.caption; letterSpacing: Theme.font.caption / 10 }
                }
                Text {
                    id: changeSummary
                    width: parent.width
                    // For several items the grid and Apply are the whole card, so the preview drops out.
                    visible: !root.isMulti
                    text: (root.facts.ok && !root.facts.reason && root.modeValue >= 0
                        ? "Requested mode " + Permissions.octal(root.modeValue) : "No changes available")
                        + "\nPath " + root.path.replace(/\//g, "/\u200b")
                        + (root.facts.reason ? "\nCurrent mode " + root.facts.mode : "")
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Theme.color.accent
                    font { family: Theme.font.family; pixelSize: Theme.font.caption }
                }
                Text {
                    id: scopeLabel
                    width: parent.width
                    // A box whose bit differs across the files shows a bar until it is clicked.
                    text: root.isMulti ? Permissions.mixedNote() : root.scopeText
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Theme.color.foreground
                    font { family: Theme.font.family; pixelSize: Theme.font.caption }
                }
                Item { width: parent.width; height: Theme.settings.railPaddingY + Theme.spacing.hairline }
                Row {
                    anchors.right: parent.right
                    spacing: Theme.spacing.gap
                    FocusScope {
                        id: cancelFocus
                        width: cancelButton.implicitWidth; height: cancelButton.implicitHeight
                        activeFocusOnTab: true
                        enabled: !root.applyLocked
                        Keys.onTabPressed: function(event) { root.stepFocus((event.modifiers & Qt.ShiftModifier) !== 0) }
                        Keys.onBacktabPressed: root.stepFocus(true)
                        Keys.onReturnPressed: root.close()
                        Keys.onSpacePressed: root.close()
                        Flea.DialogButton {
                            id: cancelButton
                            label: "Cancel"
                            focused: parent.activeFocus
                            available: !root.applyLocked
                            onActivated: root.close()
                        }
                    }
                    FocusScope {
                        id: applyFocus
                        width: applyButton.implicitWidth; height: applyButton.implicitHeight
                        activeFocusOnTab: true
                        // The multi card has no octal to validate, so Apply enables on the grid alone.
                        enabled: root.isMulti ? root.editable : root.editable && root.modeValue >= 0
                        Keys.onTabPressed: function(event) { root.stepFocus((event.modifiers & Qt.ShiftModifier) !== 0) }
                        Keys.onBacktabPressed: root.stepFocus(true)
                        Keys.onReturnPressed: root.apply()
                        Keys.onSpacePressed: root.apply()
                        Flea.DialogButton {
                            id: applyButton
                            label: "Apply"
                            primary: true
                            focused: parent.activeFocus
                            available: root.isMulti ? root.editable : root.editable && root.modeValue >= 0
                            onActivated: root.apply()
                        }
                    }
                }
            }
        }
    }
}
