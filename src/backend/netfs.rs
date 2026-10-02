// One shared list of network filesystem types for extclass, jump and ui/js/NetFs.js.
// Sample input: "fuse.sshfs" trues, "ext4" falses, "NFS4" trues, "fuse.portal" falses.
pub fn is_network_fstype(fstype: &str) -> bool {
    // Exact matches only, so local FUSE mounts and the server proc never read as remote.
    matches!(
        fstype.to_ascii_lowercase().as_str(),
        "nfs" | "nfs4" | "cifs" | "smb3" | "smbfs" | "9p" | "afs" | "ceph" | "davfs"
            | "fuse.sshfs" | "fuse.rclone" | "fuse.s3fs" | "fuse.gcsfuse" | "fuse.curlftpfs"
            | "fuse.juicefs" | "fuse.glusterfs" | "fuse.ceph-fuse" | "fuse.smbnetfs"
            | "fuse.davfs2" | "fuse.gvfsd-fuse"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_shared_list_names_each_network_kind_once() {
        for fstype in ["nfs", "nfs4", "NFS", "cifs", "smb3", "smbfs", "9p", "afs", "ceph", "davfs", "fuse.sshfs", "fuse.rclone", "fuse.s3fs", "fuse.gcsfuse", "fuse.curlftpfs", "fuse.juicefs", "fuse.glusterfs", "fuse.ceph-fuse", "fuse.smbnetfs", "fuse.davfs2", "fuse.gvfsd-fuse"] {
            assert!(is_network_fstype(fstype), "{} is network", fstype);
        }
        for fstype in ["ext4", "btrfs", "xfs", "vfat", "exfat", "ntfs", "ntfs3", "tmpfs", "overlay", "fuse", "fuseblk", "fuse.portal", "fuse.mergerfs", "fuse.gocryptfs", "fuse.bindfs", "fuse.squashfuse", "fuse.lxcfs", "fuse.protondrive", "nfsd", "sshfs", "s3fs", "davfs2", "glusterfs", "iso9660", "udf", ""] {
            assert!(!is_network_fstype(fstype), "{} stays local", fstype);
        }
    }
}
