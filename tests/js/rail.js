.import "../../ui/js/Devices.js" as Devices
.import "../../ui/js/Mounts.js" as Mounts
.import "../../ui/js/Eject.js" as Eject
.import "../../ui/js/Cloud.js" as Cloud
.import "../../ui/js/NetFs.js" as NetFs

// RailAdditions rules 1 and 2: the volumes nothing has mounted, behind their own switch, and the
// menu those rows carry. Split out of tests/js/devices.js, which keeps the 0.2.1 rail's own parse.

// One internal disk carrying /, a second drive with five volumes, one of each exception the rule
// names. fstype and parttypename are what it reads, and tests/js/devices.js's live listing predates
// both columns, which is the other half of why this fixture is its own.
var unmountedBox = '{"blockdevices":['
                 + '{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,'
                 + '"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null,"fstype":"btrfs","parttypename":"Linux filesystem"}]},'
                 + '{"name":"sdb","path":"/dev/sdb","label":null,"mountpoints":[null],"rm":false,"size":2000398934016,"type":"disk","model":"Samsung SSD 870","fstype":null,"parttypename":null,'
                 + '"children":[{"name":"sdb1","path":"/dev/sdb1","label":"Archive","mountpoints":[null],"rm":false,"size":1000398934016,"type":"part","model":null,"fstype":"ext4","parttypename":"Linux filesystem"},'
                 + '{"name":"sdb2","path":"/dev/sdb2","label":null,"mountpoints":[null],"rm":false,"size":536870912,"type":"part","model":null,"fstype":"vfat","parttypename":"EFI System"},'
                 + '{"name":"sdb3","path":"/dev/sdb3","label":null,"mountpoints":["[SWAP]"],"rm":false,"size":8589934592,"type":"part","model":null,"fstype":"swap","parttypename":"Linux swap"},'
                 + '{"name":"sdb4","path":"/dev/sdb4","label":null,"mountpoints":[null],"rm":false,"size":268435456,"type":"part","model":null,"fstype":null,"parttypename":"Linux filesystem"},'
                 + '{"name":"sdb5","path":"/dev/sdb5","label":null,"mountpoints":[null],"rm":false,"size":268435456,"type":"part","model":null,"fstype":"crypto_LUKS","parttypename":"Linux filesystem"}]}'
                 + ']}'

function labels(rows) {
    return rows.map(function (e) { return e.label }).join(",")
}

