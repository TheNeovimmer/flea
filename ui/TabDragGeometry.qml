import QtQuick
import Quickshell
import Quickshell.Io

// Wayland window positions are not QWindow positions. Match the one source client
// by pid using Theme's hyprctl Process pattern, once per lift, never on motion.
Item {
    id: root
    property string token: ""
    property string queryToken: ""
    property var rect: null
    property var strip: null

    function begin(lift, band) {
        root.token = lift
        root.rect = null
        root.strip = band
        // An old query cannot answer a new lift; until it drains this lift is unknown.
        if (query.running)
            return
        root.queryToken = lift
        query.running = true
    }

    Process {
        id: query
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (root.queryToken !== root.token)
                    return
                try {
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
