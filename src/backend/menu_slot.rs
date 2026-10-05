// The menu worker's one pending request: it bounds repeated activation while a registry query runs.
use super::trashmanifest::Cancellation;
use crate::json::field_str;
use std::sync::{Condvar, Mutex};

pub(super) type MenuJob = (String, Vec<String>, Option<String>, Cancellation);

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
    // A displaced snapshot needs no answer: request() already cancelled its generation.
    pub(super) fn send(&self, job: MenuJob) -> Result<(), MenuJob> {
        let mut state = self.state.lock().unwrap();
        if state.closed {
            return Err(job);
        }
        match state.job.take() {
            None => {
                state.job = Some(job);
                self.wake.notify_one();
                Ok(())
            }
            Some(queued) if supersedeable(&job.0) && supersedeable(&queued.0) => {
                state.job = Some(job);
                self.wake.notify_one();
                Ok(())
            }
            Some(queued) => {
                state.job = Some(queued);
                Err(job)
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
