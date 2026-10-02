// The system clipboard for files, backend half: a std-only Wayland data-control client.
// See the cb1 brief in .superpowers/038-out/ for the protocol contract.
pub mod wire;
pub mod format;
pub mod control;
pub mod owner;
pub mod reply;
pub mod watch;
pub mod own;
pub mod cli;

// Serialises the tests that borrow process-global Wayland names for a fake socket.
#[cfg(test)]
pub(crate) static ENV_GUARD: std::sync::Mutex<()> = std::sync::Mutex::new(());
