// Fixed ids are connection-local, and the reader and owner layouts share numbers on purpose.

// Every Wayland connection begins with this display object.
pub(crate) const DISPLAY: u32 = 1;
// Registry and its startup callback precede all bound objects.
pub(crate) const REGISTRY: u32 = 2;
// The registry round trip uses a callback distinct from selection callbacks.
pub(crate) const GLOBALS_CALLBACK: u32 = 3;
// The first bind is always the one seat this client uses.
pub(crate) const SEAT: u32 = 4;
// The second bind is the selected data-control manager.
pub(crate) const MANAGER: u32 = 5;
// Readers and watchers share the same device layout.
pub(crate) const READER_DEVICE: u32 = 6;
// Readers reuse this callback only after its done event.
pub(crate) const READER_CALLBACK: u32 = 7;
// An owner creates its source before its device.
pub(crate) const OWNER_SOURCE: u32 = 6;
// The owner device follows its source on that connection.
pub(crate) const OWNER_DEVICE: u32 = 7;
// Owner startup waits for this callback before reporting ready.
pub(crate) const OWNER_CALLBACK: u32 = 8;

// The seat and the ext manager bind at version 1; the zwlr manager binds at the offered version, capped.
pub(crate) const SEAT_VERSION: u32 = 1;
pub(crate) const EXT_MANAGER_VERSION: u32 = 1;
pub(crate) const ZWLR_MAX_VERSION: u32 = 2;

pub(crate) const DISPLAY_SYNC: u16 = 0;
pub(crate) const DISPLAY_GET_REGISTRY: u16 = 1;
pub(crate) const DISPLAY_ERROR: u16 = 0;
pub(crate) const REGISTRY_BIND: u16 = 0;
pub(crate) const REGISTRY_GLOBAL: u16 = 0;
pub(crate) const CALLBACK_DONE: u16 = 0;
pub(crate) const MANAGER_CREATE_SOURCE: u16 = 0;
pub(crate) const MANAGER_GET_DEVICE: u16 = 1;
pub(crate) const DEVICE_SET_SELECTION: u16 = 0;
pub(crate) const DEVICE_DATA_OFFER: u16 = 0;
pub(crate) const DEVICE_SELECTION: u16 = 1;
pub(crate) const DEVICE_PRIMARY_SELECTION: u16 = 3;
pub(crate) const SOURCE_OFFER: u16 = 0;
pub(crate) const SOURCE_SEND: u16 = 0;
pub(crate) const SOURCE_CANCELLED: u16 = 1;
pub(crate) const OFFER_RECEIVE: u16 = 0;
pub(crate) const OFFER_TYPE: u16 = 0;
pub(crate) const OFFER_DESTROY: u16 = 1;
