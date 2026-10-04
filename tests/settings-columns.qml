//@ pragma ShellId flea-settings-columns-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Settings.js" as Settings
import "flea/js/TextSize.js" as TextSize

// Every row each settings section builds, drawn by the real ui/SettingsRow.qml: columns, hint bands and caption baselines against the boards at text size 14, driven by tests/settings-columns.sh.
ShellRoot {
    id: root

    // A state every section's rows() accepts; no value in it moves a column, only which rows exist.
    readonly property var probeState: ({ data: { startIn: "last" }, home: "/probe", favouriteStatuses: {}, pins: [], selectedFavourite: "",
        about: {}, saveStatus: "", textSize: TextSize.follow(), hidden: [], keyHints: false, preset: "default",
        baseSize: 14, monitorScale: 1, cornerRadius: 8, presetKeys: {} })

    // The size the boards are drawn at, GM's own, which Omarchy's stock 12 is not.
    readonly property int boardTextSize: 14
    // Tabs040.html data-flea="hint": padding 4px 14px 2px 42px, 12px type, line-height 1.5, so 4 + 18 + 2 and one 18 px line.
    readonly property int boardHintTop: 4
    readonly property int boardHintLine: 18
    readonly property int boardHintBottom: 2
    // Chromium on Tabs040.html puts the first hint's baseline 17 px below its band top (ink rows 801..809 of Tabs040.png, band top 793), so its text box starts 17 - 12 = 5 px down.
    readonly property int boardHintBaseline: 17
    readonly property int boardHintTextTop: 5
    // ClickAndRefresh F7 at text size 14: a caption's baseline is 1 px above its label's.
    readonly property int boardCaptionRise: -1
    // KeyboardFlows board, "View, Cursor at defaults", measured at 3x in ClickAndRefresh F7: the "Wrap at list ends" ink spans rows 1406..1419 and its caption's rows 1407..1417.
    readonly property int boardLabelTop: 1406
    readonly property int boardLabelBottom: 1419
    readonly property int boardCaptionTop: 1407
    readonly property int boardCaptionBottom: 1417

    // The footer line's band at 14 with the pinned font, measured on 585c9a5c before the hint band moved.
    readonly property int footerBand: 49
    readonly property int footerTop: 21

    FontMetrics { id: bodyMetrics; font.family: Flea.Theme.font.family; font.pixelSize: Flea.Theme.font.body }
    FontMetrics { id: captionMetrics; font.family: Flea.Theme.font.family; font.pixelSize: Flea.Theme.font.caption }

    Item {
        id: holder
        width: Flea.Theme.settings.paneWidth
    }

    Component {
        id: rowComponent
        Flea.SettingsRow {}
    }

    // The x a row's text starts at: its label, a hint's own line, or the ruler; null when nothing drawn matches.
    function textX(item, row) {
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i]
            if (!child.visible)
                continue
            if (row.kind === "ruler" ? child.stops !== undefined : child.text === row.label)
                return child.x
        }
        return null
    }

    // The visible Text drawing exactly this string under an item, depth first; null when none does.
    function findText(item, text) {
        if (!item.visible)
            return null
        if (item.text === text && item.elide !== undefined)
            return item
        for (var i = 0; i < item.children.length; i++) {
            var found = root.findText(item.children[i], text)
            if (found !== null)
                return found
        }
        return null
    }

    // A Text's own y in the row it sits in, whatever it is nested in.
    function yIn(item, text) {
        var y = 0
        for (var at = text; at !== item; at = at.parent)
            y += at.y
        return y
    }

    // The whole pixel row a Text's baseline is drawn on.
    function baselineIn(item, text) {
        return Math.round(root.yIn(item, text) + text.baselineOffset)
    }

    function measure() {
        var out = { label: [], hint: [], ruler: [], footer: [], bands: [], captions: [], failures: [] }
        var sections = Settings.SECTIONS.map(function (section) { return section.id }).concat(["columns"])
        for (var s = 0; s < sections.length; s++) {
            var rows = []
            try {
                rows = Settings.rows(sections[s], root.probeState)
            } catch (error) {
                out.failures.push(sections[s] + " built no rows: " + error)
            }
            for (var r = 0; r < rows.length; r++) {
                var row = rows[r]
                var item = rowComponent.createObject(holder, { row: row, width: holder.width })
                var kind = row.kind === "hint" ? (row.footer === true ? "footer" : "hint")
                         : row.kind === "ruler" ? "ruler" : item.isGroup || item.isHero || item.isFavourite || item.isKeyPreview ? "" : "label"
                if (kind !== "")
                    out[kind].push({ at: sections[s] + ": " + (row.label || row.id), x: root.textX(item, row) })
                if (kind === "hint" || kind === "footer") {
                    var line = root.findText(item, row.label)
                    if (line === null)
                        out.failures.push(sections[s] + ": " + row.label + " draws no visible Text for its hint " + JSON.stringify(row.label))
                    else
                        out.bands.push({ at: sections[s] + ": " + row.label, footer: kind === "footer", height: item.height,
                                         y: line.y, lineHeight: line.height, lines: line.lineCount, baseline: root.baselineIn(item, line) })
                }
                if (kind === "label" && row.caption !== undefined) {
                    var label = root.findText(item, row.label)
                    var caption = root.findText(item, row.caption)
                    if (label === null || caption === null)
                        out.failures.push(sections[s] + ": " + row.label + " draws no visible Text for its " + (label === null ? "label " + JSON.stringify(row.label) : "caption " + JSON.stringify(row.caption)))
                    else
                        out.captions.push({ at: sections[s] + ": " + row.label, text: row.label, captionText: row.caption,
                                            label: root.baselineIn(item, label), caption: root.baselineIn(item, caption) })
                }
                item.destroy()
            }
        }
        return out
    }

    // Every hint draws the board's literal band, 4 + 18 per wrapped line + 2, its first baseline on the board's row and its text box 5 down, never a figure derived from the product.
    function checkBands(found, failures) {
        var plain = found.bands.filter(function (band) { return !band.footer })
        var footer = found.bands.filter(function (band) { return band.footer })
        for (var i = 0; i < plain.length; i++) {
            var band = plain[i]
            var want = root.boardHintTop + band.lines * root.boardHintLine + root.boardHintBottom
            if (band.baseline !== root.boardHintBaseline)
                failures.push(band.at + " draws its baseline on row " + band.baseline + ", the board's line puts it on " + root.boardHintBaseline)
            if (band.height !== want || band.y !== root.boardHintTextTop || band.lineHeight !== band.lines * root.boardHintLine)
                failures.push(band.at + " is a " + band.height + " px band with its text at " + band.y + " and " + band.lineHeight
                              + " tall, the board draws " + want + " with the text at " + root.boardHintTextTop + " and " + band.lines * root.boardHintLine + " tall")
        }
        // The pane's footer line is not a board hint: its 49 px band is what 585c9a5c measured at this font, and it stays put.
        for (var f = 0; f < footer.length; f++) {
            if (footer[f].height !== root.footerBand || footer[f].y !== root.footerTop)
                failures.push(footer[f].at + " footer band is " + footer[f].height + " with its text at " + footer[f].y + ", not " + root.footerBand + " and " + root.footerTop)
        }
        if (plain.length === 0 || footer.length === 0 || !plain.some(function (band) { return band.at.indexOf("Last folder reopens") >= 0 }))
            failures.push("nothing to compare: " + plain.length + " hints, " + footer.length + " footers, and the Tabs040 sentence among them is "
                          + plain.some(function (band) { return band.at.indexOf("Last folder reopens") >= 0 }))
    }

    // The board centres a caption's glyphs in the row beside the label's, so the baseline gap follows the two fonts' ink, never the product's own formula.
    function checkCaptions(found, failures) {
        var label = bodyMetrics.tightBoundingRect("Wrap at list ends")
        var caption = captionMetrics.tightBoundingRect("arrow-up at the top")
        var gap = (root.boardCaptionTop - root.boardLabelTop) - (caption.y - label.y)
        var bottomGap = (root.boardLabelBottom - root.boardCaptionBottom) - ((label.y + label.height) - (gap + caption.y + caption.height))
        if (gap !== root.boardCaptionRise)
            failures.push("the fonts' ink puts a caption baseline " + gap + " px from its label's, the board's is " + root.boardCaptionRise)
        if (bottomGap !== 0)
            failures.push("the fonts' ink disagrees with the board's own bottoms by " + bottomGap + " px, so the baseline gap " + gap + " proves nothing")
        var wrap = found.captions.filter(function (entry) { return entry.text === "Wrap at list ends" })
        if (wrap.length !== 1 || found.captions.length < 3)
            failures.push("nothing to compare: " + found.captions.length + " captioned rows, " + wrap.length + " Wrap at list ends")
        for (var i = 0; i < found.captions.length; i++) {
            var entry = found.captions[i]
            if (entry.caption - entry.label !== root.boardCaptionRise)
                failures.push(entry.at + " caption baseline is " + (entry.caption - entry.label) + " px from its label's, the board's is " + root.boardCaptionRise)
        }
    }

    // Every visible Text under an item, depth first; a favourite row's path is one of them.
    function visibleTexts(item, out) {
        if (!item.visible)
            return out
        if (item.text !== undefined && item.elide !== undefined)
            out.push(item.text)
        for (var i = 0; i < item.children.length; i++)
            root.visibleTexts(item.children[i], out)
        return out
    }

    // Sidebar040: a favourite's drawn path is home-relative with "~/", and the row keeps the stored absolute path.
    function favouritePaths() {
        var state = Object.assign({}, root.probeState, { data: { places: { favourites: [
            { label: "Projects", path: "/probe/Projects" }, { label: "Archive", path: "/srv/archive" }] } } })
        var rows = Settings.rows("places", state).filter(function (row) { return row.kind === "favourite" })
        var out = { drawn: [], values: rows.map(function (row) { return row.value }) }
        for (var i = 0; i < rows.length; i++) {
            var item = rowComponent.createObject(holder, { row: rows[i], width: holder.width })
            out.drawn.push(root.visibleTexts(item, []).filter(function (text) { return text.indexOf("/") >= 0 }))
            item.destroy()
        }
        return out
    }

    Component.onCompleted: {
        var failures = []
        // Assigned only once the state file is proved under the harness state home, because the store may write on assignment.
        var state = Quickshell.env("XDG_STATE_HOME") || ""
        if (state === "" || Flea.ViewState.store.path.indexOf(state + "/") !== 0)
            failures.push("the state file " + Flea.ViewState.store.path + " is not under the harness state home " + state)
        else
            Flea.ViewState.state = { display: { textSize: { mode: TextSize.nearest(root.boardTextSize) } } }
        if (Flea.Theme.font.family !== "monospace")
            failures.push("Theme.font.family is " + JSON.stringify(Flea.Theme.font.family) + ", not the monospace alias the harness's fonts.conf pins to the board's face")
        if (Flea.Theme.baseSize !== root.boardTextSize)
            failures.push("the probe draws at " + Flea.Theme.baseSize + ", the boards at " + root.boardTextSize)
        var found = root.measure()
        root.checkBands(found, failures)
        root.checkCaptions(found, failures)
        var paths = root.favouritePaths()
        var labelX = found.label.length > 0 ? found.label[0].x : null
        failures = failures.concat(found.failures)
        function expect(list, x, what) {
            for (var i = 0; i < list.length; i++) {
                if (list[i].x === null || list[i].x !== x)
                    failures.push(list[i].at + " starts at " + list[i].x + ", " + what + " is " + x)
            }
        }
        expect(found.label, labelX, "the label column")
        expect(found.hint, labelX, "the label column")
        expect(found.ruler, labelX, "the label column")
        // The control that proves the reader tells two columns apart: the footer sits at the row's edge.
        expect(found.footer, Flea.Theme.spacing.rowPaddingX, "the row edge")
        if (labelX === null || labelX === Flea.Theme.spacing.rowPaddingX || found.hint.length === 0
                || found.ruler.length === 0 || found.footer.length === 0)
            failures.push("nothing to compare: label " + labelX + ", " + found.hint.length + " hints, "
                          + found.ruler.length + " rulers, " + found.footer.length + " footers")
        if (JSON.stringify(paths.drawn) !== JSON.stringify([["~/Projects"], ["/srv/archive"]]))
            failures.push("favourite paths draw " + JSON.stringify(paths.drawn) + ", not ~/Projects then /srv/archive")
        if (JSON.stringify(paths.values) !== JSON.stringify(["/probe/Projects", "/srv/archive"]))
            failures.push("favourite values are " + JSON.stringify(paths.values) + ", the stored absolute paths")
        for (var f = 0; f < failures.length; f++)
            console.log("SETTINGS_COLUMNS FAIL " + failures[f])
        if (failures.length === 0)
            console.log("SETTINGS_COLUMNS PASS label=" + labelX + " labels=" + found.label.length + " hints=" + found.hint.length
                        + " rulers=" + found.ruler.length + " footer=" + found.footer[0].x)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
