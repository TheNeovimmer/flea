// The subtree walk behind a search request, ticked a slice at a time so a cancel is never blocked.
use crate::backend::fuzzy::{rank_order, Fuzzy};
use crate::backend::listing::Listing;
use std::path::PathBuf;
use std::time::Instant;

// One tick reads this many directories before the loop looks at its channel again, the same "one at a time" idea dirsize uses.
const DIRS_PER_TICK: usize = 4;

pub struct Search {
    root: PathBuf,
    // Folded once by Fuzzy, because the comparison runs once per entry and the query never changes mid-walk.
    fuzzy: Fuzzy,
    hidden: bool,
    // Directories still to read, each a path relative to root; the empty string is root itself.
    pending: Vec<String>,
    // One score per pushed match, in push order, so ranking is a permutation of the listing's spans.
    scores: Vec<i32>,
    pub scanned: usize,
    pub started: Instant,
}

impl Search {
    pub fn new(root: &str, query: &str, hidden: bool) -> Search {
        Search {
            root: PathBuf::from(root),
            fuzzy: Fuzzy::new(query),
            hidden,
            pending: vec![String::new()],
            scores: Vec::new(),
            scanned: 0,
            started: Instant::now(),
        }
    }

    // Returns true when the walk is finished; the caller then writes the terminal line.
    pub fn step(&mut self, listing: &mut Listing) -> bool {
        for _ in 0..DIRS_PER_TICK {
            match self.pending.pop() {
                Some(rel) => self.read_one(&rel, listing),
                None => return true,
            }
        }
        self.pending.is_empty()
    }

    fn read_one(&mut self, rel: &str, listing: &mut Listing) {
        let dir = if rel.is_empty() { self.root.clone() } else { self.root.join(rel) };
        let body = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
        // One bound for opendir, getdents and d_type together, so a dead server costs one deadline, never one per entry.
        let owned = dir.clone();
        let entries = match super::iomount::call(&dir, &body, "search", move || read_entries(&owned)) {
            Ok(entries) => entries,
            _ => return,
        };
        for (name, is_dir) in entries {
            // corner: a dot-prefixed name is dropped before it is counted, matching scan.rs's own hidden rule.
            if !self.hidden && name.starts_with('.') {
                continue;
            }
            self.scanned += 1;
            let child = if rel.is_empty() { name.clone() } else { format!("{}/{}", rel, name) };
            // The candidate is the whole relative path, not the base name, so one query can span a
            // separator: "dwnhelp" reaches "downloads/helper.txt", see docs/protocol.md "search".
            if let Some(score) = self.fuzzy.score(&child) {
                // The row's name is its path relative to the root, so base.join(name) still reaches the file and every per-row facility works unchanged.
                listing.push(&child, is_dir);
                self.scores.push(score);
            }
            // corner: a symlink reports its own type here, so a link to a directory is never descended and no loop is possible.
            if is_dir {
                self.pending.push(child);
            }
        }
    }

    // The walk appends in discovery order, so ranking is one permutation of the spans at the end and
    // the name arena never moves. Answers whether the row order changed, because a new order
    // invalidates every outstanding row index the same way a sort does.
    pub fn rank(&self, listing: &mut Listing) -> bool {
        // A listing this walk did not fill by itself is never reordered: the scores would name other rows.
        if self.scores.len() != listing.len() || listing.len() < 2 {
            return false;
        }
        // Take the buffer out so the comparator can borrow it while spans are moved, as sort.rs does.
        let names = std::mem::take(&mut listing.names);
        let spans = &listing.spans;
        let scores = &self.scores;
        let mut order: Vec<usize> = (0..spans.len()).collect();
        order.sort_by(|&a, &b| {
            let an = &names[spans[a].off as usize..(spans[a].off + spans[a].len) as usize];
            let bn = &names[spans[b].off as usize..(spans[b].off + spans[b].len) as usize];
            rank_order(scores[a], an, scores[b], bn)
        });
        let ranked: Vec<_> = order.iter().map(|&i| spans[i]).collect();
        listing.spans = ranked;
        listing.names = names;
        true
    }
}

