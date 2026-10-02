.pragma library

.import "DragOut.js" as DragOut
.import "Ops.js" as Ops
.import "Swap.js" as Swap

// A drop is a gesture that calls the transfer request Ops.moveToDropbox already sends, with the folder
// row under the pointer as its destination, so there is no second copy path here. States.dc.html
// "Drop target": the hovered folder takes the accent frame and reads "move here", and copy versus
// move reads in the status bar. ui/List.qml wires the handlers; this file decides.

// The rows a drag carries: the whole selection when the pressed row is in it, that row alone when it
// is not. One file dropped when five were selected is a data surprise; five moved when the operator
// grabbed one is a worse one, so the pressed row decides which the drag means.
function carried(pane, index) {
    var picked = pane.selectedIndices()
    for (var i = 0; i < picked.length; i++) {
        if (picked[i] === index) {
            return picked
        }
    }
    return [index]
}

// Ctrl copies, Shift moves, both link: read at the lift, since Drag.active gets no keys after it.
function copying(modifiers) {
    return (modifiers & Qt.ControlModifier) !== 0
}

function shifting(modifiers) {
    return (modifiers & Qt.ShiftModifier) !== 0
}

function linking(modifiers) {
    return copying(modifiers) && shifting(modifiers)
}

// Only a directory row takes a drop, and never one the drag itself carries: a folder cannot move into
// itself, and a selection holding the target is refused whole rather than moved in part.
function canDrop(rows, index, row) {
    if (!row || row.d !== true) {
        return false
    }
    return rows.indexOf(index) < 0
}

// The board's own words on the hovered folder.
function label(copy, link) {
    if (link === true) return "link here"
    return copy ? "copy here" : "move here"
}

// The status bar's half of the board. The hint names the lift because Drag.active runs a nested
// event loop the window gets no key events in, so a key pressed after the drag starts cannot arrive.
function line(n, name, copy, link) {
    var verb = link === true ? "Link " : copy ? "Copy " : "Move "
    var where = name.length > 0 ? " to " + name : " to a folder"
    return verb + Ops.items(n) + where + ((copy || link === true) ? "" : " · ctrl copies and shift moves, read at lift")
}

// Rows as Ops.moveToDropbox sends them, named in the listing of the lift; answers whether the card's question went out.
function drop(pane, rows, index, copy, listing) {
    return dropByIndex(pane, rows, index, copy ? "copy" : "move", listing)
}

// The by-index drop in verb form, the only path a selection too wide to carry paths takes, and only
// onto its own listing. A link names the same card Paste as links asks through, so one undo removes it.
function dropByIndex(pane, rows, index, verb, listing) {
    var row = pane.rowFor(index)
    if (!canDrop(rows, index, row)) {
        return false
    }
    var dest = pane.join(pane.path, row.n)
    if (verb === "link") {
        return pane.collide.ask(Swap.named({ c: "link", op: "relative", rows: rows, dest: dest }, listing))
    }
    return pane.collide.ask(Swap.named({ c: "transfer", op: verb, rows: rows, dest: dest }, listing))
}

// The local paths an external drag carries. Qt hands these over as file:// URIs, and anything that is
// not one is left behind rather than guessed at, so a drag from a browser carrying an http link
// contributes nothing instead of a bogus path. The wire form is percent-encoded, so it is decoded here.
function pathsFromUrls(urls) {
    return DragOut.filePaths(urls)
}


// The type Flea's own drag carries alongside the uri-list. The compositor hands a window's own
// platform drag back to that window's own DropAreas, so without a marker an internal move would be
// indistinguishable from a foreign drop, take the always-copy path below, and leave the source behind
// while still looking like it worked.
var ROWS_MIME = "application/x-flea-rows"

// DragOut rule 4: Flea is the one named receiver of a shelf drag. The payload is the single-use
// token the shelf minted and the intent it fixed at the lift, in that order, one per line. The token
// is the authority: the backend reads the entries and the intent out of its own record, and this
// second line is only so the receiver can say the right word before the drop lands.
var SHELF_MIME = "application/x-flea-shelf"

function shelfToken(payload) {
    return String(payload || "").split("\n")[0]
}

function shelfCopying(payload) {
    return String(payload || "").split("\n")[1] === "copy"
}

// A value unique to this running Flea. ROWS_MIME names the application, and two Flea windows are two
// processes: a drag from the other one carries row indices that mean nothing in this listing, so the
// instance has to be identifiable on its own or the receiver takes the internal path against a
// selection it never made and the drop does nothing at all.
var INSTANCE = String(Date.now()) + "-" + String(Math.floor(Math.random() * 1000000000))

// False only when the listed directory cannot be written, which makes a same-device drag copy.
function listingDeletable(pane) {
    return !(pane && pane.backend && pane.backend.dirWritable === false)
}

