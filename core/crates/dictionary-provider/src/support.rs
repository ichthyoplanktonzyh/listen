// Shared resource-file change detection.
// Split out of lib.rs (mechanical decomposition).

use std::time::SystemTime;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ResourceSignature {
    pub(crate) len: u64,
    pub(crate) modified: Option<SystemTime>,
}
