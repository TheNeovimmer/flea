.pragma library

// ui/ViewState.qml's one-writer bookkeeping, and nothing else: `saved` is the newest patch a writer
// landed, `inflight` is what the running `flea --ui-state` carries, and `pending` is the newest patch
// waiting behind it. All three are patch bytes and not the state file's, because a patch names only
// the settings that window changed. Imports no QML, so tests/js/uistate.js can redden on a mutation.

// The window's own read of ui.json. main() leaves a document it cannot read as a JSON object
// exactly as the operator wrote it, so `unreadable` is what makes the pane say the file was not used;
// no file at all is a first launch and says nothing.
function fromFile(text) {
    try {
        var found = JSON.parse(text)
        if (found && typeof found === "object" && !Array.isArray(found)) {
            return { state: found, unreadable: false }
        }
    } catch (e) {
        // A hand edit this cannot parse, which is the ordinary way in and is not an error here.
    }
    return { state: {}, unreadable: text.length > 0 }
}

// External favourites update independently of this window's settings drafts and pending patches.
function refreshedFavourites(state, text) {
    var read = fromFile(text)
    var places = read.state.places
    if (text.length === 0 || read.unreadable || (places !== undefined && (!places || typeof places !== "object" || Array.isArray(places)))
            || (places && places.favourites !== undefined && !Array.isArray(places.favourites)))
        return { state: state, error: "Favorites could not be refreshed: invalid ui.json; previous entries kept." }
    var records = places && places.favourites || []
    if (JSON.stringify((state.places || {}).favourites || []) === JSON.stringify(records))
        return { state: state, error: "" }
    return { state: withGroup(state, "places", { favourites: records }), error: "" }
}

// Compare a save with this window's intent, because the writer response can include concurrent edits.
function favouritesAfter(records, operation) {
    var next = records.slice()
    if (operation.op === "add") next.push(operation.record)
    else if (operation.op === "remove") next.splice(operation.index, 1)
    else if (operation.op === "move") next.splice(operation.to, 0, next.splice(operation.index, 1)[0])
    else if (operation.op === "rename") next[operation.index] = Object.assign({}, next[operation.index], { label: operation.label })
    return next
}

// Keys one window never takes from the state file, because they name where that window is
// rather than how Flea behaves: the view it shows, the widths it drew, the dual pair and focus,
// where it was, its own sort, and stamps the sweep and the migrations own. Everything else is a
// preference the Settings panel or a global toggle writes, and applies live in every open window.
var WINDOW_KEYS = ["view", "pickerView", "columnWidths", "dual", "lastPath", "lastTabs",
                   "trashSweptOn", "stateVersion", "sort"]

function isWindowKey(key) {
    return WINDOW_KEYS.indexOf(key) >= 0
}

// Leaves one window never takes, Finder-style: the rail, the preview column and the grid zoom
// stay per window like the sidebar, preview pane and icon size. A change made in Settings still
// writes the file and a new window reads it; open windows keep their own.
var WINDOW_LEAF_KEYS = ["places.rail", "preview.column", "preview.thumbSize"]

function isWindowLeaf(key, leaf) {
    return WINDOW_LEAF_KEYS.indexOf(key + "." + leaf) >= 0
}

// True for a patch the schema refused, which settled heals and a retry can never land: the
// binary names the key it refused. Anything else (an unwritable directory, a wrapper's simulated
// refusal, a writer that never started) keeps today's retry, so transient failures lose nothing.
// The writer reads this off its own inflight patch rather than the child's stderr, because onExited
// races the collector's text and an empty read would retry a refusal forever.
function isValidationRefusal(stderrText) {
    var text = String(stderrText || "")
    return text.indexOf("must be a JSON object") >= 0
        || text.indexOf("is not a ui.json key") >= 0
        || text.indexOf("takes an object, not") >= 0
        || text.indexOf("is kept by Flea") >= 0
        || text.indexOf("does not take") >= 0
}

