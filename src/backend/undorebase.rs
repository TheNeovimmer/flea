// A batch of moves applied to a stored document in one walk, by the identity each move replaced.
use super::undo::{ItemIdentity, Step};
use std::collections::HashMap;

// Every identity field a step carries goes through one function, so no walk can miss a kind.
pub(crate) fn rebase_step(step: &mut Step, change: &mut impl FnMut(&mut ItemIdentity)) {
    #[cfg(test)]
    super::undoprobe::visit();
    match step {
        Step::Moved { before, after, .. } => {
            change(before);
            change(after);
        }
        Step::Copied { source, created, .. } => {
            change(source);
            change(created);
        }
        Step::MadeFile { identity, .. } | Step::MadeDir { identity, .. } | Step::Linked { identity, .. } => change(identity),
        _ => {}
    }
}

// Applies (old, new) pairs in order to every identity it is asked about, as a loop of one rebase per pair would.
pub(crate) struct RebaseMap {
    pairs: Vec<(ItemIdentity, ItemIdentity)>,
    // Pair indexes by the (device, inode, kind) of their old identity, ascending; a match needs all three.
    by_item: HashMap<(u64, u64, u32), Vec<usize>>,
}

impl RebaseMap {
    pub(crate) fn new<'a>(pairs: impl IntoIterator<Item = (&'a ItemIdentity, &'a ItemIdentity)>) -> RebaseMap {
        let pairs: Vec<_> = pairs.into_iter().map(|(old, new)| (old.clone(), new.clone())).collect();
        let mut by_item: HashMap<(u64, u64, u32), Vec<usize>> = HashMap::new();
        for (index, (old, _)) in pairs.iter().enumerate() {
            by_item.entry(old.parts()).or_default().push(index);
        }
        RebaseMap { pairs, by_item }
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.pairs.is_empty()
    }

    // The test an entry step uses: the same item and still unchanged since the old record.
    pub(crate) fn moved(&self, identity: &mut ItemIdentity) {
        self.chase(identity, ItemIdentity::unchanged_for_move);
    }

    // The looser test a redo's parent folder uses: the same item, whatever changed in it.
    pub(crate) fn item(&self, identity: &mut ItemIdentity) {
        self.chase(identity, ItemIdentity::same_item);
    }

    // A rewritten identity meets only the later pairs, exactly as the next rebase of a loop would.
    fn chase(&self, identity: &mut ItemIdentity, matches: fn(&ItemIdentity, &ItemIdentity) -> bool) {
        let mut next = 0;
        while let Some(candidates) = self.by_item.get(&identity.parts()) {
            let Some(&found) = candidates.iter().find(|&&index| index >= next && matches(identity, &self.pairs[index].0)) else { return };
            *identity = self.pairs[found].1.clone();
            next = found + 1;
        }
    }
}
