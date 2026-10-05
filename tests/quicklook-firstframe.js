.pragma library
.import "flea/js/Markdown.js" as Markdown

// Object keys in sorted order, because a block that crossed the worker's boundary comes back with its keys sorted.
function canon(v) {
    if (v === null || typeof v !== "object") return JSON.stringify(v)
    if (Array.isArray(v)) return "[" + v.map(canon).join(",") + "]"
    return "{" + Object.keys(v).sort().filter(function (k) { return v[k] !== undefined }).map(function (k) { return JSON.stringify(k) + ":" + canon(v[k]) }).join(",") + "}"
}

// The blocks the card took from the prepared entry (the worker's parse) against a fresh parse of the same text on the merged parser, kinds the stage added among them.
function sameAsFreshParse(root, d, n) {
    var fresh = Markdown.blocks(d.rawText, Markdown.dirOf(d.path), d.chromeHex, d.inkHex)
    var kinds = fresh.map(function (b) { return b.type })
    var empty = fresh.some(function (b) { return b.type === "heading" && b.text === "" })
    if (kinds.indexOf("images") < 0 || kinds.indexOf("image") < 0 || kinds.indexOf("quote") < 0 || !empty)
        root.fail("step " + n + " fixture lost a kind the prepared parse must carry: " + kinds.join("+"))
    if (canon(d.blockList) !== canon(fresh))
        root.fail("step " + n + " drew a prepared parse that differs from a fresh parse of the same text")
    else
        root.log("PARSE " + n + " prepared equals fresh blocks=" + fresh.length)
}

// A row index by file name, or -1 when the listing holds no such row.
function indexOf(root, name) {
    for (var i = 0; i < root.pane().total; i++) {
        var row = root.pane().rowFor(i)
        if (row && row.n === name) return i
    }
    return -1
}

// A real item of the shell by its type name, searched down from the preview overlay.
function find(item, type) {
    if (String(item).indexOf(type) === 0) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
        var found = find(kids[i], type)
        if (found) return found
    }
    return null
}

function collect(item, type, out) {
    if (!item) return
    if (String(item).indexOf(type) === 0) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) collect(kids[i], type, out)
}

function doc(root) {
    return root.pv() ? find(root.pv(), "PreviewMarkdown") : null
}

// Every picture the open document draws and how many have their pixels: one still loading in the first frame lands a frame later.
function pictureState(root, ready) {
    var found = []
    collect(doc(root), "QQuickImage", found)
    return { total: found.length, ready: found.filter(function (one) { return one.status === ready }).length }
}

// The compiled units the idle warm holds: an open before them would compile inside the key, which a user's first Space never does.
function unitsReady(root, ready) {
    var w = root.warm
    var units = w ? [w.previewUnit, w.markdownUnit, w.swapUnit] : []
    return units.every(function (u) { return u !== null && u !== undefined && u.status === ready })
}

// A move off the rested Markdown file releases the closed Quick Look and the move back builds it again, so only a resting window holds one.
function release(root) {
    var pane = root.pane()
    if (root.pv() === null) root.fail("the rested cursor on " + root.cur().name + " built no Quick Look before the move")
    pane.cursorIndex = indexOf(root, "img")
    if (root.pv() !== null) root.fail("a move to a folder row left Quick Look built")
    root.released = true
    pane.cursorIndex = indexOf(root, root.cur().name)
    root.quiet = 0
}

// The first block of the document named by the step: a block left over from the previous file never counts.
function firstBlock(root) {
    var p = root.pv()
    var md = p ? p.markdownItem : null
    // A too-deep document draws its notice and its Source, which is its content.
    var inner = doc(root)
    if (root.steps[root.step].expect === "deep") return inner && inner.tooDeep && inner.sourceChars > 0 && inner.noticeItem.visible ? inner.noticeItem : null
    var block = md ? md.blockItem(0) : null
    var title = root.steps[root.step].name.replace(".md", "")
    return block && block.block && String(block.block.text).indexOf(title) >= 0 ? block : null
}

