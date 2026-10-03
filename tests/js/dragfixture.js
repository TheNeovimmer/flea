// A stub pane: what its card is asked lands in sent as is, a send straight to the backend lands wrapped, so no drop check passes by skipping the card.
function pane(sent, picked, rows) {
    return {
        path: "/d",
        rows: rows,
        clipboard: "untouched",
        selectedIndices: function () { return picked },
        rowFor: function (i) { return (i < 0 || i >= rows.length) ? null : rows[i] },
        join: function (a, b) { return a + "/" + b },
        backend: { send: function (msg) { sent.push({ straight: msg }) } }, collide: { ask: function (msg) { sent.push(msg); return true } }
    }
}

