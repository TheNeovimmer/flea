import Quickshell.Io
import "js/Devices.js" as Devices

FileView {
    property var owner: null
    path: owner && owner._powerOffDisk.length > 0
        ? "/sys/block/" + Devices.sysBase(owner._powerOffDisk) + "/stat" : ""
    printErrors: false
    onLoaded: if (owner) owner.notePowerSectors(text())
}