// One marker, not two mime types, carrying sender, rows and lift bits (fields: 0 sender, 1 rows, 2 ctrl, 3 source, 4 device, 5 deletable, 6 shift).
function markerPayload(rows, copy, source, dev, deletable, shift) {
    return INSTANCE + "\n" + rows.join(",") + "\n" + (copy ? "copy" : "move") + "\n" + String(source || "") + "\n" + String(dev || 0) + "\n" + (deletable === false ? "0" : "1") + "\n" + (shift === true ? "1" : "0")
}

// The directory the rows were lifted from, and its filesystem, both baked at the lift: a drop that
// lands after the listing changed under the drag, which hovering a tab now does, cannot use the row
// indices any more and resolves by path against these instead.
function markerSource(payload) {
    return String(payload).split("\n")[3] || ""
}

function markerDev(payload) {
    return Number(String(payload).split("\n")[4]) || 0
}

function markerShift(payload) {
    return String(payload).split("\n")[6] === "1"
}

// Missing means the source can be deleted. Only an explicit 0 copies a same-device drag.
function markerDeletable(payload) {
    var field = String(payload).split("\n")[5]
    return field !== "0"
}

// Whether the listing under the drop is still the one the rows were lifted from, which is the only
// case the by-index transfer is safe in.
function sameListing(payload, path) {
    return isOwnDrag(payload) && markerSource(payload) === path
}

// Whether a drag carries at least one local path, which is what decides a drop resolves by path.
function hasPaths(urls) {
    return pathsFromUrls(urls).length > 0
}

// The by-index drop's gate: only a selection too wide to carry paths takes it, only onto its own
// listing, and never onto a folder it carries itself.
function canDropByIndex(marker, path, rows, index) {
    return rows.length > 0 && sameListing(marker, path) && rows.indexOf(index) < 0
}

// Whether the marked drag was lifted with ctrl down. No marker answers false.
function markerCopying(payload) {
    return String(payload).split("\n")[2] === "copy"
}

// Whether a marked drag began in this very window. An unmarked drag has no payload and answers false,
// which is the right answer: something that is not Flea is not this Flea.
function isOwnDrag(payload) {
    return String(payload).split("\n")[0] === INSTANCE
}

// A path as a file:// URI. Each component is encoded on its own: encodeURIComponent would escape the
// separators too, and encodeURI would leave a "#" or a "?" in a filename unescaped.
function uriFor(path) {
    var parts = path.split("/")
    for (var i = 0; i < parts.length; i++) {
        parts[i] = encodeURIComponent(parts[i])
    }
    return "file://" + parts.join("/")
}

// What the drag puts on the wire: the marker naming this drag as Flea's own, which the backend
// resolves by index and which therefore always carries the whole selection, plus a CRLF-separated
// uri-list for every other application.
//
// The uri-list is offered only when every carried row resolves. A selection reaches past the window
// the client holds and pane.rowFor answers null outside it, so a wide selection cannot be turned into
// paths here at all; pushing only the rows that happen to be realised is the defect Ops.js records as
// "a wide move relocated a few files and abandoned the rest", and here it would hand another
// application a subset while the bar named the whole count. No list at all is refusable and visible.
// Whether the key is present is also what tells the bar the drag cannot leave Flea.
function mimeFor(pane, rows, copy, shift) {
    var mime = {}
    mime[ROWS_MIME] = markerPayload(rows, copy, pane.path, pane.backend ? pane.backend.dirDev : 0, listingDeletable(pane), shift === true)
    var uris = []
    var paths = []
    for (var i = 0; i < rows.length; i++) {
        var row = pane.rowFor(rows[i])
        if (!row) {
            return mime
        }
        paths.push(pane.join(pane.path, row.n))
        uris.push(uriFor(paths[paths.length - 1]))
    }
    if (uris.length > 0) {
        mime["text/uri-list"] = uris.join("\r\n") + "\r\n"
        // GM's ruling: a terminal or a text field that takes plain text gets the absolute paths, one a line.
        mime["text/plain"] = paths.join("\n")
    }
    return mime
}

// A path drop lands on another directory only, and only with paths to send; same-directory and pathless drops refuse.
function canDropInto(marker, urls, dest, plain) {
    // No destination is no drop: a tab with no path for its row and the history's base, which
    // names no folder of its own, both refuse rather than landing wherever "" resolves.
    if (!dest) return false
    if (isOwnDrag(marker) && markerSource(marker) === dest) return false
    var paths = DragOut.sources(urls, plain, marker, "")
    return paths.length > 0 && DragOut.refusal(paths, dest, marker, "") === ""
}