function run(check) {
    var off = Devices.parseDevices(unmountedBox, false)
    check("with the switch off the rail is the one 0.2.1 drew", labels(off), "nvme0n1")
    var on = Devices.parseDevices(unmountedBox, true)
    check("the volume nothing mounted joins the rail, and only it", labels(on), "nvme0n1,Archive")
    check("the unmounted volume reads as unmounted", on[1].mounted, false)
    check("it has no mountpoint to open, so it has no path", on[1].path, "")
    check("it keeps the RailDetails column's own size", on[1].size, 1000398934016)
    check("it is not removable, so nothing offers to eject a fixed disk", on[1].removable, false)
    check("and it carries its device node, which is what gio mounts", on[1].device, "/dev/sdb1")
    check("only a row built under the switch carries the board's own menu", on[1].volumeMenu, true)
    // A stick is a row either way, so it is the one that says what the switch does to an existing row.
    var stickBox = '{"blockdevices":[{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"size":124656812032,"type":"disk","model":"USB Flash Disk","fstype":null,"parttypename":null,'
              + '"children":[{"name":"sda1","path":"/dev/sda1","label":"128GB","mountpoints":["/run/media/gm/128GB"],"rm":true,"size":124656812032,"type":"part","model":null,"fstype":"vfat","parttypename":"W95 FAT32"}]}]}'
    check("and a row built without it carries the menu it carried in 0.2.1",
          Devices.parseDevices(stickBox, false)[0].volumeMenu, false)

    // Rule 1's three exceptions, each named by lsblk rather than guessed from a name.
    check("swap is not a place to browse", labels(on).indexOf("sdb3"), -1)
    check("the EFI system partition is the box's own plumbing", labels(on).indexOf("sdb2"), -1)
    check("a volume with no filesystem has nothing to mount", labels(on).indexOf("sdb4"), -1)
    check("a locked LUKS container mounts through its crypt child, never itself", labels(on).indexOf("sdb5"), -1)

    // A USB LUN with media but no filesystem is not a rail row, removable or not.
    function bootBox(sda) {
        return '{"blockdevices":['
            + '{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,'
            + '"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null,"fstype":"btrfs","parttypename":"Linux filesystem"}]},'
            + sda + ']}'
    }
    var bootLun = '{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"tran":"usb","size":4194304,"type":"disk","model":"USB bootloader","fstype":null,"parttypename":null}'
    check("a no-filesystem USB LUN is not a row with the switch on", labels(Devices.parseDevices(bootBox(bootLun), true)), "nvme0n1")
    check("a no-filesystem USB LUN is not a row with the switch off", labels(Devices.parseDevices(bootBox(bootLun), false)), "nvme0n1")
    var bootChild = '{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":false,"tran":"usb","size":4194304,"type":"disk","model":"USB bootloader","fstype":null,"parttypename":null,'
        + '"children":[{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":4194304,"type":"part","model":null,"fstype":null,"parttypename":null}]}'
    check("a no-filesystem child on a USB disk is not a row either", labels(Devices.parseDevices(bootBox(bootChild), true)), "nvme0n1")
    check("null, empty and absent fstype all mean no filesystem",
        [bootLun, bootLun.replace('"fstype":null', '"fstype":""'), bootLun.replace(',"fstype":null', '')].every(function (leaf) {
            return labels(Devices.parseDevices(bootBox(leaf), true)) === "nvme0n1"
        }), true)
    check("the same LUN with a filesystem is still a row", labels(Devices.parseDevices(bootBox(bootLun.replace('"fstype":null', '"fstype":"vfat"')), true)), "nvme0n1,USB bootloader")
    function stickPart(leaf) {
        return '{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"tran":"usb","size":124656812032,"type":"disk","model":"USB bootloader","fstype":null,"parttypename":null,'
            + '"children":[' + leaf + ']}'
    }
    function romLeaf(fs) {
        var fstype = fs === null ? "null" : '"' + fs + '"'
        return '{"name":"sr0","path":"/dev/sr0","label":null,"mountpoints":[null],"rm":true,"size":0,"type":"rom","model":"MATSHITA DVD+/-RW UJ8FB","fstype":' + fstype + '}'
    }
    var espLeaf = '{"name":"sda1","path":"/dev/sda1","label":"BOOT","mountpoints":[null],"rm":true,"tran":null,"size":536870912,"type":"part","model":null,"fstype":"vfat","parttypename":"EFI System","parttype":"c12a7328-f81f-11d2-ba4b-00a0c93ec93b","pttype":"gpt","partn":1,"uuid":"A1B2-C3D4"}'
    check("an EFI system partition on a stick is hidden on every setting", labels(Devices.parseDevices(bootBox(stickPart(espLeaf)), true)), "nvme0n1")
    check("and it stays hidden with the switch off", labels(Devices.parseDevices(bootBox(stickPart(espLeaf)), false)), "nvme0n1")
    var cryptLeaf = '{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":true,"tran":null,"size":8589934592,"type":"part","model":null,"fstype":"crypto_LUKS","parttypename":"Linux filesystem"}'
    check("an unmounted crypto_LUKS stick partition is still a row", labels(Devices.parseDevices(bootBox(stickPart(cryptLeaf)), true)), "nvme0n1,USB bootloader")
    check("a no-filesystem leaf that is somehow mounted is still a row",
        labels(Devices.parseDevices(bootBox(bootLun.replace('[null]', '["/run/media/gm/BOOT"]')), true)), "nvme0n1,USB bootloader")
    check("an empty rom stays hidden through the same guard", labels(Devices.parseDevices(bootBox(romLeaf(null)), true)), "nvme0n1")
    check("an iso9660 rom is still a row", labels(Devices.parseDevices(bootBox(romLeaf("iso9660")), true)), "nvme0n1,MATSHITA DVD+/-RW UJ8FB")

    // Every hidden class, each mirrored in tests/fake-lsblk.sh for the native battery.
    function hideLeaf(leaf) { return labels(Devices.parseDevices(bootBox(stickPart(leaf)), true)) }
    function hideLeafOff(leaf) { return labels(Devices.parseDevices(bootBox(stickPart(leaf)), false)) }
    var sysLeaf = '{"name":"sda1","path":"/dev/sda1","label":"System Reserved","mountpoints":[null],"rm":false,"tran":null,"size":52428800,"type":"part","model":null,"fstype":"ntfs","parttypename":null,"parttype":"0x7","pttype":"dos","partn":1,"uuid":"2222222222222222"}'
    check("System Reserved hides on every setting", hideLeaf(sysLeaf), "nvme0n1")
    check("and it stays hidden with the switch off", hideLeafOff(sysLeaf), "nvme0n1")
    var winLeaf = '{"name":"sda2","path":"/dev/sda2","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":524288000,"type":"part","model":null,"fstype":"ntfs","parttypename":null,"parttype":"0x27","pttype":"dos","partn":2,"uuid":"3333333333333333"}'
    check("a 0x27 WinRE partition hides", hideLeaf(winLeaf), "nvme0n1")
    var msrLeaf = '{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":16777216,"type":"part","model":null,"fstype":null,"parttypename":null,"parttype":"e3c9e316-0b5c-4db8-817d-f92df00215ae","pttype":"gpt","partn":1,"uuid":null}'
    check("an MSR partition hides", hideLeaf(msrLeaf), "nvme0n1")
    var pvLeaf = '{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":1073741824,"type":"part","model":null,"fstype":"LVM2_member","parttypename":null,"parttype":"0x8e","pttype":"dos","partn":1,"uuid":"44444444-4444-4444-4444-444444444444"}'
    check("an LVM PV hides", hideLeaf(pvLeaf), "nvme0n1")
    check("and it stays hidden with the switch off", hideLeafOff(pvLeaf), "nvme0n1")
    var raidLeaf = '{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":1073741824,"type":"part","model":null,"fstype":"linux_raid_member","parttypename":null,"parttype":"0xfd","pttype":"dos","partn":1,"uuid":"55555555-5555-5555-5555-555555555555"}'
    check("a RAID member hides", hideLeaf(raidLeaf), "nvme0n1")
    var swapLeaf = '{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":["[SWAP]"],"rm":true,"tran":null,"size":268435456,"type":"part","model":null,"fstype":"swap","parttypename":"Linux swap","parttype":"0x82","pttype":"dos","partn":1,"uuid":"66666666-6666-6666-6666-666666666666"}'
    check("swap on a stick hides on every setting", hideLeaf(swapLeaf), "nvme0n1")
    check("and it stays hidden with the switch off", hideLeafOff(swapLeaf), "nvme0n1")
    var nofsLeaf = '{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":true,"tran":null,"size":268435456,"type":"part","model":null,"fstype":null,"parttypename":null,"parttype":null,"pttype":"dos","partn":1,"uuid":null}'
    check("a partition with no filesystem hides", hideLeaf(nofsLeaf), "nvme0n1")
    var isoLeaf = '{"name":"sda1","path":"/dev/sda1","label":"FLEA-ISO","mountpoints":[null],"rm":true,"tran":null,"size":1073741824,"type":"part","model":null,"fstype":"iso9660","parttypename":null,"parttype":"0x0","pttype":"dos","partn":1,"uuid":"88888888-8888-8888-8888-888888888888"}'
    check("an isohybrid ISO partition stays a row", hideLeaf(isoLeaf), "nvme0n1,FLEA-ISO")
    var dupBody = '{"blockdevices":[{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null}]},'
        + '{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"tran":"usb","size":124656812032,"type":"disk","model":"Stick","fstype":null,"parttypename":null,"children":[{"name":"sda1","path":"/dev/sda1","label":"A","mountpoints":["/run/media/gm/A"],"rm":true,"size":1000,"type":"part","model":null,"fstype":"vfat","uuid":"9999"},{"name":"sda1","path":"/dev/sda1","label":"A","mountpoints":["/run/media/gm/A"],"rm":true,"size":1000,"type":"part","model":null,"fstype":"vfat","uuid":"9999"}]}]}'
    check("a repeated PATH names one row, not two", Devices.parseDevices(dupBody, true).length, 2)

    // Rule 2's rows, which only a row from rule 1 carries.
    function solid(rows) { return rows.filter(function (r) { return r.separator !== true }) }
    var unmounted = { group: "device", kind: "volume", mounted: false, removable: false, volumeMenu: true }
    check("an unmounted volume offers the mount its own activation does",
          solid(Mounts.railMenu(unmounted)).map(function (r) { return r.label + ":" + r.action }).join(","), "Mount:mountVolume")
    var mounted = { group: "device", kind: "volume", mounted: true, removable: false, volumeMenu: true }
    check("a mounted one offers the open beside the release",
          solid(Mounts.railMenu(mounted)).map(function (r) { return r.label + ":" + r.action }).join(","),
          "Open:open,Unmount:unmountVolume")
    var stick = { group: "device", kind: "volume", mounted: true, removable: true, volumeMenu: true }
    check("and Eject stays where it stands today, on a volume somebody can pull out",
          solid(Mounts.railMenu(stick)).map(function (r) { return r.label }).join(","), "Open,Unmount,Eject")
    check("with the switch off a mounted stick opens beside its eject",
          solid(Mounts.railMenu({ group: "device", kind: "volume", mounted: true, removable: true })).map(function (r) { return r.label }).join(","),
          "Open,Eject")
    check("and an unmounted one opens no menu at all",
          Mounts.railMenu({ group: "device", kind: "volume", mounted: false, removable: true }).length, 0)

    // CloudMounts: a FUSE mount inside the home folder shows in NETWORK under its
    // folder's name. Sample input, /proc/self/mountinfo lines (id parent maj:min root
    // mountpoint options, then fstype source superoptions):
    // 23 1 8:1 / /home/u/gdrive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000
    // 24 1 8:1 / /home/u/My\040Drive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000
    // 31 1 0:27 / /home/u/ProtonDrive rw,nosuid,nodev - fuse.protondrive proton: rw,user_id=1000
    // 18 1 8:1 / /home/u rw,nosuid,nodev - btrfs /dev/sda1 rw
    // 40 1 0:40 / /run/user/1000/gvfs rw,nosuid,nodev - fuse.gvfsd-fuse gvfsd-fuse rw,user_id=1000
    var mountsBody = "23 1 8:1 / /home/u/gdrive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000\n"
        + "24 1 8:1 / /home/u/My\\040Drive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000\n"
        + "31 1 0:27 / /home/u/ProtonDrive rw,nosuid,nodev - fuse.protondrive proton: rw,user_id=1000\n"
        + "18 1 8:1 / /home/u rw,nosuid,nodev - btrfs /dev/sda1 rw\n"
        + "40 1 0:40 / /run/user/1000/gvfs rw,nosuid,nodev - fuse.gvfsd-fuse gvfsd-fuse rw,user_id=1000\n"
    var clouds = Cloud.parseCloudMounts(mountsBody, "/home/u")
    check("three FUSE mounts inside home parse to three rows", clouds.length, 3)
    check("the first row names the folder's own path", clouds[0].path, "/home/u/gdrive")
    check("an octal escape decodes to the folder's real name", clouds[1].path, "/home/u/My Drive")
    check("the home directory itself is not a cloud mount",
          clouds.some(function (c) { return c.path === "/home/u" }), false)
    check("the gvfs FUSE mount is not inside home and stays out",
          clouds.some(function (c) { return c.path.indexOf("/run/") === 0 }), false)
    check("an empty body parses to nothing", Cloud.parseCloudMounts("", "/home/u").length, 0)
    check("garbage parses to nothing", Cloud.parseCloudMounts("not mountinfo at all\n", "/home/u").length, 0)
    check("no home means no rows", Cloud.parseCloudMounts(mountsBody, "").length, 0)
    check("a stacked mountpoint names one row, not two",
          Cloud.parseCloudMounts(mountsBody + "44 1 0:44 / /home/u/gdrive rw - fuse.rclone remote: rw\n", "/home/u").length, 3)

    // The row itself: a server mark and a green square, and no menu at defaults, like
    // Dropbox's row, because the tool that made the mount owns it.
    var grow = { label: "gdrive", group: "network", kind: "cloud", uri: "", path: "/home/u/gdrive", mounted: true, glyph: "server" }
    check("a cloud row draws the server mark", grow.glyph, "server")
    check("a cloud row offers no menu row", Mounts.railMenu(grow).length, 0)
    check("and no right-click row either", Mounts.rowMenu(grow).length, 0)
    check("and no eject mark either", Eject.releasable(grow), false)

    // One shared network list: NetFs answers what Rust netfs answers, so the rail and the loop agree.
    check("nfs names network", NetFs.isNetworkFstype("nfs"), true)
    check("nfs4 names network", NetFs.isNetworkFstype("nfs4"), true)
    check("cifs names network", NetFs.isNetworkFstype("cifs"), true)
    check("smb3 names network", NetFs.isNetworkFstype("smb3"), true)
    check("davfs names network", NetFs.isNetworkFstype("davfs"), true)
    check("fuse.sshfs names network", NetFs.isNetworkFstype("fuse.sshfs"), true)
    check("fuse.rclone names network", NetFs.isNetworkFstype("fuse.rclone"), true)
    check("fuse.s3fs names network", NetFs.isNetworkFstype("fuse.s3fs"), true)
    check("fuse.gvfsd-fuse names network for the storage class", NetFs.isNetworkFstype("fuse.gvfsd-fuse"), true)
    check("ext4 stays local", NetFs.isNetworkFstype("ext4"), false)
    check("bare fuse stays local", NetFs.isNetworkFstype("fuse"), false)
    check("fuseblk stays local", NetFs.isNetworkFstype("fuseblk"), false)
    check("the document portal stays local", NetFs.isNetworkFstype("fuse.portal"), false)
    check("a local mergerfs stays local", NetFs.isNetworkFstype("fuse.mergerfs"), false)
    check("gocryptfs stays local", NetFs.isNetworkFstype("fuse.gocryptfs"), false)
    check("nfsd stays local", NetFs.isNetworkFstype("nfsd"), false)
    check("a bare sshfs stays local", NetFs.isNetworkFstype("sshfs"), false)
    // Kernel and outside-home FUSE mounts become NETWORK rows without a per-row stat.
    var netBody = "30 1 0:45 / /mnt/nas rw - nfs nas:/share rw\n"
        + "31 1 0:46 / /media/smb rw - cifs //nas/media rw\n"
        + "32 1 0:47 / /mnt/ssh rw - fuse.sshfs user@h:/ rw\n"
        + "33 1 0:48 / /home/u/gdrive rw - fuse.rclone remote: rw\n"
        + "40 1 0:40 / /run/user/1000/gvfs rw - fuse.gvfsd-fuse gvfsd-fuse rw\n"
    var nets = Cloud.parseNetworkMounts(netBody, "/home/u")
    check("kernel nfs, cifs and outside-home sshfs become rows", nets.length, 3)
    check("the inside-home rclone stays a cloud row, not a second one",
        nets.some(function (n) { return n.path === "/home/u/gdrive" }), false)
    check("the gvfs root never becomes a row",
        nets.some(function (n) { return n.path.indexOf("/run/") === 0 }), false)
    // The portal, the bridge, the server proc and a local FUSE mount never become rows.
    var narrowBody = "10 1 0:50 / /run/user/1000/doc rw - fuse.portal portal rw\n"
        + "11 1 0:40 / /run/user/1000/gvfs rw - fuse.gvfsd-fuse gvfsd-fuse rw\n"
        + "12 1 0:51 / /proc/fs/nfsd rw - nfsd nfsd rw\n"
        + "13 1 8:1 / /mnt/merge rw - fuse.mergerfs merge rw\n"
        + "14 1 0:45 / /mnt/nas rw - nfs nas:/share rw\n"
    var narrow = Cloud.parseNetworkMounts(narrowBody, "/home/u")
    check("portal, bridge, nfsd and mergerfs beside one NFS yield exactly it",
        narrow.length === 1 && narrow[0].path === "/mnt/nas", true)
}