// One directory as (name, is_dir) pairs; d_type is free and answers is_dir with no stat.
// Sample input: a directory holding "a.txt" and a "sub" directory.
fn read_entries(dir: &std::path::Path) -> Vec<(String, bool)> {
    // corner: an unreadable directory answers empty in silence, as scan.rs's phase one skips an unreadable entry.
    let mut out = Vec::new();
    let Ok(rd) = std::fs::read_dir(dir) else { return out; };
    for entry in rd.flatten() {
        let is_dir = entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false);
        out.push((entry.file_name().to_string_lossy().into_owned(), is_dir));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;

    // Hard rule 9: every path below is inside a sandbox TestDir made and removes itself.
    fn root(d: &TestDir) -> &str {
        d.path().to_str().expect("the sandbox path is utf-8")
    }

    fn walk_all(root: &str, query: &str, hidden: bool) -> (Listing, Search) {
        let mut s = Search::new(root, query, hidden);
        let mut l = Listing::new();
        while !s.step(&mut l) {}
        s.rank(&mut l);
        (l, s)
    }

    // Ranked order, which is the order the client is answered in.
    fn names(l: &Listing) -> Vec<String> {
        (0..l.len()).map(|i| l.name(i).to_string()).collect()
    }

    fn sorted_names(l: &Listing) -> Vec<String> {
        let mut v = names(l);
        v.sort();
        v
    }

    #[test]
    fn matches_are_paths_relative_to_the_root() {
        let d = TestDir::new("rel");
        d.dir("tools/benches");
        d.file("tools/benches/bench-run.sh", "");
        d.file("unrelated.txt", "");

        let (l, s) = walk_all(root(&d), "bench", false);
        assert_eq!(sorted_names(&l), ["tools/benches", "tools/benches/bench-run.sh"]);
        assert_eq!(s.scanned, 4);
        // The directory match keeps its directory bit, so the client can navigate into it.
        for i in 0..l.len() {
            if l.name(i) == "tools/benches" {
                assert!(l.is_dir(i));
            }
        }
    }

    #[test]
    fn a_query_spanning_a_separator_finds_the_file() {
        let d = TestDir::new("span");
        d.dir("downloads");
        d.file("downloads/helper.txt", "");

        let (l, _) = walk_all(root(&d), "dwnhelp", false);
        assert_eq!(names(&l), ["downloads/helper.txt"]);
    }

    #[test]
    fn results_arrive_ranked_rather_than_in_discovery_order() {
        let d = TestDir::new("rank");
        d.dir("bench");
        d.file("bench/unrelated-notes.txt", "");
        d.file("bench.txt", "");

        let (l, _) = walk_all(root(&d), "bench", false);
        // All three carry the query whatever readdir said: the two whose own name is the query lead
        // on score, the shorter of those two leads on the tie, and the parent-only match comes last.
        assert_eq!(names(&l), ["bench", "bench.txt", "bench/unrelated-notes.txt"]);
    }

    #[test]
    fn hidden_is_false_by_default_and_true_descends_dot_directories() {
        let d = TestDir::new("hidden");
        d.dir(".git");
        d.file(".git/bench.log", "");
        d.file("bench.txt", "");

        let (visible, vs) = walk_all(root(&d), "bench", false);
        assert_eq!(sorted_names(&visible), ["bench.txt"]);
        assert_eq!(vs.scanned, 1);

        let (all, _) = walk_all(root(&d), "bench", true);
        assert_eq!(sorted_names(&all), [".git/bench.log", "bench.txt"]);
    }

    #[test]
    fn a_symlink_to_a_parent_directory_is_never_descended() {
        let d = TestDir::new("loop");
        d.dir("sub");
        d.file("sub/bench.txt", "");
        std::os::unix::fs::symlink(d.path(), d.join("sub/up")).unwrap();

        let (l, _) = walk_all(root(&d), "bench", false);
        assert_eq!(sorted_names(&l), ["sub/bench.txt"]);
    }

    #[test]
    fn a_missing_root_finishes_with_nothing_rather_than_failing() {
        let mut s = Search::new("/definitely/not/here", "x", false);
        let mut l = Listing::new();
        assert!(s.step(&mut l));
        assert_eq!(l.len(), 0);
        assert_eq!(s.scanned, 0);
    }

    #[test]
    fn a_step_bounds_each_directory_once_never_once_per_entry() {
        crate::backend::iomount::test_reset();
        let d = TestDir::new("stepcalls");
        for i in 0..DIRS_PER_TICK + 1 {
            d.dir(&format!("d{}", i));
        }
        let mut s = Search::new(root(&d), "zzz", false);
        let mut l = Listing::new();
        // The root read queues every child, so the first step cannot also drain them.
        assert!(!s.step(&mut l));
        assert_eq!(crate::backend::iomount::test_calls(), DIRS_PER_TICK, "one bound per directory read, never one per entry");
    }

    #[test]
    fn a_step_reads_a_bounded_slice_so_a_cancel_is_never_blocked() {
        let d = TestDir::new("slice");
        for i in 0..DIRS_PER_TICK + 3 {
            d.dir(&format!("d{}", i));
        }
        let mut s = Search::new(root(&d), "zzz", false);
        let mut l = Listing::new();
        // The root read queues every child, so the first step cannot also drain them.
        assert!(!s.step(&mut l));
    }

    #[test]
    fn a_listing_the_walk_did_not_fill_is_never_reordered() {
        let s = Search::new("/definitely/not/here", "x", false);
        let mut l = Listing::new();
        l.push("b.txt", false);
        l.push("a.txt", false);
        assert!(!s.rank(&mut l));
        assert_eq!(names(&l), ["b.txt", "a.txt"]);
    }
}