// The same decision off the patch itself, which is what the writer gates on: a columns set without
// name, with an unknown key or with a duplicate, and a places group that is not an object, are the
// shapes a hand edit plants and a retry can never land. Anything else retries, so the wrapper's
// simulated refusal of a valid patch keeps the old behaviour.
function isPatchInvalid(patchText) {
    var patch = null
    try {
        patch = JSON.parse(patchText)
    } catch (e) {
        return false
    }
    if (!patch || typeof patch !== "object" || Array.isArray(patch))
        return false
    if (patch.columns !== undefined) {
        var cols = patch.columns
        if (!Array.isArray(cols) || cols.indexOf("name") < 0)
            return true
        var seen = {}
        var keys = ["name", "mode", "size", "date", "kind"]
        for (var i = 0; i < cols.length; i++) {
            if (keys.indexOf(cols[i]) < 0 || seen[cols[i]])
                return true
            seen[cols[i]] = true
        }
    }
    if (patch.places !== undefined && (patch.places === null || typeof patch.places !== "object" || Array.isArray(patch.places)))
        return true
    return false
}

// True when text parses as a JSON object; empty or garbage is ignored until the next valid write.
function parsesAsObject(text) {
    try {
        var found = JSON.parse(text)
        return found && typeof found === "object" && !Array.isArray(found)
    } catch (e) {
        return false
    }
}

// Drop a refused patch's keys from what is owed and revert them to the settled document, so one
// refusal never blocks every later save. Groups drop leaf by leaf, maps entry by entry; whole
// keys drop whole. Returns the pruned owed patch plus the dropped top-level keys.
function pruneRefused(unsaved, inflightText, settled) {
    var inflight = null
    try {
        inflight = JSON.parse(inflightText)
    } catch (e) {
        return { unsaved: unsaved, dropped: [] }
    }
    if (!inflight || typeof inflight !== "object" || Array.isArray(inflight))
        return { unsaved: unsaved, dropped: [] }
    var out = {}
    for (var k in unsaved)
        out[k] = unsaved[k]
    var dropped = []
    for (var key in inflight) {
        if (out[key] === undefined)
            continue
        if (isGroup(out[key]) && isGroup(inflight[key])) {
            var kept = {}
            var any = false
            for (var leaf in out[key]) {
                if (inflight[key][leaf] !== undefined
                        && JSON.stringify(out[key][leaf]) === JSON.stringify(inflight[key][leaf])) {
                    if (settled && settled[key] && JSON.stringify(inflight[key][leaf])
                            !== JSON.stringify(settled[key][leaf]))
                        continue
                } else {
                    kept[leaf] = out[key][leaf]
                    any = true
                }
            }
            if (any)
                out[key] = kept
            else
                delete out[key]
            dropped.push(key)
        } else {
            delete out[key]
            dropped.push(key)
        }
    }
    return { unsaved: out, dropped: dropped }
}

// The settled values a dropped key reverts to: whole keys copy, group leaves copy leaf by leaf.
function revertedState(state, inflightText, settled) {
    var inflight = null
    try {
        inflight = JSON.parse(inflightText)
    } catch (e) {
        return state
    }
    if (!inflight || typeof inflight !== "object" || !settled)
        return state
    var out = {}
    for (var s in state)
        out[s] = state[s]
    for (var key in inflight) {
        if (settled[key] === undefined)
            continue
        if (isGroup(inflight[key]) && isGroup(settled[key]) && isGroup(out[key])) {
            var group = {}
            for (var h in out[key])
                group[h] = out[key][h]
            for (var leaf in inflight[key]) {
                if (settled[key][leaf] !== undefined)
                    group[leaf] = settled[key][leaf]
                else
                    delete group[leaf]
            }
            out[key] = group
        } else {
            out[key] = settled[key]
        }
    }
    return out
}

