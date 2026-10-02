.pragma library

// The DEVICES half of the rail: one lsblk listing turned into the rows ui/DeviceMounts.qml draws.
// Split out of ui/js/Mounts.js, which keeps the rail's shared vocabulary and the NETWORK half; a
// block device and a gvfs share have nothing in common but the rail they land in.

// Sample lsblk --bytes --json row, with the columns ui/DeviceMounts.qml asks for:
// {"name":"sda1","path":"/dev/sda1","label":"128GB","mountpoints":["/run/media/gm/128GB"],"rm":true,
//  "tran":null,"size":124656812032,"type":"part","model":null,"fstype":"vfat","parttype":"0xb",
//  "pttype":"dos","partn":1,"uuid":"A1B2-C3D4"}.
// Two row kinds come out: one "disk" row for the disk that carries /, then one "volume" row for each
// volume on every other disk. ui/DeviceMounts.qml turns these into rail entries.
function parseDevices(body, unmounted) {
    var tree
    try {
        tree = JSON.parse(String(body || ""))
    } catch (e) {
        // A parse failure returns the empty shape rather than throwing, so the rail self-hides.
        return []
    }
    var nodes = (tree && tree.blockdevices) || []
    var out = []
    var system = systemDisk(nodes)
    if (system)
        out.push({ kind: "disk", label: String(system.name), device: devicePath(system), path: "/",
                   mounted: true, removable: false, size: deviceBytes(system.size) })
    for (var i = 0; i < nodes.length; i++) {
        // The system disk is never walked: /boot and a separate home are the box's own plumbing and
        // the row above already stands for that disk. Everything else on the box is walked, which is
        // what puts a second internal drive in the rail (operator, 2026-09-11: only sticks appeared).
        if (!nodes[i].name || nodes[i] === system || isPseudo(nodes[i].name))
            continue
        // No transport to inherit at the top: the disk answers for itself inside the walk.
        collectVolumes([nodes[i]], "", false, out, unmounted === true)
    }
    return dedupeVolumes(out)
}

// zram and loop devices are type "disk" too, and neither is a disk anyone browses.
function isPseudo(name) {
    return /^(zram|loop)/.test(String(name))
}

// The disk that actually carries /, found through the mountpoints of its own subtree. It used to be
// guessed as the first non-removable disk, and with a second internal drive present that guess names
// whichever disk lsblk lists first: the wrong drive was then labelled with the hostname and pointed
// at /, while the real system disk had no row at all.
function systemDisk(nodes) {
    for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].name && holdsRoot(nodes[i]))
            return nodes[i]
    }
    return null
}

function holdsRoot(node) {
    var points = node.mountpoints || []
    for (var i = 0; i < points.length; i++) {
        if (points[i] === "/")
            return true
    }
    var kids = node.children || []
    for (var k = 0; k < kids.length; k++) {
        if (holdsRoot(kids[k]))
            return true
    }
    return false
}

// A volume earns a rail row when it can be unplugged, which is a stick whether or not anything
// mounted it, or when it is mounted, which is every internal drive the operator actually uses.
// RailAdditions rule 1 adds the third case behind its own switch: a volume nothing has mounted, with
// a filesystem to browse. With the switch off this is the 0.2.1 rule exactly, which kept a spare EFI
// or recovery partition out of the rail.
function collectVolumes(nodes, model, unplugs, out, unmounted) {
    for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i]
        var kids = n.children || []
        // Only the disk carries a product name, so it is passed down to its own partitions.
        var own = n.model ? String(n.model) : model
        // Only the disk carries the transport, so its partitions take its answer: measured by
        // mariobgsp (PR 74), whose USB drive reports tran=usb on sdb and null on sdb1. It stops
        // there: what a crypt leaf under it reads as is what it read as before that PR.
        var pulls = unpluggable(n) || (unplugs && String(n.type || "") === "part")
        // The hide rule runs in every branch: a removable ESP, swap or member is no row on any setting.
        if (n.name && kids.length === 0 && !hidden(n)
                && (pulls || mountOf(n).length > 0 || (unmounted && browsable(n))))
            out.push(volumeRow(n, own, pulls, unmounted))
        collectVolumes(kids, own, pulls, out, unmounted)
    }
}

