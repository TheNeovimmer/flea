.pragma library

// How long the favourite inspector waits for its answer before its guard clears anyway:
// one favourite on a dead mount must not stop every later favourite status for the window's life.
var INSPECT_WAIT_MS = 10000

// True once the wait has run out, so the guard clears even when no answer ever lands.
function expired(startedAt, nowMs) {
    return nowMs - startedAt >= INSPECT_WAIT_MS
}
