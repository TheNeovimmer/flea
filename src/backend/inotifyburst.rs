// The one walk over a buffer of inotify events, shared by the open folder's watch and the columns' peek watch.

// One inotify_event is a watch descriptor, a mask, a cookie and a name length, then the name.
pub(crate) const EVENT_HEADER: usize = 16;

// Sample input: IN_CREATE on wd 3 and IN_IGNORED on wd 7 call seen with (3, 0x100) and (7, 0x8000).
pub(crate) fn each_event(buf: &[u8], mut seen: impl FnMut(i32, u32)) {
    let mut at = 0;
    while at + EVENT_HEADER <= buf.len() {
        let wd = i32::from_ne_bytes([buf[at], buf[at + 1], buf[at + 2], buf[at + 3]]);
        let mask = u32::from_ne_bytes([buf[at + 4], buf[at + 5], buf[at + 6], buf[at + 7]]);
        let len = u32::from_ne_bytes([buf[at + 12], buf[at + 13], buf[at + 14], buf[at + 15]]) as usize;
        seen(wd, mask);
        // The loop condition is the bound that keeps this indexing inside the slice.
        at += EVENT_HEADER + len;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Sample input: wd 3 with IN_CREATE then a 8 byte name, wd 7 with IN_IGNORED and no name.
    fn burst() -> Vec<u8> {
        let mut out = Vec::new();
        for (wd, mask, name) in [(3i32, 0x100u32, &b"a.txt\0\0\0"[..]), (7, 0x8000, &b""[..])] {
            out.extend_from_slice(&wd.to_ne_bytes());
            out.extend_from_slice(&mask.to_ne_bytes());
            out.extend_from_slice(&0u32.to_ne_bytes());
            out.extend_from_slice(&(name.len() as u32).to_ne_bytes());
            out.extend_from_slice(name);
        }
        out
    }

    #[test]
    fn every_event_in_a_burst_is_seen_with_its_mask() {
        let mut seen = Vec::new();
        each_event(&burst(), |wd, mask| seen.push((wd, mask)));
        assert_eq!(seen, vec![(3, 0x100), (7, 0x8000)]);
    }

    // Not a shape inotify produces: it pins the bound, so a length running past the slice cannot panic.
    #[test]
    fn a_truncated_tail_ends_the_walk() {
        let mut buf = burst();
        buf.truncate(buf.len() - 4);
        let mut seen = Vec::new();
        each_event(&buf, |wd, _| seen.push(wd));
        assert_eq!(seen, vec![3]);
    }
}
