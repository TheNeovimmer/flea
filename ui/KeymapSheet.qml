import QtQuick
import qs.Commons
import "." as Flea
import "js/Keymap.js" as Keymap
import "js/Menu.js" as Menu
import "js/Mounts.js" as Mounts
import "js/SheetQuery.js" as SheetQuery

// The keymap sheet ? opens, drawn as the Keys panel on Operations.dc.html draws it. Every row comes
// from keys.toml through Keymap.sheetFor, so a key that loses its binding cannot go on being advertised.
Item {
    id: root

    property bool opened: false
    property Item focusHolder: null
    // The query field appears on the first typed key, never as a permanent field: the sheet at
    // rest stays the generated sheet it always was. An exact place name ranks first, above actions.
    property string query: ""
    // The history read once when the query line opens, never per keystroke, bounded by
    // Recent.LIMIT with no per-entry stat, listed whether or not the Recent rail row is on.
    property var recentPaths: []
    property bool recentAsked: false
    // The cursor sits on the first row, the menu lift, and arrows move it.
    property int resultCursor: 0
    onQueryChanged: root.resultCursor = 0
    readonly property var sheet: {
        var rows = Keymap.sheetFor(ViewState.keysPreset, "gui", root.focusHolder ? root.focusHolder.dualMode : false)
        if (root.query.length === 0)
            return rows
        return SheetQuery.rank(SheetQuery.actionCandidates(rows), root.query).map(function (c) { return c })
    }
    // The query results across actions, the cursor row's menu, places and recent files, bounded.
    readonly property var queryResults: {
        if (root.query.length === 0 || !root.focusHolder)
            return []
        var holder = root.focusHolder
        var rows = Keymap.sheetFor(ViewState.keysPreset, "gui", holder.dualMode)
        var actions = SheetQuery.actionCandidates(rows)
        var menus = SheetQuery.menuCandidates(root.menuModel(), function (a) { return Keymap.hintFor(a) })
        var places = SheetQuery.placeCandidates(root.railModel())
        var recents = SheetQuery.recentCandidates(root.recentPaths, holder.home)
        return SheetQuery.rank(actions.concat(menus, places, recents), root.query)
    }
    // The cursor row's menu rows from the menu's own model, hidden rows included, so the sheet
    // still finds a row Settings Menus hides. Disabled state rides along and never runs.
    function menuModel() {
        var holder = root.focusHolder
        if (!holder || !holder.cursorRow)
            return []
        var m = holder.contextMenu ? holder.contextMenu() : null
        var p = {
            showHidden: holder.showHidden, hasRow: true,
            rowInDropbox: m ? m.rowInDropbox : false, dropboxPath: m ? m.dropboxPath : "",
            dropboxInstalled: m ? m.dropboxInstalled : false, dropboxReason: m ? m.dropboxReason : "",
            taildropPeers: [], taildropInstalled: false, taildropReason: "",
            taildropRefreshing: false, dropboxRefreshing: false,
            archiveFormats: m ? m.archiveFormats : [], rowIsArchive: m ? m.rowIsArchive : false,
            rowIsImage: m ? m.rowIsImage : false, canConvert: m ? m.canConvert : false,
            canExtract: m ? m.canExtract : false,
            clipboardAvailable: holder.clipboard && holder.clipboard.paths.length > 0,
            canTrash: Mounts.trashable(holder.path, holder.backend ? holder.backend.dirWritable !== false : true),
            openWithApps: [], openWithLoaded: false,
            rowMode: 0, selectionCount: 1, scripts: [], localSendInstalled: false,
            localSendPeers: [], localSendChecking: false, hiddenActions: [],
            storageClass: m ? m.storageClass : "", thumbPreview: ViewState.preview,
            updateVersion: "", hasFolderSort: m ? m.hasFolderSort : false,
            // MenuAdditions040 callout 10: the sheet lists the cursor row's menu rows the way the
            // menu does, so it reads the same two-byte shebang flag the menu's own open read.
            hasShebang: holder.rowHasShebang === true,
            cursorIsTarget: false,
        }
        var sel = holder.permissionSelection()
        if (sel)
            p.rowMode = sel.p
        p.selectionCount = holder.selectionCount()
        p.cursorIsTarget = holder.isSingleCursorTarget() === true
        return Menu.listingEntries(p)
    }
    function railModel() {
        var holder = root.focusHolder
        var bar = holder ? holder.sidebar : null
        return bar ? bar.entries : []
    }
    function ensureRecent() {
        if (root.recentAsked)
            return
        root.recentAsked = true
        recentLoader.active = true
    }
    // Enter runs the highlighted row the way its own surface would.
    function activateResult() {
        var pick = root.queryResults[root.resultCursor]
        if (!pick)
            return
        var decided = SheetQuery.dispatch(pick)
        var holder = root.focusHolder
        if (!holder || decided.kind === "disabled" || decided.kind === "none")
            return
        if (decided.kind === "action") {
            SheetQuery.runAction(holder, decided.action, function () { root.close() })
            return
        }
        if (decided.kind === "menu" || decided.kind === "confirm") {
            SheetQuery.runMenu(holder, decided.menuAction, function () { root.close() })
            return
        }
        if (decided.kind === "place") {
            var at = SheetQuery.placeIndex(holder.sidebar ? holder.sidebar.entries : [], decided)
            root.close()
            if (at >= 0)
                holder.sidebar.activate(at)
            return
        }
        if (decided.kind === "recent") {
            root.close()
            holder.openFile(decided.path)
            return
        }
    }
    // Directive 18's footprint: the four blocks flow into two columns of equal length rather than a
    // 2x2 grid, which paid twice for the taller block of each pair and grew the card to the screen.
    readonly property var columnSlots: {
        var flat = []
        for (var g = 0; g < root.groups.length; g++) {
            flat.push({ heading: root.groups[g].title, row: null })
            for (var i = 0; i < root.groups[g].rows.length; i++)
                flat.push({ heading: "", row: root.groups[g].rows[i] })
        }
        if (root.columns === 1)
            return [flat]
        var half = Math.ceil(flat.length / 2)
        // The fold prefers a group's own boundary, which costs at most one row of imbalance here.
        for (var b = half - 1; b <= half + 1; b++)
            if (b > 0 && b < flat.length && flat[b].heading.length > 0)
                return [flat.slice(0, b), flat.slice(b)]
        // It cannot always: a group longer than a column has to break inside itself, and then the
        // continuation names it again, so no row on this sheet ever sits under no heading at all.
        var owner = ""
        for (var k = half - 1; k >= 0; k--)
            if (flat[k].heading.length > 0) {
                owner = flat[k].heading
                break
            }
        var tail = flat.slice(half)
        if (owner.length > 0)
            tail = [{ heading: owner, row: null }].concat(tail)
        return [flat.slice(0, half), tail]
    }

    // KeymapSheet rule 1: a binding gets a group in keys.toml and the sheet reads it, in the order
    // that table lists them, with the heading its own key carries under a raised first letter.
    readonly property var groups: {
        var out = []
        for (var name in Keymap.SHEET_GROUPS) {
            var order = Keymap.SHEET_GROUPS[name], claimed = []
            // The group's own list is the order the board draws, cursor keys before the chords;
            // the generated sheet is in keys.toml's file order, which puts every preset row first.
            for (var i = 0; i < order.length; i++) {
                var row = root.sheet.filter(function (candidate) { return candidate.action === order[i] })
                if (row.length > 0)
                    claimed.push(row[0])
            }
            if (claimed.length > 0)
                out.push({ title: name.charAt(0).toUpperCase() + name.slice(1), rows: claimed })
        }
        return out
    }

    // The canvas drew this panel at 300, the convert popup's width, beside four illustrative rows.
    // The real sheet is sixty rows whose chords run to eighteen characters: at 300 a cap took the
    // whole half-cell, the wording beside it elided to a single ellipsis, and the two columns
    // overprinted each other. 480 is the Open with card's own anchor and leaves both room.
    readonly property int sheetWidth: 480
    readonly property int clampMargin: 8
    // var, not Item: BorderSurface is a qs.Ui type qmllint cannot resolve, and Item would read as incompatible.
    readonly property var cardItem: card
    // A cap is sized from the type scale, never from the text inside it, so every cap is one height.
    readonly property int capSize: Theme.markSize
    // The 0.2.1 sheet's own row, which directive 18 makes the ceiling: the cap with one row padding
    // under it. The board draws 32 around a 19 cap, but its pane holds 36 rows and this one holds 56.
    readonly property int rowPitch: root.capSize + Theme.spacing.rowPaddingY
    // A heading carries no cap box, so it takes the cap's own height rather than a whole row's.
    readonly property int headingPitch: root.capSize
    readonly property int capGap: Theme.spacing.gap

    // One cap column for the whole sheet, measured off the widest chord this preset spells. Sizing
    // each cap to its own text left every wording starting on a different x, and a wide chord took
    // the cell whole and drew across the column beside it.
    readonly property string widestCap: {
        var out = ""
        for (var i = 0; i < root.sheet.length; i++)
            if (root.sheet[i].keys.length > out.length) out = root.sheet[i].keys
        return out
    }
    readonly property int capWidth: Math.max(root.capSize, Math.ceil(capMetrics.width) + root.capGap)
    // Board rule 4: no label is ever cut, so the floor is the widest wording this preset really
    // draws. A window that cannot give two cells that much takes one column and scrolls instead.
    readonly property string widestLabel: {
        var out = ""
        for (var i = 0; i < root.sheet.length; i++)
            if (root.sheet[i].label.length > out.length) out = root.sheet[i].label
        return out
    }
    readonly property int cellFloor: root.capWidth + root.capGap + Math.ceil(labelFloor.width)
    // Two columns is what the canvas draws, and what keeps the whole map on one panel where it fits.
    readonly property int columns: body.width >= 2 * root.cellFloor + Theme.spacing.rowPaddingX ? 2 : 1

    TextMetrics {
        id: capMetrics
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        text: root.widestCap
    }

    TextMetrics {
        id: labelFloor
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        text: root.widestLabel
    }
    readonly property real groundOpacity: 0.5

    anchors.fill: parent
    visible: root.opened
    z: 2

    function open(holder) {
        root.focusHolder = holder
        root.query = ""
        root.recentPaths = []
        root.recentAsked = false
        root.resultCursor = 0
        recentLoader.active = false
        // MenuAdditions040 callout 10: one two-byte read for the cursor row, so Make executable reads as the menu shows.
        holder.checkShebang()
        root.opened = true
        keys.forceActiveFocus()
    }
    Loader {
        id: recentLoader
        active: false
        source: "PickerRecent.qml"
        onLoaded: item.refresh()
    }
    Connections {
        target: recentLoader.item
        function onRefreshed() { root.recentPaths = recentLoader.item.paths }
    }

    function close() {
        if (!root.opened)
            return
        root.opened = false
        if (root.focusHolder)
            root.focusHolder.forceActiveFocus()
    }

    // What a test reads instead of running OCR over the panel, the same idiom ui/Pane.qml's
    // menuEntries() uses: one row per line, the cap and the wording it is drawn beside.
    function rows() {
        var out = []
        for (var g = 0; g < root.groups.length; g++) {
            out.push(root.groups[g].title)
            for (var i = 0; i < root.groups[g].rows.length; i++)
                out.push(root.groups[g].rows[i].keys + " " + root.groups[g].rows[i].label)
        }
        return out.join("\n")
    }

    // A dimmed ground, and a click on it closes, the same shape ui/ConvertDialog.qml uses.
    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
        opacity: root.groundOpacity

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            onClicked: root.close()
            onWheel: function (wheel) { wheel.accepted = true }
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.max(0, Math.min(Theme.space(root.sheetWidth) * Theme.dialogWidthRatio, root.width - 2 * root.clampMargin))
        // Clamped to the window; the body scrolls whatever the clamp cut, see ui/CardScroll.qml.
        height: Math.min(body.wanted + 2 * Theme.spacing.rowPaddingX, root.height - 2 * root.clampMargin)
        color: Theme.color.surface
        border.width: Theme.spacing.hairline
        border.color: Theme.color.muted
        // Mirrors hyprland decoration:rounding, same as ui/ConvertDialog.qml; 0 on a stock box stays square.
        radius: Style.cornerRadius

        Flea.CardScroll {
            id: body
            anchors.fill: parent
            anchors.margins: Theme.spacing.rowPaddingX

        Column {
            width: parent.width
            spacing: Theme.spacing.gap

            // Rule 2: the one clause a reader needs, in the corner every other surface puts it in.
            Item {
                width: parent.width
                height: title.implicitHeight

                Text {
                    id: title
                    anchors.left: parent.left
                    text: "Keys"
                    color: Theme.color.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.bodySmall
                    textFormat: Text.PlainText
                }

                Text {
                    anchors.right: parent.right
                    anchors.baseline: title.baseline
                    text: root.query.length > 0 ? "esc clears" : "esc closes"
                    color: Theme.color.muted
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.caption
                    textFormat: Text.PlainText
                }
            }

            // The query the typed keys narrowed the sheet to, drawn only while one stands: at rest
            // the card holds the title and the rows and nothing else.
            Item {
                width: parent.width
                height: queryLine.visible ? queryLine.implicitHeight : 0
                visible: root.query.length > 0

                Text {
                    id: queryLine
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: root.query.length > 0
                    text: root.query
                    color: Theme.color.foreground
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.caption
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }
            }

            // The query results replace the key grid, one row per match with the run washed.
            Column {
                width: parent.width
                visible: root.query.length > 0
                Repeater {
                    model: root.queryResults
                    delegate: Item {
                        id: hit
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: root.rowPitch
                        clip: true
                        Rectangle {
                            anchors.fill: parent
                            visible: hit.index === root.resultCursor
                            color: Qt.alpha(Theme.color.foreground, Theme.washHover)
                        }
                        Rectangle {
                            id: hitCap
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.capWidth
                            height: root.capSize
                            color: "transparent"
                            border.width: hit.modelData.keys.length > 0 ? Theme.spacing.hairline : 0
                            border.color: Theme.color.muted
                            Text {
                                anchors.fill: parent
                                anchors.margins: Theme.spacing.hairline
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: hit.modelData.keys
                                color: hit.modelData.disabled === true ? Theme.color.muted : Theme.color.foreground
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.caption
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                            }
                        }
                        Flea.MatchText {
                            id: hitLabel
                            anchors.left: hitCap.right
                            anchors.leftMargin: root.capGap
                            anchors.right: hitWhere.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: hit.modelData.label
                            color: hit.modelData.disabled === true ? Theme.color.muted : Theme.color.foreground
                            pixelSize: Theme.font.caption
                            matchStart: SheetQuery.matchOf(hit.modelData.label, root.query) ? SheetQuery.matchOf(hit.modelData.label, root.query).start : -1
                            matchLength: SheetQuery.matchOf(hit.modelData.label, root.query) ? SheetQuery.matchOf(hit.modelData.label, root.query).length : 0
                        }
                        Text {
                            id: hitWhere
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: String(hit.modelData.where || "").length > 0
                            text: String(hit.modelData.where || "").length > 0 ? "in " + hit.modelData.where : ""
                            color: Theme.color.muted
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.caption
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                        }
                    }
                }
            }
            Row {
                visible: root.query.length === 0
                spacing: Theme.spacing.rowPaddingX

                Repeater {
                    model: root.columnSlots

                    // Equal halves, so the second column starts on one x the whole way down.
                    delegate: Column {
                        id: block
                        required property var modelData
                        width: (body.width - (root.columns - 1) * Theme.spacing.rowPaddingX) / root.columns

                        Repeater {
                            model: block.modelData

                            delegate: Item {
                                id: slot
                                required property var modelData
                                width: block.width
                                height: slot.modelData.heading.length > 0 ? root.headingPitch : root.rowPitch
                                // Nothing this cell draws may reach the cell beside it, whatever it holds.
                                clip: true

                                // A heading takes a row's own slot, so both columns keep one rhythm.
                                Text {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: Theme.spacing.hairline * 2
                                    visible: slot.modelData.heading.length > 0
                                    text: slot.modelData.heading
                                    color: Theme.color.muted
                                    font.family: Theme.font.family
                                    font.pixelSize: Theme.font.caption
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: Theme.spacing.hairline
                                    textFormat: Text.PlainText
                                }

                                Rectangle {
                                    id: capBox
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: slot.modelData.row !== null
                                    // The sheet's own cap column, never this row's text: see root.capWidth.
                                    width: root.capWidth
                                    height: root.capSize
                                    color: "transparent"
                                    border.width: Theme.spacing.hairline
                                    border.color: Theme.color.muted

                                    Text {
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacing.hairline
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: slot.modelData.row ? slot.modelData.row.keys : ""
                                        color: Theme.color.foreground
                                        font.family: Theme.font.family
                                        font.pixelSize: Theme.font.caption
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    anchors.left: capBox.right
                                    anchors.leftMargin: root.capGap
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: slot.modelData.row !== null
                                    text: slot.modelData.row ? slot.modelData.row.label : ""
                                    // The wording is the sheet's own running text, so it takes the
                                    // foreground the board draws it in; muted is for the headings.
                                    color: Theme.color.foreground
                                    font.family: Theme.font.family
                                    font.pixelSize: Theme.font.caption
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        // Esc clears a standing query before it closes; every other key answers through SheetQuery.sheetKey.
        Keys.onPressed: function (event) {
            var decision = SheetQuery.sheetKey(root.query, root.queryResults.length, root.resultCursor, event.key, event.text)
            if (decision === "clear") { root.query = "" }
            else if (decision === "up" || decision === "down") {
                root.resultCursor = SheetQuery.stepCursor(root.resultCursor, decision === "up" ? -1 : 1, root.queryResults.length)
            }
            else if (decision === "activate") { root.activateResult() }
            else if (decision === "backspace") { root.query = root.query.substring(0, root.query.length - 1) }
            else if (decision === "type") {
                if (root.query.length === 0)
                    root.ensureRecent()
                root.query += event.text
            }
            else if (decision === "ignore") { event.accepted = true; return }
            else { root.close() }
            event.accepted = true
        }
    }
}