// Path drops transfer through dropVerb, the only verb decision, which ignores proposed for a Flea marker.
function dropInto(pane, marker, urls, dest, destDev, shelf, plain, proposed) {
    // No destination is no drop, even for a shelf drag whose token would otherwise redeem.
    if (!dest) return false
    var paths = DragOut.sources(urls, plain, marker, shelf)
    if (!canDropInto(marker, urls, dest, plain) && shelfToken(shelf).length === 0) return false
    // Rule 4: a shelf drag is redeemed rather than re-read as a list of URIs, because a fallback to
    // a URI copy after the shelf promised a move is the silent wrong answer it forbids; its URIs only ask first.
    if (shelfToken(shelf).length > 0) {
        return pane.collide.ask({ c: "transfer", op: "", paths: [], dest: dest, shelf: shelfToken(shelf) }, pathsFromUrls(urls))
    }
    var verb = dropVerb(marker, proposed, destDev)
    if (verb === "link") {
        return pane.collide.ask({ c: "link", op: "relative", paths: paths, dest: dest })
    }
    return pane.collide.ask({ c: "transfer", op: verb, paths: paths, dest: dest })
}

// Marker-less platform action, read here only: move-only shifts, copy-only copies, link-only links, both-or-neither stays plain.
function foreignHeld(proposed) {
    var moveBit = (proposed & Qt.MoveAction) !== 0
    var copyBit = (proposed & Qt.CopyAction) !== 0
    var linkBit = (proposed & Qt.LinkAction) !== 0
    if (linkBit && !moveBit && !copyBit) return { copy: true, shift: true }
    if (moveBit && !copyBit) return { copy: false, shift: true }
    if (copyBit && !moveBit) return { copy: true, shift: false }
    return { copy: false, shift: false }
}

// Verb from marker plus platform action: a Flea marker carries the lift's own bits, a foreign drag follows foreignHeld.
function dropVerb(marker, proposed, destDev) {
    if (marker) {
        return verbFor(isOwnDrag(marker), markerCopying(marker), markerShift(marker),
                       markerDev(marker), destDev, markerDeletable(marker))
    }
    var held = foreignHeld(proposed)
    return verbFor(false, held.copy, held.shift, 0, destDev, true)
}

// Only verb decision: Ctrl with Shift links, Ctrl copies, Shift moves; else same-device moves and unknown-device or undeletable copies.
function verbFor(own, ctrlHeld, shiftHeld, srcDev, destDev, deletable) {
    void own
    if (ctrlHeld && shiftHeld) return "link"
    if (ctrlHeld) return "copy"
    if (shiftHeld) return "move"
    if (!srcDev || !destDev || deletable === false) return "copy"
    return srcDev === destDev ? "move" : "copy"
}

// Said beside the drag line when the selection cannot be handed to another application. The internal
// drop is still whole, so the count stands; this only tells the operator the drag will not leave,
// which beats a drop that silently does nothing over another window.
function reachNote(canLeave) {
    return canLeave ? "" : " · too wide to drag out"
}

// Sample marker "<instance>\n1,3\nmove\n/source\n42\n1\n0"; feedback never becomes destination row indices.
function feedbackFor(marker, urls, shelf, proposed) {
    var fields = String(marker).split("\n")
    var own = fields[0] === INSTANCE
    var paths = pathsFromUrls(urls)
    if (shelfToken(shelf).length > 0) {
        return { own: true, copy: shelfCopying(shelf), dev: 0, fixed: shelfCopying(shelf),
                 count: paths.length, canLeave: paths.length > 0 }
    }
    var copy = fields[2] === "copy"
    var shift = fields[6] === "1"
    if (!marker) {
        var held = foreignHeld(proposed)
        copy = held.copy
        shift = held.shift
    }
    return { own: own, copy: copy, shift: shift,
             dev: Number(fields[4]) || 0, deletable: fields[5] !== "0",
             count: own && fields[1] ? fields[1].split(",").length : paths.length,
             canLeave: paths.length > 0 }
}

function copyingFor(feedback, destDev) {
    if (!feedback) return true
    return feedback.fixed !== undefined ? feedback.fixed === true
        : verbFor(feedback.own, feedback.copy, feedback.shift, feedback.dev, destDev, feedback.deletable) === "copy"
}

function linkingFor(feedback, destDev) {
    if (!feedback || feedback.fixed !== undefined) return false
    return verbFor(feedback.own, feedback.copy, feedback.shift, feedback.dev, destDev, feedback.deletable) === "link"
}

function feedbackLine(feedback, name, destDev) {
    if (!feedback || feedback.count === 0) return ""
    var link = linkingFor(feedback, destDev)
    return line(feedback.count, name, !link && copyingFor(feedback, destDev), link) + reachNote(feedback.canLeave)
}
