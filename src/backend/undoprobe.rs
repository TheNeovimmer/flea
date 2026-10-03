// Test-only work counters for the shared journal, per thread so parallel tests never see each other's.
use std::cell::Cell;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct Counts {
    pub decodes: u64,
    pub renders: u64,
    // Identity comparisons: one per same_item call.
    pub compares: u64,
    // Stored steps a rebase walk looked at.
    pub visits: u64,
    pub bytes_read: u64,
    pub bytes_written: u64,
}

thread_local! {
    static COUNTS: Cell<Counts> = const { Cell::new(Counts { decodes: 0, renders: 0, compares: 0, visits: 0, bytes_read: 0, bytes_written: 0 }) };
}

fn bump(change: impl FnOnce(&mut Counts)) {
    COUNTS.with(|cell| {
        let mut counts = cell.get();
        change(&mut counts);
        cell.set(counts);
    });
}

pub(crate) fn reset() {
    COUNTS.with(|cell| cell.set(Counts::default()));
}

pub(crate) fn snapshot() -> Counts {
    COUNTS.with(|cell| cell.get())
}

pub(crate) fn decode() {
    bump(|c| c.decodes += 1);
}

pub(crate) fn render() {
    bump(|c| c.renders += 1);
}

pub(crate) fn compare() {
    bump(|c| c.compares += 1);
}

pub(crate) fn visit() {
    bump(|c| c.visits += 1);
}

pub(crate) fn read(bytes: usize) {
    bump(|c| c.bytes_read += bytes as u64);
}

pub(crate) fn wrote(bytes: usize) {
    bump(|c| c.bytes_written += bytes as u64);
}