// A leaf udisks hides is no row in any branch: no filesystem, a non-filesystem type, a firmware or
// system partition type, a vendor recovery label, or a mount only the system itself uses.
function hidden(n) {
    if (mountOf(n).length === 0 && String(n.fstype || "").length === 0)
        return true // H1: a partition with no filesystem and nothing mounted.
    var fs = String(n.fstype || "").toLowerCase()
    if (fs === "swap" || fs.slice(-7) === "_member" || fs === "bcache" || fs === "ceph" || fs === "drbd")
        return true // H2: swap, LVM and RAID members, and other non-filesystem types.
    if (fs.indexOf("crypto_") === 0)
        return false // The Unlock board keeps a locked LUKS container as a row.
    if (isFirmwarePart(n) && !isIsohybridKeep(n))
        return true // H3: ESP, MSR, BIOS boot, WinRE GUID or MBR type, except an installer ISO part.
    if (isRecoveryLabel(n))
        return true // H4: System Reserved and vendor recovery labels on ntfs or vfat.
    if (isSystemMountOnly(n))
        return true // H5: mounted only where the system itself lives, never a user folder.
    return false
}

// GPT GUIDs and MBR numbers udisks hides (80-udisks2.rules); PARTTYPE is a lowercase GUID on GPT
// and 0xNN on MBR, compared numerically because lsblk drops the leading zero.
function isFirmwarePart(n) {
    var raw = String(n.parttype || "")
    if (raw.length === 0)
        return false
    var lower = raw.toLowerCase()
    if (lower.indexOf("-") >= 0)
        return gptHidden(lower)
    var num = parseInt(lower, 16)
    if (isNaN(num))
        return false // An unparsable type hides nothing rather than everything.
    return mbrHidden(num)
}

// Sample input: "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" trues, "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7" falses.
function gptHidden(lower) {
    var hide = ["c12a7328-f81f-11d2-ba4b-00a0c93ec93b", "21686148-6449-6e6f-744e-656564454649",
        "e3c9e316-0b5c-4db8-817d-f92df00215ae", "de94bba4-06d1-4d40-a16a-bfd50179d6ac",
        "bc13c2ff-59e6-4262-a352-b275fd6f7172", "426f6f74-0000-11aa-aa11-00306543ecac",
        "a19d880f-05fc-4d3b-a006-743f0f84911e", "e6d6d379-f507-44c2-a23c-238f2a3df928"]
    for (var i = 0; i < hide.length; i++)
        if (lower === hide[i])
            return true
    return false
}

// Sample input: 0x27 trues, 0x7 falses; 0x0 hides unless the isohybrid keep below answers first.
function mbrHidden(num) {
    var hide = [0x0, 0x5, 0xf, 0x85, 0x11, 0x12, 0x14, 0x16, 0x17, 0x1b, 0x1c, 0x1e, 0x27, 0x3d,
        0x84, 0x8d, 0x8e, 0x90, 0x91, 0x92, 0x93, 0x97, 0x98, 0x9a, 0x9b, 0xab, 0xbb, 0xc2, 0xc3, 0xdd, 0xef, 0xfd]
    for (var i = 0; i < hide.length; i++)
        if (num === hide[i])
            return true
    return false
}

// Sample input: dos with 0x0 part 1 iso9660 keeps, the same part as vfat hides; udisks isohybrid undo.
function isIsohybridKeep(n) {
    if (String(n.pttype || "").toLowerCase() !== "dos")
        return false
    var num = parseInt(String(n.parttype || ""), 16)
    if (!(num === 0x0 || num === 0x17))
        return false
    var partn = String(n.partn == null ? "" : n.partn)
    if (!(partn === "1" || partn === "2"))
        return false
    var fs = String(n.fstype || "").toLowerCase()
    return fs === "iso9660" || fs === "udf"
}

// Sample input: ntfs "System Reserved" trues, ext4 "System Reserved" falses; spaces read as udev writes them.
function isRecoveryLabel(n) {
    var fs = String(n.fstype || "").toLowerCase()
    if (!(fs === "ntfs" || fs === "vfat"))
        return false
    var label = String(n.label || "").replace(/ /g, "_")
    var hide = ["Recovery", "RECOVERY", "Lenovo_Recovery", "HP_RECOVERY", "Recovery_Partition",
        "DellUtility", "DellRestore", "IBM_SERVICE", "SERVICEV001", "SERVICEV002",
        "SYSTEM_RESERVED", "System_Reserved", "WINRE_DRV", "DIAGS", "IntelRST"]
    for (var i = 0; i < hide.length; i++)
        if (label === hide[i])
            return true
    return false
}