// A change another window saved, read off the file's own bytes. Preference keys the file names and
// this window does not owe take the file's value, through the same state assignment the Settings
// panel's own owe() makes, so bindings, listings and menus update the way a local change does.
// Per-window keys are left alone, and so is anything this window changed and no writer has landed
// for yet (leaf by leaf inside a group, entry by entry inside a map), so applying never clobbers
// an in-flight write and never writes in response: the answer is a document, not a patch.
// A file that does not parse as an object is ignored until the next valid write, the way fromFile
// already treats a half-written one. Favourites keep their own validated syncFavourites path, so
// they are never taken here. Returns the state to draw, and whether it moved at all.
function applyExternal(state, unsaved, text) {
    var read = fromFile(text)
    if (read.unreadable)
        return { state: state, changed: false }
    var file = read.state
    var out = {}
    for (var s in state)
        out[s] = state[s]
    var changed = false
    for (var key in file) {
        if (isWindowKey(key))
            continue
        var value = file[key]
        if (key === "places" && isGroup(value)) {
            var merged = {}
            for (var f in value) {
                if (f !== "favourites")
                    merged[f] = value[f]
            }
            var held = state.places || {}
            if (held.favourites !== undefined)
                merged.favourites = held.favourites
            var owedPlaces = unsaved ? unsaved.places : undefined
            if (isGroup(owedPlaces)) {
                for (var leaf in owedPlaces) {
                    if (leaf === "favourites")
                        continue
                    if (held[leaf] !== undefined)
                        merged[leaf] = held[leaf]
                    else
                        delete merged[leaf]
                }
            }
            if (held.rail !== undefined)
                merged.rail = held.rail
            if (JSON.stringify(merged) !== JSON.stringify(state.places)) {
                out.places = merged
                changed = true
            }
            continue
        }
        var owed = unsaved ? unsaved[key] : undefined
        if (owed !== undefined) {
            if (isGroup(owed) && isGroup(value) && !isWholeKey(key)) {
                var group = {}
                for (var g in value)
                    group[g] = value[g]
                var current = state[key] || {}
                for (var o in owed) {
                    if (current[o] !== undefined)
                        group[o] = current[o]
                    else
                        delete group[o]
                }
                for (var w in group) {
                    if (isWindowLeaf(key, w)) {
                        if (current[w] !== undefined)
                            group[w] = current[w]
                        else
                            delete group[w]
                    }
                }
                if (JSON.stringify(group) !== JSON.stringify(state[key])) {
                    out[key] = group
                    changed = true
                }
            }
            continue
        }
        if (isGroup(value) && isGroup(state[key])) {
            var anyLeafWindow = false
            for (var vl in value) {
                if (isWindowLeaf(key, vl)) {
                    anyLeafWindow = true
                    break
                }
            }
            if (anyLeafWindow) {
                var leafGroup = {}
                for (var vg in value) {
                    if (!isWindowLeaf(key, vg))
                        leafGroup[vg] = value[vg]
                }
                var heldGroup = state[key] || {}
                for (var hg in heldGroup) {
                    if (isWindowLeaf(key, hg))
                        leafGroup[hg] = heldGroup[hg]
                }
                if (JSON.stringify(leafGroup) !== JSON.stringify(state[key])) {
                    out[key] = leafGroup
                    changed = true
                }
                continue
            }
        }
        if (JSON.stringify(value) !== JSON.stringify(state[key])) {
            out[key] = value
            changed = true
        }
    }
    return { state: changed ? out : state, changed: changed }
}

// A copy of the document with one top-level key replaced, and the nested version of the same. QML
// notifies on assignment and not on a mutation, so every writer rebuilds rather than reaching in;
// the nested one merges into the group beside it, because a whole-group assignment would take the
// half a writer holds as the whole of it. ui/ViewState.qml runs both over two documents at once:
// the state it draws from, and the patch it owes the state file.
function withKey(state, key, value) {
    var out = {}
    for (var s in state)
        out[s] = state[s]
    out[key] = value
    return out
}

function withGroup(state, key, next) {
    var group = {}
    var held = state[key] || {}
    for (var h in held)
        group[h] = held[h]
    for (var n in next)
        group[n] = next[n]
    return withKey(state, key, group)
}

// The book a window starts with: nothing of its own written yet, and no writer running. Its own read
// of the file is not a patch it sent, so `saved` starts empty rather than holding what it read.
function book() {
    return { saved: "", inflight: "", pending: "" }
}

