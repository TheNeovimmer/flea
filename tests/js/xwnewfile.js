.import "sourcefixture.js" as Source

function run(check) {
    // Exercise the real New File dispatch: the xwwatch inline-editor wait targets the wrong editor.
    var dispatch = eval("(function(pane, show) { var opened = false, deleting = false, survivorId = 0, requestId = 0, folder = ''; "
        + Source.slice(Source.source("ui/PaneMenuActions.qml"), "function open(action, menuId)", "function activate(action, selected)")
        + "\nopen('newFile', 0); return {requestId: requestId, folder: folder}; })")
    var shown = [], requests = []
    var newFilePane = {path: "/fixture", backend: {send: function(message) { requests.push(message) }}}
    var dispatched = dispatch(newFilePane, function(action) { shown.push(action) })
    check("New File opens its filename dialog, not the inline rename editor", shown.join(","), "newFile")
    check("opening New File creates nothing before dialog submission", requests.length, 0)
    check("New File dialog captures its parent directory", dispatched.folder, "/fixture")
    var submit = eval("(function(requested) { var canSubmit = true, action = 'newFile', field = {text: 'created-by-a.txt'}, "
        + "body = {forceActiveFocus: function() {}}, busy = false, committing = false, errorText = '', requestId = 1, folder = '/fixture'; "
        + Source.slice(Source.source("ui/MenuActionDialog.qml"), "function submit()", "function stepFocus(back)")
        + "\nsubmit(); })")
    submit(function(message) { requests.push(message) })
    check("New File submission sends the backend creation request", JSON.stringify(requests),
        JSON.stringify([{c: "newfile", op: "newFile", id: 1, path: "/fixture", name: "created-by-a.txt"}]))
}
