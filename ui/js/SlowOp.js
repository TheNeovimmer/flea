.pragma library

// A slow notice is information, never an error: the request stays open and the late reply closes it.
function show(pane, msg) {
    pane.message(msg, false)
}

// The late reply closes exactly what the in-time reply would close.
function closesRename(request, path) {
    return !!request && path === request.destination
}