// A change asks for a write. The answer is the next book plus `start`, the patch to launch now.
function asked(b, patch) {
    // The newest patch this window has landed or has on its way, so asking for exactly those bytes
    // again sends nothing and a refused one is never short-circuited.
    if (patch === (b.pending || b.inflight || b.saved)) {
        return { saved: b.saved, inflight: b.inflight, pending: b.pending, start: "" }
    }
    // One writer at a time, and the newest patch waits rather than being dropped on the floor.
    if (b.inflight.length > 0) {
        return { saved: b.saved, inflight: b.inflight, pending: patch, start: "" }
    }
    return { saved: b.saved, inflight: patch, pending: "", start: patch }
}

// The writer exited. The answer is the next book plus `start`, and `failed` for the pane to report.
// `owed` is what the window still owes NOW and is what a queued writer launches with, because the
// bytes waiting in `pending` were built before this writer landed: they still name the settings it
// just stored, and re-sending one writes this window's own copy of it over whatever another window
// or the CLI put there in between. A refusal changes nothing, so there `owed` is those same bytes.
function exited(b, code, owed) {
    // Nothing waiting, or nothing left owed once this writer's own settings came out of it, which a
    // value changed and changed back under one writer produces: an empty patch is a process and a
    // rename spent on a document that would come out byte for byte the same.
    var next = (b.pending.length > 0 && owed !== "{}") ? owed : ""
    return {
        // Only a zero status proves the patch reached the file: src/main.rs exits 2 on a refused
        // patch and on a state directory it could not write, and the change is on screen either way.
        saved: code === 0 ? b.inflight : b.saved,
        inflight: next,
        pending: "",
        start: next,
        failed: code !== 0
    }
}

// What is still owed once the patch a writer landed is taken out of it. A setting is only cleared
// when what the window owes for it now is what that writer carried: a change made while the writer
// ran is a newer value for the same setting, and the file does not have that one yet.
function acknowledged(unsaved, patch) {
    var landed
    try {
        landed = JSON.parse(patch)
    } catch (e) {
        // Bytes this file built itself, so a parse failure clears nothing rather than clearing wrong.
        return unsaved
    }
    if (!landed || typeof landed !== "object" || Array.isArray(landed))
        return unsaved
    var out = {}
    for (var key in unsaved) {
        var still = stillOwed(unsaved[key], landed[key], key)
        if (still !== undefined)
            out[key] = still
    }
    return out
}

// One key of the owed patch against the same key of the landed one: `undefined` when the writer took
// all of it, and otherwise what is left. Two objects are a settings group and are walked leaf by
// leaf, because changeLeaf owes the leaf alone and clearing the group would drop a leaf beside it
// that no writer has taken yet. A map (changeMapEntries) owes entry by entry, which is the same
// walk. A whole-value object key below is the exception: it is compared and cleared whole, because
// src/uischema.rs Rule::LastTabs stands or falls together and a half value is refused whole.
function stillOwed(owed, landed, key) {
    if (landed === undefined)
        return owed
    if (isWholeKey(key) && isGroup(owed) && isGroup(landed))
        return JSON.stringify(owed) === JSON.stringify(landed) ? undefined : owed
    if (isGroup(owed) && isGroup(landed)) {
        var kept = {}
        var any = false
        for (var leaf in owed) {
            if (JSON.stringify(owed[leaf]) === JSON.stringify(landed[leaf]))
                continue
            kept[leaf] = owed[leaf]
            any = true
        }
        return any ? kept : undefined
    }
    return JSON.stringify(owed) === JSON.stringify(landed) ? undefined : owed
}

// A settings group, which is the only shape withGroup builds: an array is a whole key's value.
function isGroup(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

// Whole-value object keys: owed and cleared whole, never leaf by leaf. Today only lastTabs, whose
// src/uischema.rs Rule::LastTabs takes exactly paths plus index together.
function isWholeKey(key) {
    return key === "lastTabs"
}
