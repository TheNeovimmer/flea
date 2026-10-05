// The menu worker's one pending request: it bounds repeated activation while a registry query runs.
use super::trashmanifest::Cancellation;
use crate::json::field_str;
use std::sync::{Arc, Condvar, Mutex};

pub(super) type MenuJob = (String, Vec<String>, Option<String>, Cancellation);

// What became of a sent job; a displaced or refused job is handed back so its caller can answer it.
pub(super) enum Sent {
    Queued,
    Displaced(MenuJob),
    Busy(MenuJob),
    Closed(MenuJob),
}

// Only a snapshot yields to a newer snapshot; queued work (activate, applications) is never dropped.
fn supersedeable(line: &str) -> bool {
    matches!(field_str(line, "op").as_deref(), Some("snapshot"))
}

#[derive(Default)]
pub(super) struct MenuSlot {
    state: Mutex<MenuSlotState>,
    wake: Condvar,
}

#[derive(Default)]
struct MenuSlotState {
    job: Option<MenuJob>,
    closed: bool,
}

impl MenuSlot {
    pub(super) fn send(&self, job: MenuJob) -> Sent {
        let mut state = self.state.lock().unwrap();
        if state.closed {
            return Sent::Closed(job);
        }
        match state.job.take() {
            None => {
                state.job = Some(job);
                self.wake.notify_one();
                Sent::Queued
            }
            Some(queued) if supersedeable(&job.0) && supersedeable(&queued.0) => {
                state.job = Some(job);
                self.wake.notify_one();
                Sent::Displaced(queued)
            }
            Some(queued) => {
                state.job = Some(queued);
                Sent::Busy(job)
            }
        }
    }
    pub(super) fn take(&self) -> Option<MenuJob> {
        let mut state = self.state.lock().unwrap();
        loop {
            if state.closed {
                return None;
            }
            if let Some(job) = state.job.take() {
                return Some(job);
            }
            state = self.wake.wait(state).unwrap();
        }
    }
    pub(super) fn close(&self) {
        let mut state = self.state.lock().unwrap();
        state.closed = true;
        self.wake.notify_all();
    }
}

// Held by the worker, so a worker that returns or panics closes the slot and later sends are refused.
pub(super) struct CloseOnExit(pub(super) Arc<MenuSlot>);

impl Drop for CloseOnExit {
    fn drop(&mut self) {
        self.0.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot(id: usize) -> MenuJob {
        (format!(r#"{{"c":"menuaction","op":"snapshot","id":{}}}"#, id), Vec::new(), None, Cancellation::default())
    }

    #[test]
    fn a_worker_that_panics_closes_the_slot() {
        let slot = Arc::new(MenuSlot::default());
        let held = Arc::clone(&slot);
        let worker = std::thread::spawn(move || {
            let _close = CloseOnExit(held);
            panic!("the menu worker died");
        });
        assert!(worker.join().is_err());
        assert!(matches!(slot.send(snapshot(1)), Sent::Closed(_)), "a send after the worker died must be refused, never queued unanswered");
    }
}
