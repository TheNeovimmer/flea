import QtQuick
import Quickshell
import Quickshell.Io

// Wayland window positions are not QWindow positions. Match the one source client
// by pid using Theme's hyprctl Process pattern, once per lift, never on motion.
Item {
    id: root
    property string token: ""
    property string queryToken: ""
    property bool queryDrained: true
    property var rect: null
    property var strip: null

    function begin(lift, band) {
        root.token = lift
        root.rect = null
        root.strip = band
        // An old query drains before the latest token starts its own query.
        if (query.running || !root.queryDrained)
            return
        root.queryDrained = false
        root.queryToken = lift
        query.running = true
    }

    // Exit must clear running and drain old stdout before the next token starts.
    function restartLatest() {
        if (!query.running && root.queryDrained && root.queryToken !== root.token) root.begin(root.token, root.strip)
    }

    Process {
        id: query
        command: ["hyprctl", "clients", "-j"]
        onExited: Qt.callLater(root.restartLatest)
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.queryDrained = true
                Qt.callLater(root.restartLatest)
                if (root.queryToken !== root.token)
                    return
                try {
                    // Sample input: [{"pid":111,"at":[0,0],"size":[900,500],"mapped":true,"hidden":false}].
                    var clients = JSON.parse(text)
                    var matches = clients.filter(function (client) {
                        return String(client.pid) === String(Quickshell.processId)
                            && client.mapped !== false && client.hidden !== true
                    })
                    if (matches.length === 1) {
                        var client = matches[0]
                        if (client.at && client.size && isFinite(client.at[0]) && isFinite(client.at[1])
                                && client.size[0] > 0 && client.size[1] > 0)
                            root.rect = { x: client.at[0], y: client.at[1], width: client.size[0], height: client.size[1] }
                    }
                } catch (error) { root.rect = null }
            }
        }
    }
}
