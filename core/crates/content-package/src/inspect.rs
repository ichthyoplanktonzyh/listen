#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InspectLimits {
    pub max_file_count: usize,
    pub max_file_bytes: u64,
    pub max_manifest_bytes: u64,
    pub max_total_bytes: u64,
}

impl Default for InspectLimits {
    fn default() -> Self {
        Self {
            max_file_count: 1_024,
            max_file_bytes: 32 * 1024 * 1024,
            max_manifest_bytes: 4 * 1024 * 1024,
            max_total_bytes: 256 * 1024 * 1024,
        }
    }
}
