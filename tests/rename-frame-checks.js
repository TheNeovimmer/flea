.pragma library

// The rename frame test's geometry checks, taking the test's root for its counters, tokens and tree walkers.

// Sample input: overlaps({x: 0, y: 0, width: 10, height: 10}, {x: 10, y: 0, width: 5, height: 5}) is false, they only touch.
function overlaps(a, b) { return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height }
function sceneBox(item) { return item.mapToItem(null, 0, 0, item.width, item.height) }
// Sample input: kindOf(item) of a Row prints "Row_QMLTYPE_12(0x55d0)" and answers "Row".
function kindOf(item) { return String(item).split("_")[0] }
// The drawn cells of one kind other than the one holding the editor, in the whole window.
function siblings(root, cell) {
    return root.ofType(root.windowBody, kindOf(cell), []).filter(function (o) { return o !== cell && o.visible && o.width > 0 && o.height > 0 })
}

// The frame stays in its own row or cell and in its own column, and meets no other row, cell or column drawn beside it.
function neighbours(root, tag, found, scene, want) {
    var cell = found.cell
    // A row shorter than the frame is overhung by design, which checkPlacement bounds.
    if (cell.height < want) return
    var others = siblings(root, cell)
    root.check(others.length > 0, tag + " drew no other " + kindOf(cell) + ", so no neighbour was measured")
    var own = sceneBox(cell)
    root.check(scene.x >= own.x && scene.y >= own.y && scene.x + scene.width <= own.x + own.width && scene.y + scene.height <= own.y + own.height, tag + " frame " + root.boxText(scene) + " leaves its own cell " + root.boxText(own))
    for (var i = 0; i < others.length; i++)
        root.check(!overlaps(scene, sceneBox(others[i])), tag + " frame " + root.boxText(scene) + " overlaps a neighbouring " + kindOf(cell) + " " + root.boxText(sceneBox(others[i])))
    if (!found.column) return
    var column = sceneBox(found.column)
    root.check(scene.x >= column.x && scene.x + scene.width <= column.x + column.width, tag + " frame " + root.boxText(scene) + " leaves its column " + root.boxText(column))
    var columns = siblings(root, found.column)
    for (var j = 0; j < columns.length; j++)
        root.check(!overlaps(scene, sceneBox(columns[j])), tag + " frame overlaps a neighbouring column " + root.boxText(sceneBox(columns[j])))
}

// The board fills the interior with the selection edge to edge and centres the text in it.
function selection(root, tag, editor) {
    var sel = editor.selectionBox
    root.check(!!sel && sel.visible, tag + " the stem selection is not drawn as one box in the field")
    if (!sel || !sel.visible) return
    var frame = editor.frame
    var field = editor.inputItem
    var box = sel.mapToItem(frame, 0, 0, sel.width, sel.height)
    var interior = frame.height - 2 * root.hairline
    root.check(box.y === root.hairline && box.height === interior, tag + " selection " + root.boxText(box) + " is not the interior, " + interior + " tall one hairline in")
    root.check(Math.abs(box.y + box.height / 2 - field.height / 2) <= 0.5, tag + " the text line is not centred in the selection")
    var from = field.positionToRectangle(field.selectionStart).x
    var to = field.positionToRectangle(field.selectionEnd).x
    root.check(Math.abs(box.x - (root.gap + from)) <= 0.5 && Math.abs(box.width - (to - from)) <= 0.5, tag + " selection " + root.boxText(box) + " does not span the selected text " + from + " to " + to)
}

// The grid centres the one line box on the caption's first line it replaces, in the list's body size.
function grid(root, tag, found, box) {
    var cell = found.cell
    var lineCentre = cell.captionItem.y + root.captionLineHeight / 2
    root.check(Math.abs(box.y + box.height / 2 - lineCentre) <= 0.5, tag + " frame centre " + (box.y + box.height / 2) + " is not the caption line's " + lineCentre)
    root.check(found.editor.inputItem.font.pixelSize === root.bodyPx, tag + " editor draws at " + found.editor.inputItem.font.pixelSize + " px, not the body size " + root.bodyPx)
    root.check(cell.renameExtraHeight === 0, tag + " the tile grew by " + cell.renameExtraHeight + " for a field its caption room holds")
}

// The error line a column draws: the rows below move down for it, none is drawn over, and it spans label column to right inset.
function columnError(root, tag, host, found, label, line) {
    var column = found.column
    root.check(root.inside(label.mapToItem(column, 0, 0, label.width, label.height), column.width, column.height), tag + " error line " + root.boxText(label.mapToItem(column, 0, 0, label.width, label.height)) + " leaves its column " + column.width + "x" + column.height)
    var rows = root.ofType(column, "ColumnRow", []).filter(function (r) { return r !== found.cell && r.visible })
    var own = sceneBox(found.cell)
    var below = 0
    for (var i = 0; i < rows.length; i++) {
        var other = sceneBox(rows[i])
        root.check(!overlaps(line, other), tag + " error line " + root.boxText(line) + " is drawn over the row at " + root.boxText(other))
        if (other.y > own.y) {
            below++
            root.check(other.y >= line.y + line.height, tag + " the next row starts at " + other.y + ", above the error's bottom " + (line.y + line.height))
        }
    }
    root.check(host.last || below > 0, tag + " drew no row under the renamed one, so none was measured moving")
    // The renamed row's own mark, name, size and chevron keep to its first line, so none sits under its error line.
    var parts = found.cell.children.filter(function (c) { return c.visible && c.width > 0 && c.height > 0 && c.height < found.cell.height - found.cell.errorGrowth })
    for (var p = 0; p < parts.length; p++)
        root.check(!overlaps(line, sceneBox(parts[p])), tag + " the row's own " + parts[p] + " at " + root.boxText(sceneBox(parts[p])) + " lies under its error line " + root.boxText(line))
    var box = label.mapToItem(found.cell, 0, 0, label.width, label.height)
    var span = found.cell.width - root.rowInset - box.x
    root.check(box.x === column.renameLeft && box.width === span, tag + " error line " + root.boxText(box) + " does not span " + column.renameLeft + " to the right inset " + (found.cell.width - root.rowInset))
    root.metrics.font = label.font
    root.metrics.text = root.errorSample
    root.check(root.metrics.width <= span ? label.lineCount === 1 : label.lineCount > 1, tag + " error line wraps in " + span + " px though it fits in " + root.metrics.width)
    if (host.last) {
        root.check(found.cell.index === root.pane.shownTotal - 1, tag + " renamed row " + found.cell.index + " is not the column's last")
        root.check(root.roomBelow < label.height + root.gap, tag + " the last row has " + root.roomBelow + " px under it, room for the error without the scroll")
    }
}