// An answer for a cursor that moved on is dropped, and one for the cursor that rests is kept; neither is a read of a file.
function answerControl(root) {
    var p = root.prepare
    var held = p.preparedPath
    var seq = p.seq
    var request = { path: "/nowhere/stale.md", text: "# stale\n", dir: "/nowhere/", chrome: "#000000", ink: "#ffffff" }
    p.asked = Object.assign({ seq: seq - 1 }, request)
    p.answered({ seq: seq - 1, blocks: [{ type: "run", text: "stale" }], error: "" })
    if (p.preparedPath !== held || p.workerAnswers !== 0) root.fail("an answer for a cursor that moved on was kept")
    p.asked = Object.assign({ seq: seq }, request)
    p.answered({ seq: seq, blocks: [{ type: "run", text: "stale" }], error: "" })
    if (p.preparedPath !== request.path || p.workerAnswers !== 1) root.fail("an answer for the resting cursor was dropped")
    root.answersBefore = p.workerAnswers
}

// The checks of one finished step, run once its document's first block is in the card.
function judge(root) {
    var step = root.steps[root.step]
    var n = root.step + 1
    var d = doc(root)
    var blocked = d ? d.blockedReads - root.blockedBefore : -1
    root.log("STEP " + n + " " + step.name + " " + step.expect + " frames=" + root.contentFrame + " empty=" + root.emptyFrames + " blocked=" + blocked
        + " pictures=" + root.syncPictures.ready + "/" + root.syncPictures.total
        + " keyMs=" + (root.returnedAt - root.keyAt) + " toFrameMs=" + (root.contentAt - root.keyAt))
    if (!d || (step.expect !== "deep" && d.sourceChars !== 0)) root.fail("step " + n + " laid out " + (d ? d.sourceChars : -1) + " characters of Source text while Rendered shows")
    if (step.expect === "inline") {
        if (root.emptyFrames !== 0) root.fail("step " + n + " drew the card " + root.emptyFrames + " time(s) without its first block")
        if (root.contentFrame !== 1) root.fail("step " + n + " reached content in frame " + root.contentFrame + ", want 1")
        if (blocked !== 1) root.fail("step " + n + " blocked " + blocked + " time(s) for a small local file, want 1")
        if (step.via === "space" && (!d || d.reusedParses !== 1)) root.fail("step " + n + " parsed again instead of taking the prepared entry")
        // A small local picture is held decoded while the cursor rests, so the card builds it ready inside the key and draws it in its first frame.
        if (step.via === "space" && root.syncPictures.total === 0 && root.pictureDocs.indexOf(step.name) >= 0) root.fail("step " + n + " built no picture to check")
        if (step.via === "space" && !root.realKey && root.syncPictures.ready !== root.syncPictures.total)
            root.fail("step " + n + " built " + (root.syncPictures.total - root.syncPictures.ready) + " of " + root.syncPictures.total + " picture(s) still loading when the key returned")
        if (step.via === "space" && d && d.reusedParses === 1 && !root.compared && step.name === "a-notes.md") {
            root.compared = true
            sameAsFreshParse(root, d, n)
        }
    } else if (blocked !== 0) {
        root.fail("step " + n + " blocked " + blocked + " time(s) for " + step.name + ", want 0")
    }
    // A big document's first screen draws from the head of the parse, which is still running, and builds a screenful of delegates.
    if (step.expect === "partial" && (!root.atContent.parsing || root.atContent.delegates > root.firstScreenDelegates))
        root.fail("step " + n + " drew block 0 with the parse " + (root.atContent.parsing ? "running" : "done") + " and " + root.atContent.delegates + " delegates")
    // The swap lets go of its held picture on that head too, or a move to a big document waits out the whole parse.
    if (step.expect === "partial" && !root.atContent.look)
        root.fail("step " + n + " held the swap while the head was drawn")
    // A too-deep document is refused on the UI thread from its head, and only a screenful of its Source is laid out.
    if (step.expect === "deep" && (!d.tooDeep || d.parsedOffThread || root.maxSourceChars === 0 || root.maxSourceChars > root.firstScreenChunks * Markdown.SOURCE_CHUNK_CHARS))
        root.fail("step " + n + " deep=" + d.tooDeep + " offthread=" + d.parsedOffThread + " laid out up to " + root.maxSourceChars + " Source characters")
}