// Sample input: ["/"] trues, ["/mnt/data"] falses; every mountpoint must be system for the row to hide.
function isSystemMountOnly(n) {
    var points = []
    var raw = n.mountpoints || []
    for (var i = 0; i < raw.length; i++) {
        var p = raw[i] === null ? "" : String(raw[i])
        if (p.length > 0 && p.charAt(0) === "/")
            points.push(p)
    }
    if (points.length === 0)
        return false
    for (var j = 0; j < points.length; j++)
        if (!isSystemPath(points[j]))
            return false
    return true
}

// Sample input: "/boot/efi" trues, "/run/media/gm/128GB" falses; glib system prefixes plus dot parts.
function isSystemPath(p) {
    if (p === "/" || p.indexOf("/.") >= 0)
        return true
    var roots = ["/boot", "/home", "/opt", "/srv", "/tmp", "/usr", "/var", "/dev", "/proc", "/sys"]
    for (var i = 0; i < roots.length; i++)
        if (p === roots[i] || p.indexOf(roots[i] + "/") === 0)
            return true
    return false
}

// One row per device path and per filesystem UUID: an md repeat lists the same path twice and a
// multi-device btrfs shares one UUID, so the first mounted row wins and any later copy goes.
function dedupeVolumes(rows) {
    if (rows.length === 0)
        return rows
    var head = [rows[0]]
    var byUuid = {}
    var at = {}
    for (var i = 1; i < rows.length; i++) {
        var r = rows[i]
        var dkey = String(r.device || "")
        var ukey = String(r.uuid || "")
        var dup = -1
        if (dkey.length > 0 && at[dkey] !== undefined)
            dup = at[dkey]
        else if (ukey.length > 0 && byUuid[ukey] !== undefined)
            dup = byUuid[ukey]
        if (dup < 0) {
            at[dkey] = head.length
            if (ukey.length > 0)
                byUuid[ukey] = head.length
            head.push(r)
        } else if (r.mounted === true && head[dup].mounted !== true) {
            at[dkey] = dup
            if (ukey.length > 0)
                byUuid[ukey] = dup
            head[dup] = r
        }
    }
    return head
}

// RailAdditions rule 1's switch gate: a real filesystem to browse, kept for old lsblk bodies
// without PARTTYPE; the hide rule above already answers the same for new bodies in every branch.
function browsable(n) {
    var fs = String(n.fstype || "").toLowerCase()
    if (fs.length === 0 || fs === "swap" || fs.indexOf("crypto_") === 0)
        return false
    return String(n.parttypename || "").toLowerCase().indexOf("efi") < 0
}

// A drive somebody can pull out, which is what Eject is for. RM alone is not the answer: a USB
// bridge (a WD My Passport, PR 74) reports rm=false and is still a drive you unplug, while a hot-swap
// SATA bay reports its own hotplug and is not, which is why the transport decides and not that.
function unpluggable(n) {
    return !!n && (n.rm === true || String(n.tran || "").toLowerCase() === "usb")
}

// Sample: ["/home", "/var/log", "/"] for one btrfs device with several subvolumes mounted, ["[SWAP]"]
// for swap, which is no directory, and [null] for a volume nothing has mounted. The first real path
// wins, which is also what drops swap: only a mountpoint is browsable and only one row is drawn.
function mountOf(node) {
    var points = node.mountpoints || []
    for (var i = 0; i < points.length; i++) {
        var point = points[i] === null ? "" : String(points[i])
        if (point.length > 0 && point.charAt(0) === "/")
            return point
    }
    return ""
}

// lsblk's own PATH column, because a device-mapper leaf lives at /dev/mapper/<name> and "/dev/" plus
// its kernel name is a path that does not exist. gio is handed this, so it has to be the real one.
function devicePath(node) {
    return node.path ? String(node.path) : "/dev/" + String(node.name)
}

// The label ladder is the filesystem label, then the drive's product name, then the kernel name.
// volumeMenu says the row was built under RailAdditions rule 1, which is what gives it the Mount,
// Open and Unmount rows; without the switch the row carries the menu it carried in 0.2.1.
function volumeRow(n, model, unplugs, unmounted) {
    var path = mountOf(n)
    var label = n.label ? String(n.label) : (model.length > 0 ? model : String(n.name))
    return { kind: "volume", label: label, device: devicePath(n), path: path, mounted: path.length > 0,
             removable: unplugs === true, size: deviceBytes(n.size), volumeMenu: unmounted === true,
             uuid: n.uuid ? String(n.uuid) : "" }
}

// An unavailable or malformed capacity stays absent; only the delegate formats valid byte counts.
function deviceBytes(value) {
    return Number.isSafeInteger(value) && value >= 0 ? value : null
}
