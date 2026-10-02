// One shared list of network filesystem types for extclass, jump and ui/js/NetFs.js.
// Sample input: "fuse.sshfs" trues, "ext4" falses, "NFS4" trues, "fuse.portal" falses.
const NETWORK_FSTYPES: &[&str] = &[
    "nfs", "nfs4", "cifs", "smb3", "smbfs", "9p", "afs", "ceph", "davfs",
    "fuse.sshfs", "fuse.rclone", "fuse.s3fs", "fuse.gcsfuse", "fuse.curlftpfs",
    "fuse.juicefs", "fuse.glusterfs", "fuse.ceph-fuse", "fuse.smbnetfs",
    "fuse.davfs2", "fuse.gvfsd-fuse", "fuse.protondrive",
];

pub fn is_network_fstype(fstype: &str) -> bool {
    // Exact matches only, so local FUSE mounts and the server proc never read as remote.
    NETWORK_FSTYPES.iter().any(|kind| kind.eq_ignore_ascii_case(fstype))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_shared_list_names_each_network_kind_once() {
        for fstype in ["nfs", "nfs4", "NFS", "cifs", "smb3", "smbfs", "9p", "afs", "ceph", "davfs", "fuse.sshfs", "fuse.rclone", "fuse.s3fs", "fuse.gcsfuse", "fuse.curlftpfs", "fuse.juicefs", "fuse.glusterfs", "fuse.ceph-fuse", "fuse.smbnetfs", "fuse.davfs2", "fuse.gvfsd-fuse", "fuse.protondrive"] {
            assert!(is_network_fstype(fstype), "{} is network", fstype);
        }
        for fstype in ["ext4", "btrfs", "xfs", "vfat", "exfat", "ntfs", "ntfs3", "tmpfs", "overlay", "fuse", "fuseblk", "fuse.portal", "fuse.mergerfs", "fuse.gocryptfs", "fuse.bindfs", "fuse.squashfuse", "fuse.lxcfs", "nfsd", "sshfs", "s3fs", "davfs2", "glusterfs", "iso9660", "udf", ""] {
            assert!(!is_network_fstype(fstype), "{} stays local", fstype);
        }
    }

    // Sample input: `case "nfs":` labels, one per line or several per line, lower or any case.
    fn netfs_js_labels(text: &str) -> Vec<String> {
        let mut out = Vec::new();
        for chunk in text.split("case ") {
            let label = chunk.trim_start().strip_prefix('"').and_then(|rest| rest.split('"').next());
            if let Some(label) = label {
                if !label.is_empty() {
                    out.push(label.to_ascii_lowercase());
                }
            }
        }
        out.sort();
        out.dedup();
        out
    }

    #[test]
    fn the_js_list_matches_the_rust_list() {
        let js = netfs_js_labels(include_str!("../../ui/js/NetFs.js"));
        let mut rust: Vec<String> = NETWORK_FSTYPES.iter().map(|kind| kind.to_string()).collect();
        rust.sort();
        assert_eq!(js, rust, "ui/js/NetFs.js case labels drifted from netfs.rs");
    }
}
