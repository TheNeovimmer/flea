// Per-filesystem name rules, checked before acting so a refusal names the cause instead of EINVAL.
pub fn refuse_name(name: &str, fstype: &str, windows_names: bool) -> Option<String> {
    let fs = fstype.to_ascii_lowercase();
    // Only vfat, exfat and windows_names ntfs3 restrict names; every other filesystem takes what valid_name takes.
    let drive = match fs.as_str() {
        "vfat" | "msdos" => "vfat",
        "exfat" => "exfat",
        "ntfs3" if windows_names => "ntfs3",
        _ => return None,
    };
    // Sample input: "a:b" answers "':' is not allowed in a name on this vfat drive".
    for bad in ['"', '*', ':', '<', '>', '?', '\\', '|'] {
        if name.contains(bad) {
            return Some(format!("'{bad}' is not allowed in a name on this {drive} drive"));
        }
    }
    // Sample input: "a\x01b" answers "a name cannot hold control character U+0001 on this vfat drive".
    if let Some(control) = name.chars().find(|c| c.is_control()) {
        return Some(format!("a name cannot hold control character U+{:04X} on this {drive} drive", control as u32));
    }
    if name.ends_with('.') {
        return Some(format!("a name cannot end in a dot on this {drive} drive"));
    }
    if name.ends_with(' ') {
        return Some(format!("a name cannot end in a space on this {drive} drive"));
    }
    // Sample input: "CON" and "con.txt" answer "'CON' is reserved on this vfat drive".
    let stem = name.split('.').next().unwrap_or(name).to_ascii_uppercase();
    if is_reserved(&stem) {
        return Some(format!("'{stem}' is reserved on this {drive} drive"));
    }
    None
}

// The DOS device names vfat and exfat refuse, with or without an extension.
fn is_reserved(stem: &str) -> bool {
    const RESERVED: [&str; 22] = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5",
        "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"];
    RESERVED.contains(&stem)
}

// The fstype of the filesystem owning dir, read from the live mount table; None when unreadable.
pub fn fstype_of(dir: &std::path::Path) -> Option<String> {
    let body = std::fs::read_to_string("/proc/self/mountinfo").ok()?;
    crate::backend::mountinfo::mount_type_in(dir, &body)
}

// Whether that filesystem was mounted with windows_names, which alone makes ntfs3 restrict names.
pub fn has_windows_names(dir: &std::path::Path) -> bool {
    let Ok(body) = std::fs::read_to_string("/proc/self/mountinfo") else { return false };
    crate::backend::mountinfo::mount_options_in(dir, &body).is_some_and(|opts| opts.split(',').any(|opt| opt == "windows_names"))
}

// Sample input: dir "/media/stick/dir" answers the refusal for "a:b" when the stick is vfat.
pub fn refuse_in(dir: &std::path::Path, name: &str) -> Option<String> {
    refuse_name(name, &fstype_of(dir).unwrap_or_default(), has_windows_names(dir))
}
